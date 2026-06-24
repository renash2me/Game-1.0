import uuid
from datetime import datetime

from pydantic import BaseModel


class QuestResponse(BaseModel):
    id: uuid.UUID
    character_id: uuid.UUID
    quest_id: str
    status: str
    progress: dict
    accepted_at: datetime | None
    completed_at: datetime | None
    daily_streak: int

    model_config = {"from_attributes": True}


class QuestCatalogEntry(BaseModel):
    quest_id: str
    name: str
    description: str
    type: str
    objectives: list
    rewards: dict
    requirements: dict
    status: str  # "available", "active", "completed", "locked"
    record: QuestResponse | None = None


class AcceptQuestRequest(BaseModel):
    quest_id: str


class DeliverQuestRequest(BaseModel):
    quest_id: str
