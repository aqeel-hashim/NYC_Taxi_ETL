"""Add dashboard-only analytics interfaces and keyset index

Revision ID: 0004
Revises: 0003
Create Date: 2026-07-21
"""

from collections.abc import Sequence

from alembic import op

revision: str = "0004"
down_revision: str | None = "0003"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

_VIEWS = (
    "dashboard_trip_metrics",
    "dashboard_trip_explorer",
    "dashboard_publication_state",
    "dashboard_quality_summary",
    "dashboard_fingerprints",
    "dashboard_thresholds",
    "dashboard_alerts",
)
_READONLY_VIEWS = (*_VIEWS, "dashboard_revenue_by_payment_type")

_EXPLORER_INDEXES = {
    "ix_fact_taxi_trips_explorer_keyset": "pickup_at_local, trip_key",
    "ix_fact_taxi_trips_explorer_pickup_zone": "pickup_zone_key, pickup_at_local, trip_key",
    "ix_fact_taxi_trips_explorer_dropoff_zone": "dropoff_zone_key, pickup_at_local, trip_key",
    "ix_fact_taxi_trips_explorer_payment": "payment_type_key, pickup_at_local, trip_key",
    "ix_fact_taxi_trips_explorer_vendor": "vendor_key, pickup_at_local, trip_key",
    "ix_fact_taxi_trips_explorer_rate": "rate_code_key, pickup_at_local, trip_key",
    "ix_fact_taxi_trips_explorer_distance": "distance_millimiles, pickup_at_local, trip_key",
    "ix_fact_taxi_trips_explorer_duration": "duration_seconds, pickup_at_local, trip_key",
    "ix_fact_taxi_trips_explorer_total": "total_amount_cents, pickup_at_local, trip_key",
}


