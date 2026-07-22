"""Initial star schema

Revision ID: 0001
Revises:
Create Date: 2026-07-20
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "0001"
down_revision: str | None = None
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.execute("CREATE SCHEMA IF NOT EXISTS warehouse")
    op.execute("CREATE SCHEMA IF NOT EXISTS analytics")
    op.execute("CREATE SCHEMA IF NOT EXISTS ops")
    op.execute("CREATE EXTENSION IF NOT EXISTS btree_gist")

    # dim_date
    op.create_table(
        "dim_date",
        sa.Column("date_key", sa.Integer(), primary_key=True),
        sa.Column("calendar_date", sa.Date(), nullable=False),
        sa.Column("year", sa.SmallInteger(), nullable=False),
        sa.Column("quarter", sa.SmallInteger(), nullable=False),
        sa.Column("month", sa.SmallInteger(), nullable=False),
        sa.Column("month_name", sa.String(10), nullable=False),
        sa.Column("iso_week", sa.SmallInteger(), nullable=False),
        sa.Column("iso_year", sa.SmallInteger(), nullable=False),
        sa.Column("day_of_month", sa.SmallInteger(), nullable=False),
        sa.Column("day_of_year", sa.SmallInteger(), nullable=False),
        sa.Column("weekday_number", sa.SmallInteger(), nullable=False),
        sa.Column("weekday_name", sa.String(10), nullable=False),
        sa.Column("is_weekend", sa.Boolean(), nullable=False),
        schema="warehouse",
    )

    # dim_time
    op.create_table(
        "dim_time",
        sa.Column("time_key", sa.SmallInteger(), primary_key=True),
        sa.Column("hour", sa.SmallInteger(), nullable=False),
        sa.Column("minute", sa.SmallInteger(), nullable=False),
        sa.Column("quarter_hour", sa.SmallInteger(), nullable=False),
        sa.Column("hour_label", sa.String(8), nullable=False),
        sa.Column("daypart", sa.String(16), nullable=False),
        schema="warehouse",
    )

    # SCD2 dimensions
    for table_name in ("dim_taxi_zone", "dim_payment_type", "dim_vendor", "dim_rate_code"):
        op.create_table(
            table_name,
            sa.Column("surrogate_key", sa.Integer(), autoincrement=True, nullable=False),
            sa.Column("business_key", sa.Integer(), nullable=False),
            sa.Column("label", sa.String(128), nullable=False),
            sa.Column("attributes", sa.String(256), nullable=True),
            sa.Column("reference_snapshot_id", sa.String(64), nullable=True),
            sa.Column("row_hash", sa.String(64), nullable=True),
            sa.Column("observed_from", sa.DateTime(timezone=True), nullable=False),
            sa.Column("observed_to", sa.DateTime(timezone=True), nullable=True),
            sa.Column("is_current", sa.Boolean(), nullable=False),
            sa.PrimaryKeyConstraint("surrogate_key"),
            schema="warehouse",
        )
        op.create_index(f"ix_{table_name}_business_key", table_name, ["business_key"], schema="warehouse")
        op.create_index(f"ix_{table_name}_current", table_name, ["is_current"], schema="warehouse")

        # exclusion constraint: no overlap on observed range per business key
        op.execute(f"""
            ALTER TABLE warehouse.{table_name}
            ADD CONSTRAINT {table_name}_no_overlap
            EXCLUDE USING gist (
                business_key WITH =,
                tstzrange(observed_from, observed_to, '[)'::text) WITH &&
            )
        """)
        # partial unique: one current row per business key
        op.create_index(
            f"{table_name}_one_current",
            table_name,
            ["business_key"],
            unique=True,
            postgresql_where=sa.text("is_current IS TRUE"),
            schema="warehouse",
        )

    # fact_taxi_trips (partitioned)
    op.execute("""
        CREATE TABLE warehouse.fact_taxi_trips (
            trip_key BIGSERIAL,
            pickup_date_key INTEGER NOT NULL,
            dropoff_date_key INTEGER NOT NULL,
            pickup_time_key SMALLINT NOT NULL,
            dropoff_time_key SMALLINT NOT NULL,
            pickup_zone_key INTEGER NOT NULL,
            dropoff_zone_key INTEGER NOT NULL,
            payment_type_key INTEGER NOT NULL,
            vendor_key INTEGER NOT NULL,
            rate_code_key INTEGER NOT NULL,
            pickup_at_local TIMESTAMP WITHOUT TIME ZONE NOT NULL,
            dropoff_at_local TIMESTAMP WITHOUT TIME ZONE NOT NULL,
            duration_seconds BIGINT NOT NULL,
            passenger_count SMALLINT,
            distance_millimiles BIGINT NOT NULL,
            store_and_fwd_flag VARCHAR(1),
            fare_amount_cents BIGINT NOT NULL,
            extra_cents BIGINT,
            mta_tax_cents BIGINT,
            tip_amount_cents BIGINT,
            tolls_amount_cents BIGINT,
            improvement_surcharge_cents BIGINT,
            total_amount_cents BIGINT NOT NULL,
            congestion_surcharge_cents BIGINT,
            airport_fee_cents BIGINT,
            source_asset_id VARCHAR(128) NOT NULL,
            source_row_number BIGINT NOT NULL,
            source_version VARCHAR(64) NOT NULL,
            threshold_version_id VARCHAR(64),
            reference_snapshot_id VARCHAR(64),
            publish_run_id VARCHAR(64),
            has_statistical_outlier BOOLEAN NOT NULL DEFAULT FALSE,
            has_quality_issue BOOLEAN NOT NULL DEFAULT FALSE,
            PRIMARY KEY (pickup_date_key, trip_key)
        ) PARTITION BY RANGE (pickup_date_key)
    """)
    op.execute("""
        CREATE TABLE warehouse.fact_taxi_trips_2023_01
        PARTITION OF warehouse.fact_taxi_trips
        FOR VALUES FROM (20230101) TO (20230201)
    """)
    op.execute("""
        CREATE TABLE warehouse.fact_taxi_trips_2023_02
        PARTITION OF warehouse.fact_taxi_trips
        FOR VALUES FROM (20230201) TO (20230301)
    """)
    op.execute("""
        ALTER TABLE warehouse.fact_taxi_trips
        ADD CONSTRAINT uq_fact_taxi_trips_source_row
        UNIQUE (pickup_date_key, source_asset_id, source_version, source_row_number)
    """)
    for column, table in (
        ("pickup_date_key", "dim_date"),
        ("dropoff_date_key", "dim_date"),
        ("pickup_time_key", "dim_time"),
        ("dropoff_time_key", "dim_time"),
        ("pickup_zone_key", "dim_taxi_zone"),
        ("dropoff_zone_key", "dim_taxi_zone"),
        ("payment_type_key", "dim_payment_type"),
        ("vendor_key", "dim_vendor"),
        ("rate_code_key", "dim_rate_code"),
    ):
        target_column = "date_key" if table == "dim_date" else "time_key" if table == "dim_time" else "surrogate_key"
        op.execute(f"""
            ALTER TABLE warehouse.fact_taxi_trips
            ADD CONSTRAINT fk_fact_taxi_trips_{column}
            FOREIGN KEY ({column}) REFERENCES warehouse.{table} ({target_column})
        """)

    # analytics.trip_metrics_hourly (partitioned)
    op.execute("""
        CREATE TABLE analytics.trip_metrics_hourly (
            pickup_date_key INTEGER NOT NULL,
            pickup_hour SMALLINT NOT NULL,
            pickup_zone_key INTEGER NOT NULL,
            payment_type_key INTEGER NOT NULL,
            vendor_key INTEGER NOT NULL,
            rate_code_key INTEGER NOT NULL,
            has_statistical_outlier BOOLEAN NOT NULL,
            has_quality_issue BOOLEAN NOT NULL,
            trip_count BIGINT NOT NULL,
            passenger_count_sum BIGINT NOT NULL,
            passenger_sum BIGINT,
            distance_millimiles_sum BIGINT NOT NULL,
            duration_seconds_sum BIGINT NOT NULL,
            fare_amount_cents_sum BIGINT NOT NULL,
            extra_cents_sum BIGINT DEFAULT 0,
            mta_tax_cents_sum BIGINT DEFAULT 0,
            tip_amount_cents_sum BIGINT DEFAULT 0,
            tolls_amount_cents_sum BIGINT DEFAULT 0,
            improvement_surcharge_cents_sum BIGINT DEFAULT 0,
            total_amount_cents_sum BIGINT NOT NULL,
            congestion_surcharge_cents_sum BIGINT DEFAULT 0,
            airport_fee_cents_sum BIGINT DEFAULT 0,
            PRIMARY KEY (pickup_date_key, pickup_hour, pickup_zone_key, payment_type_key,
                         vendor_key, rate_code_key, has_statistical_outlier, has_quality_issue)
        ) PARTITION BY RANGE (pickup_date_key)
    """)
    op.execute("""
        CREATE TABLE analytics.trip_metrics_hourly_2023_01
        PARTITION OF analytics.trip_metrics_hourly
        FOR VALUES FROM (20230101) TO (20230201)
    """)
    op.execute("""
        CREATE TABLE analytics.trip_metrics_hourly_2023_02
        PARTITION OF analytics.trip_metrics_hourly
        FOR VALUES FROM (20230201) TO (20230301)
    """)

    # ops tables
    op.create_table(
        "pipeline_run",
        sa.Column("id", sa.BigInteger(), primary_key=True, autoincrement=True),
        sa.Column("dag_id", sa.String(128), nullable=False),
        sa.Column("run_id", sa.String(128), nullable=False),
        sa.Column("task_id", sa.String(128), nullable=True),
        sa.Column("source_month", sa.String(7), nullable=False),
        sa.Column("status", sa.String(32), nullable=False),
        sa.Column("started_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("finished_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("duration_seconds", sa.Float(), nullable=True),
        sa.Column("source_rows", sa.BigInteger(), nullable=True),
        sa.Column("accepted_rows", sa.BigInteger(), nullable=True),
        sa.Column("rejected_rows", sa.BigInteger(), nullable=True),
        sa.Column("flagged_rows", sa.BigInteger(), nullable=True),
        sa.Column("source_version", sa.String(64), nullable=True),
        sa.Column("threshold_version_id", sa.String(64), nullable=True),
        sa.Column("reference_snapshot_id", sa.String(64), nullable=True),
        sa.Column("error_summary", sa.Text(), nullable=True),
        schema="ops",
    )

    op.create_table(
        "source_asset",
        sa.Column("id", sa.String(128), primary_key=True),
        sa.Column("source_month", sa.String(7), nullable=False),
        sa.Column("source_url", sa.Text(), nullable=False),
        sa.Column("byte_size", sa.BigInteger(), nullable=True),
        sa.Column("sha256", sa.String(64), nullable=False),
        sa.Column("parquet_schema_fingerprint", sa.Text(), nullable=True),
        sa.Column("object_key", sa.String(256), nullable=False),
        sa.Column("row_count", sa.BigInteger(), nullable=True),
        sa.Column("is_synthetic", sa.Boolean(), nullable=False, server_default="false"),
        sa.Column("ingested_at", sa.DateTime(timezone=True), nullable=False),
        schema="ops",
    )

    op.create_table(
        "quality_result_summary",
        sa.Column("id", sa.BigInteger(), primary_key=True, autoincrement=True),
        sa.Column("pipeline_run_id", sa.BigInteger(), nullable=True),
        sa.Column("source_month", sa.String(7), nullable=False),
        sa.Column("issue_code", sa.String(64), nullable=False),
        sa.Column("severity", sa.String(16), nullable=False),
        sa.Column("row_count", sa.BigInteger(), nullable=False),
        schema="ops",
    )

    # Seed dim_time (1440 rows)
    for minute_key in range(1440):
        hour = minute_key // 60
        minute = minute_key % 60
        quarter = minute // 15
        label = f"{hour:02d}:{minute:02d}"
        if hour < 6:
            daypart = "Late Night"
        elif hour < 12:
            daypart = "Morning"
        elif hour < 17:
            daypart = "Afternoon"
        else:
            daypart = "Evening"
        op.execute(f"""
            INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES ({minute_key}, {hour}, {minute}, {quarter}, '{label}', '{daypart}')
        """)

    op.execute("""
        INSERT INTO warehouse.dim_date (
            date_key, calendar_date, year, quarter, month, month_name, iso_week, iso_year,
            day_of_month, day_of_year, weekday_number, weekday_name, is_weekend
        )
        SELECT
            to_char(d, 'YYYYMMDD')::integer,
            d,
            extract(year from d)::smallint,
            extract(quarter from d)::smallint,
            extract(month from d)::smallint,
            trim(to_char(d, 'Month')),
            extract(week from d)::smallint,
            extract(isoyear from d)::smallint,
            extract(day from d)::smallint,
            extract(doy from d)::smallint,
            extract(isodow from d)::smallint,
            trim(to_char(d, 'Day')),
            extract(isodow from d) in (6, 7)
        FROM generate_series('2023-01-01'::date, '2023-03-01'::date, interval '1 day') AS s(d)
    """)

    # Seed Unknown rows for SCD2 dims (key 0)
    for table_name in ("dim_taxi_zone", "dim_payment_type", "dim_vendor", "dim_rate_code"):
        op.execute(f"""
            INSERT INTO warehouse.{table_name} (surrogate_key, business_key, label, observed_from, is_current)
            VALUES (0, 0, 'Unknown', '1970-01-01 00:00:00+00', TRUE)
        """)


def downgrade() -> None:
    op.execute("DROP TABLE IF EXISTS ops.quality_result_summary CASCADE")
    op.execute("DROP TABLE IF EXISTS ops.source_asset CASCADE")
    op.execute("DROP TABLE IF EXISTS ops.pipeline_run CASCADE")
    op.execute("DROP TABLE IF EXISTS analytics.trip_metrics_hourly CASCADE")
    op.execute("DROP TABLE IF EXISTS warehouse.fact_taxi_trips CASCADE")
    for table_name in ("dim_rate_code", "dim_vendor", "dim_payment_type", "dim_taxi_zone"):
        op.execute(f"DROP TABLE IF EXISTS warehouse.{table_name} CASCADE")
    op.execute("DROP TABLE IF EXISTS warehouse.dim_time CASCADE")
    op.execute("DROP TABLE IF EXISTS warehouse.dim_date CASCADE")
    op.execute("DROP SCHEMA IF EXISTS ops CASCADE")
    op.execute("DROP SCHEMA IF EXISTS analytics CASCADE")
    op.execute("DROP SCHEMA IF EXISTS warehouse CASCADE")
    op.execute("DROP EXTENSION IF EXISTS btree_gist")
