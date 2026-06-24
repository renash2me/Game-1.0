"""Create players and characters tables

Revision ID: 001
Revises:
Create Date: 2026-06-24 00:00:00.000000
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "001"
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "players",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("username", sa.String(64), nullable=False),
        sa.Column("email", sa.String(255), nullable=False),
        sa.Column("password_hash", sa.String(255), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("last_login", sa.DateTime(timezone=True), nullable=True),
        sa.Column("is_active", sa.Boolean, nullable=False, server_default="true"),
    )
    op.create_index("ix_players_username", "players", ["username"], unique=True)
    op.create_index("ix_players_email", "players", ["email"], unique=True)

    op.create_table(
        "characters",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("player_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("players.id"), nullable=False),
        sa.Column("name", sa.String(64), nullable=False),
        sa.Column("class_id", sa.String(32), nullable=False, server_default="novice"),
        sa.Column("class_tier", sa.Integer, nullable=False, server_default="0"),
        sa.Column("level", sa.Integer, nullable=False, server_default="1"),
        sa.Column("xp", sa.BigInteger, nullable=False, server_default="0"),
        sa.Column("xp_to_next", sa.BigInteger, nullable=False, server_default="100"),
        sa.Column("str", sa.Integer, nullable=False, server_default="1"),
        sa.Column("agi", sa.Integer, nullable=False, server_default="1"),
        sa.Column("vit", sa.Integer, nullable=False, server_default="1"),
        sa.Column("int_", sa.Integer, nullable=False, server_default="1"),
        sa.Column("dex", sa.Integer, nullable=False, server_default="1"),
        sa.Column("luk", sa.Integer, nullable=False, server_default="1"),
        sa.Column("stat_points", sa.Integer, nullable=False, server_default="0"),
        sa.Column("skill_points", sa.Integer, nullable=False, server_default="0"),
        sa.Column("hp", sa.Integer, nullable=False, server_default="100"),
        sa.Column("hp_max", sa.Integer, nullable=False, server_default="100"),
        sa.Column("sp", sa.Integer, nullable=False, server_default="50"),
        sa.Column("sp_max", sa.Integer, nullable=False, server_default="50"),
        sa.Column("void_gauge", sa.Integer, nullable=False, server_default="0"),
        sa.Column("void_gauge_max", sa.Integer, nullable=False, server_default="100"),
        sa.Column("current_map", sa.String(64), nullable=False, server_default="starter_village"),
        sa.Column("pos_x", sa.Float, nullable=False, server_default="0.0"),
        sa.Column("pos_y", sa.Float, nullable=False, server_default="0.0"),
        sa.Column("zeny", sa.BigInteger, nullable=False, server_default="0"),
        sa.Column("aptitude_data", postgresql.JSONB, nullable=False, server_default="{}"),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
    )
    op.create_index("ix_characters_name", "characters", ["name"], unique=True)
    op.create_index("ix_characters_player_id", "characters", ["player_id"])


def downgrade() -> None:
    op.drop_table("characters")
    op.drop_table("players")
