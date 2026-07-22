"""Add trip_quality_issue detail table for per-row quality tracking

Revision ID: 0003
Revises: 0002
Create Date: 2026-07-21
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "0003"
down_revision: str | None = "0002"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "trip_quality_issue",
        sa.Column("id", sa.BigInteger(), primary_key=True, autoincrement=True),
        sa.Column("pipeline_run_id", sa.BigInteger(), nullable=True),
        sa.Column("source_month", sa.String(7), nullable=False),
        sa.Column("source_row_number", sa.BigInteger(), nullable=False),
        sa.Column("issue_code", sa.String(64), nullable=False),
        sa.Column("severity", sa.String(16), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()")),
        schema="ops",
    )
    op.create_index("ix_trip_quality_issue_source_month", "trip_quality_issue", ["source_month"], schema="ops")
    op.create_index("ix_trip_quality_issue_issue_code", "trip_quality_issue", ["issue_code"], schema="ops")


def downgrade() -> None:
    op.drop_index("ix_trip_quality_issue_source_month", table_name="trip_quality_issue", schema="ops")
    op.drop_index("ix_trip_quality_issue_issue_code", table_name="trip_quality_issue", schema="ops")
    op.drop_table("trip_quality_issue", schema="ops")
