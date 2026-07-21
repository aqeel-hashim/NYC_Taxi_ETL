"""Security roles and dashboard views

Revision ID: 0002
Revises: 0001
Create Date: 2026-07-21
"""

from collections.abc import Sequence

from alembic import op

revision: str = "0002"
down_revision: str | None = "0001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    for role in ("taxi_migrator", "taxi_loader", "taxi_dashboard_readonly"):
        op.execute(f"DO $$ BEGIN CREATE ROLE {role}; EXCEPTION WHEN duplicate_object THEN NULL; END $$")

    op.execute("GRANT USAGE ON SCHEMA warehouse TO taxi_dashboard_readonly")
    op.execute("GRANT SELECT ON ALL TABLES IN SCHEMA warehouse TO taxi_dashboard_readonly")
    op.execute("GRANT USAGE ON SCHEMA analytics TO taxi_dashboard_readonly")
    op.execute("GRANT SELECT ON ALL TABLES IN SCHEMA analytics TO taxi_dashboard_readonly")

    op.execute("GRANT USAGE ON SCHEMA warehouse, analytics, ops TO taxi_loader")
    op.execute("GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA warehouse, analytics, ops TO taxi_loader")
    op.execute("GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA warehouse, analytics, ops TO taxi_loader")

    op.execute("""
        CREATE OR REPLACE VIEW analytics.dashboard_revenue_by_payment_type AS
        SELECT p.business_key AS payment_type_key, p.label AS payment_type_label,
            ROUND(SUM(f.total_amount_cents)::numeric / 100.0, 2) AS total_revenue_dollars,
            COUNT(*) AS trip_count
        FROM warehouse.fact_taxi_trips AS f
        INNER JOIN warehouse.dim_payment_type AS p ON f.payment_type_key = p.surrogate_key
        WHERE NOT f.has_statistical_outlier
        GROUP BY p.business_key, p.label
    """)
    op.execute("GRANT SELECT ON analytics.dashboard_revenue_by_payment_type TO taxi_dashboard_readonly")


def downgrade() -> None:
    op.execute("DROP VIEW IF EXISTS analytics.dashboard_revenue_by_payment_type")
    for role in ("taxi_dashboard_readonly", "taxi_loader"):
        op.execute(f"REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA warehouse, analytics, ops FROM {role}")
        op.execute(f"REVOKE ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA warehouse, analytics, ops FROM {role}")
        op.execute(f"REVOKE ALL PRIVILEGES ON SCHEMA warehouse, analytics, ops FROM {role}")
    for role in ("taxi_dashboard_readonly", "taxi_loader", "taxi_migrator"):
        op.execute(f"DROP ROLE IF EXISTS {role}")
