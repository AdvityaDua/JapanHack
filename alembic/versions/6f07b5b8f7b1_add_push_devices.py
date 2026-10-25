"""add push device registrations

Revision ID: 6f07b5b8f7b1
Revises: ebaa50809fca
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
import app.db.models


revision: str = "6f07b5b8f7b1"
down_revision: Union[str, None] = "ebaa50809fca"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "push_devices",
        sa.Column("id", app.db.models.UUIDType(), nullable=False),
        sa.Column("user_id", app.db.models.UUIDType(), nullable=False),
        sa.Column("device_id", sa.String(length=255), nullable=False),
        sa.Column("token", sa.String(length=4096), nullable=False),
        sa.Column("platform", sa.String(length=30), nullable=False),
        sa.Column("app_id", sa.String(length=255), nullable=True),
        sa.Column("enabled", sa.Boolean(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("token"),
        sa.UniqueConstraint("user_id", "device_id", name="uq_push_device_user_device"),
    )
    op.create_index("ix_push_devices_user_id", "push_devices", ["user_id"], unique=False)


def downgrade() -> None:
    op.drop_index("ix_push_devices_user_id", table_name="push_devices")
    op.drop_table("push_devices")
