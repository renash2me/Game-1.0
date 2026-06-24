import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.deps import get_current_player
from app.data.loader import get_items
from app.database import get_session
from app.models.character import Character
from app.models.inventory import InventoryItem
from app.models.player import Player
from app.schemas.inventory import (
    EquipRequest,
    InventoryItemResponse,
    RefineRequest,
    SocketCardRequest,
    UnequipRequest,
)
from app.systems.refinement import attempt_refinement, can_refine, zeny_cost

router = APIRouter(prefix="/api/inventory", tags=["inventory"])

EQUIP_SLOTS = {"weapon", "offhand", "head", "body", "legs", "feet", "accessory1", "accessory2"}


# ── Helpers ───────────────────────────────────────────────────────────────────

async def _get_char(
    character_id: uuid.UUID,
    player: Player,
    session: AsyncSession,
) -> Character:
    result = await session.execute(
        select(Character).where(
            Character.id == character_id,
            Character.player_id == player.id,
        )
    )
    char = result.scalar_one_or_none()
    if not char:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Personagem não encontrado")
    return char


async def _get_inv_item(
    inv_id: uuid.UUID,
    character_id: uuid.UUID,
    session: AsyncSession,
) -> InventoryItem:
    result = await session.execute(
        select(InventoryItem).where(
            InventoryItem.id == inv_id,
            InventoryItem.character_id == character_id,
        )
    )
    item = result.scalar_one_or_none()
    if not item:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Item não encontrado no inventário")
    return item


async def _next_slot(character_id: uuid.UUID, session: AsyncSession) -> int:
    result = await session.execute(
        select(InventoryItem.slot_index).where(
            InventoryItem.character_id == character_id,
            InventoryItem.slot_index.isnot(None),
        )
    )
    used = {row[0] for row in result.all()}
    slot = 0
    while slot in used:
        slot += 1
    return slot


async def add_item_to_inventory(
    character_id: uuid.UUID,
    item_id: str,
    quantity: int,
    session: AsyncSession,
) -> InventoryItem:
    catalog = get_items()
    item_data = catalog.get(item_id, {})
    stackable = item_data.get("type") in ("material", "consumable", "zeny_bag")

    if stackable:
        result = await session.execute(
            select(InventoryItem).where(
                InventoryItem.character_id == character_id,
                InventoryItem.item_id == item_id,
                InventoryItem.is_equipped == False,
            )
        )
        existing = result.scalar_one_or_none()
        if existing:
            existing.quantity += quantity
            return existing

    slot = await _next_slot(character_id, session)
    inv = InventoryItem(
        character_id=character_id,
        item_id=item_id,
        quantity=quantity,
        slot_index=slot,
    )
    session.add(inv)
    return inv


# ── Endpoints ─────────────────────────────────────────────────────────────────

@router.get("/{character_id}", response_model=list[InventoryItemResponse])
async def list_inventory(
    character_id: uuid.UUID,
    player: Player = Depends(get_current_player),
    session: AsyncSession = Depends(get_session),
):
    await _get_char(character_id, player, session)
    result = await session.execute(
        select(InventoryItem)
        .where(InventoryItem.character_id == character_id)
        .order_by(InventoryItem.is_equipped.desc(), InventoryItem.slot_index)
    )
    return result.scalars().all()


@router.post("/{character_id}/equip", response_model=InventoryItemResponse)
async def equip_item(
    character_id: uuid.UUID,
    body: EquipRequest,
    player: Player = Depends(get_current_player),
    session: AsyncSession = Depends(get_session),
):
    char = await _get_char(character_id, player, session)
    inv_item = await _get_inv_item(body.inventory_item_id, character_id, session)

    if inv_item.is_equipped:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Item já está equipado")

    catalog = get_items()
    item_data = catalog.get(inv_item.item_id, {})
    target_slot = item_data.get("equip_slot")

    if not target_slot:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Este item não pode ser equipado")

    req_level = item_data.get("requirements", {}).get("level", 1)
    if char.level < req_level:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            f"Requer nível {req_level} (seu nível: {char.level})",
        )

    # Desequipa o que estiver no slot
    result = await session.execute(
        select(InventoryItem).where(
            InventoryItem.character_id == character_id,
            InventoryItem.is_equipped == True,
            InventoryItem.equip_slot == target_slot,
        )
    )
    old = result.scalar_one_or_none()
    if old:
        old.is_equipped = False
        old.equip_slot = None
        old.slot_index = await _next_slot(character_id, session)

    inv_item.is_equipped = True
    inv_item.equip_slot = target_slot
    inv_item.slot_index = None
    await session.commit()
    await session.refresh(inv_item)
    return inv_item


@router.post("/{character_id}/unequip", response_model=InventoryItemResponse)
async def unequip_item(
    character_id: uuid.UUID,
    body: UnequipRequest,
    player: Player = Depends(get_current_player),
    session: AsyncSession = Depends(get_session),
):
    await _get_char(character_id, player, session)
    inv_item = await _get_inv_item(body.inventory_item_id, character_id, session)

    if not inv_item.is_equipped:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Item não está equipado")

    inv_item.is_equipped = False
    inv_item.equip_slot = None
    inv_item.slot_index = await _next_slot(character_id, session)
    await session.commit()
    await session.refresh(inv_item)
    return inv_item


@router.post("/{character_id}/refine")
async def refine_item(
    character_id: uuid.UUID,
    body: RefineRequest,
    player: Player = Depends(get_current_player),
    session: AsyncSession = Depends(get_session),
):
    char = await _get_char(character_id, player, session)
    inv_item = await _get_inv_item(body.inventory_item_id, character_id, session)

    catalog = get_items()
    item_data = catalog.get(inv_item.item_id, {})
    item_type = item_data.get("type", "")

    ok, reason = can_refine(item_type, inv_item.refinement)
    if not ok:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, reason)

    cost = zeny_cost(inv_item.refinement)
    if char.zeny < cost:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            f"Zeny insuficiente. Custo: {cost}, você tem: {char.zeny}",
        )

    result = attempt_refinement(inv_item.refinement)
    char.zeny -= result.zeny_cost
    inv_item.refinement = result.new_refinement

    await session.commit()
    await session.refresh(inv_item)

    return {
        "success": result.success,
        "refinement": inv_item.refinement,
        "zeny_spent": result.zeny_cost,
        "zeny_remaining": char.zeny,
        "item": InventoryItemResponse.model_validate(inv_item),
    }


@router.post("/{character_id}/socket-card", response_model=InventoryItemResponse)
async def socket_card(
    character_id: uuid.UUID,
    body: SocketCardRequest,
    player: Player = Depends(get_current_player),
    session: AsyncSession = Depends(get_session),
):
    await _get_char(character_id, player, session)
    inv_item = await _get_inv_item(body.inventory_item_id, character_id, session)
    card_item = await _get_inv_item(body.card_inventory_item_id, character_id, session)

    catalog = get_items()
    item_data = catalog.get(inv_item.item_id, {})
    card_data = catalog.get(card_item.item_id, {})

    if card_data.get("type") != "card":
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "O item selecionado não é uma carta")

    max_slots = item_data.get("slots", 0)
    current_cards: list = list(inv_item.cards or [])

    if len(current_cards) >= max_slots:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            f"Item não tem slots disponíveis (máx: {max_slots})",
        )

    current_cards.append(card_item.item_id)
    inv_item.cards = current_cards

    # Carta é consumida
    if card_item.quantity > 1:
        card_item.quantity -= 1
    else:
        await session.delete(card_item)

    await session.commit()
    await session.refresh(inv_item)
    return inv_item
