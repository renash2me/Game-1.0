import uuid
from datetime import datetime

from pydantic import BaseModel


class InventoryItemResponse(BaseModel):
    id: uuid.UUID
    character_id: uuid.UUID
    item_id: str
    quantity: int
    slot_index: int | None
    is_equipped: bool
    equip_slot: str | None
    refinement: int
    cards: list
    enchants: list
    created_at: datetime

    model_config = {"from_attributes": True}


class EquipRequest(BaseModel):
    inventory_item_id: uuid.UUID


class UnequipRequest(BaseModel):
    inventory_item_id: uuid.UUID


class RefineRequest(BaseModel):
    inventory_item_id: uuid.UUID


class SocketCardRequest(BaseModel):
    inventory_item_id: uuid.UUID
    card_inventory_item_id: uuid.UUID
