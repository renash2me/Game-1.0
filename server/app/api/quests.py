import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.deps import get_current_player
from app.data.loader import get_quests
from app.database import get_session
from app.models.character import Character
from app.models.player import Player
from app.models.quest import Quest
from app.schemas.quest import (
    AcceptQuestRequest,
    DeliverQuestRequest,
    QuestCatalogEntry,
    QuestResponse,
)
from app.systems.quest_engine import accept_quest, deliver_quest

router = APIRouter(prefix="/api/quests", tags=["quests"])


async def _get_char(character_id: uuid.UUID, player: Player, session: AsyncSession) -> Character:
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


@router.get("/{character_id}", response_model=list[QuestCatalogEntry])
async def list_quests(
    character_id: uuid.UUID,
    player: Player = Depends(get_current_player),
    session: AsyncSession = Depends(get_session),
):
    """Lista quests do catálogo com status atual do personagem."""
    char = await _get_char(character_id, player, session)

    result = await session.execute(
        select(Quest).where(Quest.character_id == character_id)
    )
    records = {q.quest_id: q for q in result.scalars().all()}

    today = datetime.now(timezone.utc).date()
    catalog = get_quests()
    entries: list[QuestCatalogEntry] = []

    for quest_data in catalog.values():
        qid = quest_data["id"]
        record = records.get(qid)
        req_level = quest_data.get("requirements", {}).get("level", 1)

        if char.level < req_level:
            quest_status = "locked"
        elif record is None:
            quest_status = "available"
        elif record.status == "active":
            quest_status = "active"
        elif record.status == "completed":
            if quest_data.get("type") == "daily":
                if record.completed_at and record.completed_at.date() < today:
                    quest_status = "available"
                else:
                    quest_status = "completed"
            else:
                quest_status = "completed"
        else:
            quest_status = record.status

        entries.append(QuestCatalogEntry(
            quest_id=qid,
            name=quest_data["name"],
            description=quest_data["description"],
            type=quest_data["type"],
            objectives=quest_data["objectives"],
            rewards=quest_data["rewards"],
            requirements=quest_data.get("requirements", {}),
            status=quest_status,
            record=QuestResponse.model_validate(record) if record else None,
        ))

    return entries


@router.post("/{character_id}/accept", response_model=QuestResponse, status_code=status.HTTP_201_CREATED)
async def accept(
    character_id: uuid.UUID,
    body: AcceptQuestRequest,
    player: Player = Depends(get_current_player),
    session: AsyncSession = Depends(get_session),
):
    char = await _get_char(character_id, player, session)
    record, error = await accept_quest(char, body.quest_id, session)

    if error:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, error)

    await session.commit()
    await session.refresh(record)
    return record


@router.post("/{character_id}/deliver")
async def deliver(
    character_id: uuid.UUID,
    body: DeliverQuestRequest,
    player: Player = Depends(get_current_player),
    session: AsyncSession = Depends(get_session),
):
    char = await _get_char(character_id, player, session)
    result, error = await deliver_quest(char, body.quest_id, session)

    if error:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, error)

    # Adiciona itens ao inventário
    if result.get("items"):
        from app.api.inventory import add_item_to_inventory
        for item_entry in result["items"]:
            await add_item_to_inventory(
                character_id,
                item_entry["item_id"],
                item_entry.get("quantity", 1),
                session,
            )

    await session.commit()
    return result
