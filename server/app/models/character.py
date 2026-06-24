import uuid
from datetime import datetime, timezone

from sqlalchemy import BigInteger, DateTime, Float, ForeignKey, Integer, String
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


def _now() -> datetime:
    return datetime.now(timezone.utc)


class Character(Base):
    __tablename__ = "characters"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    player_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("players.id"), nullable=False, index=True)
    name: Mapped[str] = mapped_column(String(64), unique=True, nullable=False, index=True)
    class_id: Mapped[str] = mapped_column(String(32), nullable=False, default="novice")
    class_tier: Mapped[int] = mapped_column(Integer, default=0)
    level: Mapped[int] = mapped_column(Integer, default=1)
    xp: Mapped[int] = mapped_column(BigInteger, default=0)
    xp_to_next: Mapped[int] = mapped_column(BigInteger, default=100)

    # Stats base — atributo Python → nome da coluna SQL
    str_stat: Mapped[int] = mapped_column("str", Integer, default=1)
    agi: Mapped[int] = mapped_column(Integer, default=1)
    vit: Mapped[int] = mapped_column(Integer, default=1)
    int_stat: Mapped[int] = mapped_column("int_", Integer, default=1)
    dex: Mapped[int] = mapped_column(Integer, default=1)
    luk: Mapped[int] = mapped_column(Integer, default=1)
    stat_points: Mapped[int] = mapped_column(Integer, default=0)
    skill_points: Mapped[int] = mapped_column(Integer, default=0)

    hp: Mapped[int] = mapped_column(Integer, default=100)
    hp_max: Mapped[int] = mapped_column(Integer, default=100)
    sp: Mapped[int] = mapped_column(Integer, default=50)
    sp_max: Mapped[int] = mapped_column(Integer, default=50)
    void_gauge: Mapped[int] = mapped_column(Integer, default=0)
    void_gauge_max: Mapped[int] = mapped_column(Integer, default=100)

    current_map: Mapped[str] = mapped_column(String(64), default="starter_village")
    pos_x: Mapped[float] = mapped_column(Float, default=0.0)
    pos_y: Mapped[float] = mapped_column(Float, default=0.0)
    zeny: Mapped[int] = mapped_column(BigInteger, default=0)
    aptitude_data: Mapped[dict] = mapped_column(JSONB, default=dict)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)

    player: Mapped["Player"] = relationship("Player", back_populates="characters")
