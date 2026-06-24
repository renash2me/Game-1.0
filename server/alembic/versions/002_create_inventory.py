"""Create inventory table

Revision ID: 002
Revises: 001
Create Date: 2026-06-24 00:00:00.000000
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "002"
down_revision: Union[str, None] = "001"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "inventory",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("character_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("characters.id"), nullable=False),
        sa.Column("item_id", sa.String(64), nullable=False),
        sa.Column("quantity", sa.Integer, nullable=False, server_default="1"),
        sa.Column("slot_index", sa.Integer, nullable=True),
        sa.Column("is_equipped", sa.Boolean, nullable=False, server_default="false"),
        sa.Column("equip_slot", sa.String(32), nullable=True),
        sa.Column("refinement", sa.Integer, nullable=False, server_default="0"),
        sa.Column("cards", postgresql.JSONB, nullable=False, server_default="[]"),
        sa.Column("enchants", postgresql.JSONB, nullable=False, server_default="[]"),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
    )
    op.create_index("ix_inventory_character_id", "inventory", ["character_id"])


def downgrade() -> None:
    op.drop_table("inventory")
