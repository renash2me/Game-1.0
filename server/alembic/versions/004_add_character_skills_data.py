"""Add skills_data column to characters

Revision ID: 004
Revises: 003
Create Date: 2026-06-24 00:00:00.000000
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects.postgresql import JSONB

revision: str = "004"
down_revision: Union[str, None] = "003"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "characters",
        sa.Column("skills_data", JSONB(), nullable=False, server_default="{}"),
    )


def downgrade() -> None:
    op.drop_column("characters", "skills_data")