def upgrade() -> None:
    for name, columns in _EXPLORER_INDEXES.items():
        op.execute(f"CREATE INDEX IF NOT EXISTS {name} ON warehouse.fact_taxi_trips ({columns})")
    op.execute("""
        CREATE INDEX IF NOT EXISTS ix_fact_taxi_trips_explorer_quality
        ON warehouse.fact_taxi_trips (pickup_at_local, trip_key)
        WHERE has_quality_issue
    """)

    op.execute("""
        CREATE VIEW analytics.dashboard_trip_metrics AS
        SELECT
            m.pickup_date_key,
            to_date(m.pickup_date_key::text, 'YYYYMMDD') AS pickup_date,
            d.weekday_number,
            d.weekday_name,
            m.pickup_hour,
            z.business_key AS pickup_zone_key,
            z.label AS pickup_zone_label,
            NULLIF(split_part(split_part(z.attributes, 'borough=', 2), ',', 1), '') AS pickup_borough,
            p.business_key AS payment_type_key,
            p.label AS payment_type_label,
            v.business_key AS vendor_key,
            v.label AS vendor_label,
            r.business_key AS rate_code_key,
            r.label AS rate_code_label,
            m.has_statistical_outlier,
            m.has_quality_issue,
            m.trip_count,
            m.passenger_count_sum,
            m.passenger_sum,
            m.distance_millimiles_sum,
            m.duration_seconds_sum,
            m.fare_amount_cents_sum,
            m.extra_cents_sum,
            m.mta_tax_cents_sum,
            m.tip_amount_cents_sum,
            m.tolls_amount_cents_sum,
            m.improvement_surcharge_cents_sum,
            m.total_amount_cents_sum,
            m.congestion_surcharge_cents_sum,
            m.airport_fee_cents_sum
        FROM analytics.trip_metrics_hourly AS m
        JOIN warehouse.dim_date AS d ON d.date_key = m.pickup_date_key
        JOIN warehouse.dim_taxi_zone AS z ON z.surrogate_key = m.pickup_zone_key
        JOIN warehouse.dim_payment_type AS p ON p.surrogate_key = m.payment_type_key
        JOIN warehouse.dim_vendor AS v ON v.surrogate_key = m.vendor_key
        JOIN warehouse.dim_rate_code AS r ON r.surrogate_key = m.rate_code_key
    """)

    op.execute("""
        CREATE VIEW analytics.dashboard_trip_explorer AS
        SELECT
            f.trip_key,
            f.pickup_date_key,
            f.pickup_at_local,
            f.dropoff_at_local,
            pz.business_key AS pickup_zone_key,
            pz.label AS pickup_zone_label,
            NULLIF(split_part(split_part(pz.attributes, 'borough=', 2), ',', 1), '') AS pickup_borough,
            dz.business_key AS dropoff_zone_key,
            dz.label AS dropoff_zone_label,
            p.business_key AS payment_type_key,
            p.label AS payment_type_label,
            v.business_key AS vendor_key,
            v.label AS vendor_label,
            r.business_key AS rate_code_key,
            r.label AS rate_code_label,
            f.passenger_count,
            f.distance_millimiles,
            f.distance_millimiles::numeric / 1000.0 AS distance_miles,
            f.duration_seconds,
            f.duration_seconds::numeric / 60.0 AS duration_minutes,
            f.fare_amount_cents::numeric / 100.0 AS fare_amount_dollars,
            f.tip_amount_cents::numeric / 100.0 AS tip_amount_dollars,
            f.total_amount_cents,
            f.total_amount_cents::numeric / 100.0 AS total_amount_dollars,
            f.has_statistical_outlier,
            f.has_quality_issue
        FROM warehouse.fact_taxi_trips AS f
        JOIN warehouse.dim_taxi_zone AS pz ON pz.surrogate_key = f.pickup_zone_key
        JOIN warehouse.dim_taxi_zone AS dz ON dz.surrogate_key = f.dropoff_zone_key
        JOIN warehouse.dim_payment_type AS p ON p.surrogate_key = f.payment_type_key
        JOIN warehouse.dim_vendor AS v ON v.surrogate_key = f.vendor_key
        JOIN warehouse.dim_rate_code AS r ON r.surrogate_key = f.rate_code_key
    """)

    op.execute("""
        CREATE VIEW analytics.dashboard_publication_state AS
        WITH latest AS (
            SELECT DISTINCT ON (source_month)
                id, source_month, status, finished_at, source_rows, accepted_rows,
                rejected_rows, flagged_rows, source_version, threshold_version_id,
                reference_snapshot_id
            FROM ops.pipeline_run
            ORDER BY source_month, id DESC
        ), version AS (
            SELECT COALESCE(MAX(id), 0)::text AS warehouse_version
            FROM ops.pipeline_run
            WHERE status = 'success'
        )
        SELECT
            l.source_month,
            l.status,
            l.finished_at AS published_at,
            l.source_rows,
            l.accepted_rows,
            l.rejected_rows,
            l.flagged_rows,
            l.accepted_rows AS loaded_rows,
            l.accepted_rows AS published_rows,
            l.source_version,
            l.threshold_version_id,
            l.reference_snapshot_id,
            EXISTS (
                SELECT 1
                FROM ops.source_asset AS s
                WHERE s.source_month = l.source_month
                  AND s.sha256 = l.source_version
                  AND s.is_synthetic
            ) AS is_synthetic,
            version.warehouse_version
        FROM latest AS l
        CROSS JOIN version
    """)

    op.execute("""
        CREATE VIEW analytics.dashboard_quality_summary AS
        SELECT source_month, issue_code, severity, SUM(row_count)::bigint AS row_count
        FROM ops.quality_result_summary
        GROUP BY source_month, issue_code, severity
    """)

    op.execute("""
        CREATE VIEW analytics.dashboard_fingerprints AS
        SELECT DISTINCT ON (source_month)
            source_month, sha256, parquet_schema_fingerprint, byte_size, row_count,
            is_synthetic, ingested_at
        FROM ops.source_asset
        ORDER BY source_month, ingested_at DESC
    """)

    op.execute("""
        CREATE VIEW analytics.dashboard_thresholds AS
        SELECT DISTINCT ON (source_month)
            source_month,
            threshold_version_id,
            reference_snapshot_id,
            NULL::integer AS k,
            NULL::numeric AS normalized_rank_error,
            NULL::text AS baseline_months
        FROM ops.pipeline_run
        WHERE status = 'success'
        ORDER BY source_month, id DESC
    """)

    op.execute("""
        CREATE VIEW analytics.dashboard_alerts AS
        SELECT
            COALESCE(finished_at, started_at) AS occurred_at,
            'pipeline'::text AS source,
            status AS severity,
            dag_id || ' / ' || run_id AS event_summary
        FROM ops.pipeline_run
        WHERE status <> 'success'
    """)

    op.execute("REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA warehouse, analytics, ops FROM taxi_dashboard_readonly")
    op.execute("REVOKE ALL PRIVILEGES ON SCHEMA warehouse, ops FROM taxi_dashboard_readonly")
    op.execute("GRANT USAGE ON SCHEMA analytics TO taxi_dashboard_readonly")
    op.execute(
        f"GRANT SELECT ON {', '.join(f'analytics.{view}' for view in _READONLY_VIEWS)} TO taxi_dashboard_readonly"
    )
    op.execute("ALTER ROLE taxi_dashboard_readonly SET default_transaction_read_only = on")
    op.execute("ALTER ROLE taxi_dashboard_readonly SET statement_timeout = '1500ms'")


def downgrade() -> None:
    op.execute("ALTER ROLE taxi_dashboard_readonly RESET statement_timeout")
    op.execute("ALTER ROLE taxi_dashboard_readonly RESET default_transaction_read_only")
    for view in reversed(_VIEWS):
        op.execute(f"DROP VIEW IF EXISTS analytics.{view}")
    op.execute("DROP INDEX IF EXISTS warehouse.ix_fact_taxi_trips_explorer_quality")
    for name in reversed(_EXPLORER_INDEXES):
        op.execute(f"DROP INDEX IF EXISTS warehouse.{name}")
    op.execute("GRANT USAGE ON SCHEMA warehouse, analytics TO taxi_dashboard_readonly")
    op.execute("GRANT SELECT ON ALL TABLES IN SCHEMA warehouse, analytics TO taxi_dashboard_readonly")
