import uuid
from datetime import datetime, timezone

from sqlalchemy import Boolean, DateTime, ForeignKey, Integer, String
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


def _now() -> datetime:
    return datetime.now(timezone.utc)


class InventoryItem(Base):
    __tablename__ = "inventory"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    character_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("characters.id"), nullable=False, index=True
    )
    item_id: Mapped[str] = mapped_column(String(64), nullable=False)
    quantity: Mapped[int] = mapped_column(Integer, default=1)
    slot_index: Mapped[int | None] = mapped_column(Integer, nullable=True)
    is_equipped: Mapped[bool] = mapped_column(Boolean, default=False)
    equip_slot: Mapped[str | None] = mapped_column(String(32), nullable=True)
    refinement: Mapped[int] = mapped_column(Integer, default=0)
    cards: Mapped[list] = mapped_column(JSONB, default=list)
    enchants: Mapped[list] = mapped_column(JSONB, default=list)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)

    character: Mapped["Character"] = relationship("Character", back_populates="inventory")
