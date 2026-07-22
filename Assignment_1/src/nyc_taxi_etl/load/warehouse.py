from __future__ import annotations

import contextlib
import csv
import os
from collections.abc import Mapping
from dataclasses import dataclass
from datetime import UTC, datetime

import psycopg
from psycopg import Connection

from nyc_taxi_etl.transform.reference import PAYMENT_TYPE_LOOKUP, RATE_CODE_LOOKUP, VENDOR_LOOKUP
from nyc_taxi_etl.transform.trips import TransformResult

_DEFAULT_ZONE_CSV = os.environ.get(
    "TAXI_ZONE_CSV",
    os.path.join(os.path.dirname(__file__), "..", "..", "..", "references", "taxi_zone_lookup.csv"),
)


@dataclass(frozen=True)
class LoadResult:
    inserted_rows: int
    duplicate_source_rows: int


def load_month(
    database_url: str,
    result: TransformResult,
    *,
    source_asset_id: str,
    source_version: str,
    source_url: str,
    sha256: str,
    byte_size: int,
    started_at: datetime | None = None,
) -> LoadResult:
    psycopg_url = database_url.replace("postgresql+psycopg://", "postgresql://")
    with psycopg.connect(psycopg_url) as conn:
        with conn.transaction():
            _load_references(conn)
            _ensure_month_support(conn, result.source_month)
            _upsert_source_asset(
                conn,
                source_asset_id=source_asset_id,
                source_month=result.source_month,
                source_url=source_url,
                sha256=sha256,
                byte_size=byte_size,
                row_count=result.source_rows,
                is_synthetic=source_url == "fixture",
            )
            _replace_month_facts(conn, result, source_asset_id=source_asset_id, source_version=source_version)
            _record_quality(conn, result)
            _record_trip_quality_issues(conn, result)
            _populate_analytics_mart(conn, result.source_month)
            duplicate_count = _duplicate_source_count(conn, result.source_month, source_asset_id, source_version)
            if duplicate_count:
                raise RuntimeError(f"duplicate source rows after load: {duplicate_count}")
            _record_run(conn, result, source_version=source_version, started_at=started_at)
        return LoadResult(inserted_rows=result.accepted_rows, duplicate_source_rows=0)


def _load_references(conn: Connection[tuple[object, ...]]) -> None:
    for table, lookup in (
        ("dim_vendor", VENDOR_LOOKUP),
        ("dim_payment_type", PAYMENT_TYPE_LOOKUP),
        ("dim_rate_code", RATE_CODE_LOOKUP),
    ):
        _load_reference_table(conn, table, lookup)
    _load_taxi_zones(conn)


def _load_reference_table(conn: Connection[tuple[object, ...]], table: str, lookup: Mapping[int, str]) -> None:
    for business_key, label in lookup.items():
        if business_key == 0:
            continue
        conn.execute(
            f"""
            INSERT INTO warehouse.{table} (business_key, label, observed_from, is_current)
            VALUES (%s, %s, '1970-01-01 00:00:00+00', true)
            ON CONFLICT DO NOTHING
            """,
            (business_key, label),
        )


def _load_taxi_zones(conn: Connection[tuple[object, ...]]) -> None:
    zone_csv = _DEFAULT_ZONE_CSV
    if not os.path.isfile(zone_csv):
        return
    with open(zone_csv, newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            location_id = int(row["LocationID"])
            if location_id == 0:
                continue
            label = row["Zone"]
            attrs = f"borough={row['Borough']}, service_zone={row['service_zone']}"
            conn.execute(
                """
                INSERT INTO warehouse.dim_taxi_zone (business_key, label, attributes, observed_from, is_current)
                VALUES (%s, %s, %s, '1970-01-01 00:00:00+00', true)
                ON CONFLICT DO NOTHING
                """,
                (location_id, label, attrs),
            )


def _ensure_month_support(conn: Connection[tuple[object, ...]], source_month: str) -> None:
    month_start, month_end = _month_key_bounds(source_month)
    year, month = (int(part) for part in source_month.split("-"))
    start_date = datetime(year, month, 1).date()
    end_date = datetime(year + (month == 12), month % 12 + 1, 1).date()
    conn.execute(
        """
        INSERT INTO warehouse.dim_date (
            date_key, calendar_date, year, quarter, month, month_name, iso_week, iso_year,
            day_of_month, day_of_year, weekday_number, weekday_name, is_weekend
        )
        SELECT
            to_char(d, 'YYYYMMDD')::integer, d, extract(year from d)::smallint,
            extract(quarter from d)::smallint, extract(month from d)::smallint,
            trim(to_char(d, 'Month')), extract(week from d)::smallint,
            extract(isoyear from d)::smallint, extract(day from d)::smallint,
            extract(doy from d)::smallint, extract(isodow from d)::smallint,
            trim(to_char(d, 'Day')), extract(isodow from d) in (6, 7)
        FROM generate_series(%s::date, %s::date, interval '1 day') AS s(d)
        ON CONFLICT (date_key) DO NOTHING
        """,
        (start_date, end_date),
    )
    partition = f"trip_metrics_hourly_{source_month.replace('-', '_')}"
    conn.execute(
        f"CREATE TABLE IF NOT EXISTS analytics.{partition} "
        f"PARTITION OF analytics.trip_metrics_hourly FOR VALUES FROM ({month_start}) TO ({month_end})"
    )


def _upsert_source_asset(
    conn: Connection[tuple[object, ...]],
    *,
    source_asset_id: str,
    source_month: str,
    source_url: str,
    sha256: str,
    byte_size: int,
    row_count: int,
    is_synthetic: bool,
) -> None:
    conn.execute(
        """
        INSERT INTO ops.source_asset (
            id, source_month, source_url, byte_size, sha256, object_key, row_count, is_synthetic, ingested_at
        ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
        ON CONFLICT (id) DO UPDATE SET row_count = EXCLUDED.row_count, ingested_at = EXCLUDED.ingested_at
        """,
        (
            source_asset_id,
            source_month,
            source_url,
            byte_size,
            sha256,
            source_asset_id,
            row_count,
            is_synthetic,
            datetime.now(UTC),
        ),
    )


def _replace_month_facts(
    conn: Connection[tuple[object, ...]],
    result: TransformResult,
    *,
    source_asset_id: str,
    source_version: str,
) -> None:
    month_start, month_end = _month_key_bounds(result.source_month)

    # Remove existing partition for this month before loading
    _remove_partition(conn, result.source_month, month_start, month_end)

    if result.accepted_rows == 0:
        return

    vendor_keys = _surrogate_map(conn, "dim_vendor")
    payment_keys = _surrogate_map(conn, "dim_payment_type")
    rate_keys = _surrogate_map(conn, "dim_rate_code")
    zone_keys = _surrogate_map(conn, "dim_taxi_zone")

    staging = _staging_partition_name(result.source_month)
    canonical = _canonical_partition_name(result.source_month)
    cols = (
        "pickup_date_key, dropoff_date_key, pickup_time_key, dropoff_time_key, "
        "pickup_zone_key, dropoff_zone_key, payment_type_key, vendor_key, rate_code_key, "
        "pickup_at_local, dropoff_at_local, duration_seconds, passenger_count, "
        "distance_millimiles, store_and_fwd_flag, fare_amount_cents, extra_cents, "
        "mta_tax_cents, tip_amount_cents, tolls_amount_cents, improvement_surcharge_cents, "
        "total_amount_cents, congestion_surcharge_cents, airport_fee_cents, source_asset_id, "
        "source_row_number, source_version, has_statistical_outlier, has_quality_issue"
    )

    # Create and populate staging table
    _create_staging_table(conn, staging, month_start, month_end)
    try:
        with (
            conn.cursor() as cur,
            cur.copy(f"COPY warehouse.{staging} ({cols}) FROM STDIN") as copy,
        ):
            for row in result.accepted.iter_rows(named=True):
                copy.write_row(
                    _fact_row(row, source_asset_id, source_version, zone_keys, vendor_keys, payment_keys, rate_keys)
                )

        # Attach as partition, then rename to canonical
        conn.execute(
            f"ALTER TABLE warehouse.fact_taxi_trips ATTACH PARTITION warehouse.{staging} "
            f"FOR VALUES FROM ({month_start}) TO ({month_end})"
        )
        conn.execute(f"ALTER TABLE warehouse.{staging} DROP CONSTRAINT IF EXISTS {staging}_month_check")
        if staging != canonical:
            conn.execute(f"ALTER TABLE warehouse.{staging} RENAME TO {canonical}")
    except BaseException:
        with contextlib.suppress(Exception):
            conn.execute(f"DROP TABLE IF EXISTS warehouse.{staging} CASCADE")
        raise


def _partition_safe_name(source_month: str) -> str:
    return source_month.replace("-", "_")


def _staging_partition_name(source_month: str) -> str:
    return f"fact_taxi_trips_staging_{_partition_safe_name(source_month)}"


def _canonical_partition_name(source_month: str) -> str:
    return f"fact_taxi_trips_{_partition_safe_name(source_month)}"


def _remove_partition(
    conn: Connection[tuple[object, ...]], source_month: str, month_start: int, month_end: int
) -> None:
    result = (
        conn.execute(
            """
        SELECT inhrelid::regclass::text
        FROM pg_inherits i
        JOIN pg_class p ON i.inhrelid = p.oid
        JOIN pg_namespace n ON p.relnamespace = n.oid
        WHERE n.nspname = 'warehouse'
        AND p.relkind = 'r'
        AND i.inhparent = 'warehouse.fact_taxi_trips'::regclass
        AND p.relispartition = true
        """
        ).fetchall()
        or []
    )
    canonical = f"warehouse.{_canonical_partition_name(source_month)}"
    for row in result:
        name = str(row[0]) if row[0] is not None else ""
        if name == canonical:
            conn.execute(f"ALTER TABLE warehouse.fact_taxi_trips DETACH PARTITION {name}")
            conn.execute(f"DROP TABLE IF EXISTS {name} CASCADE")
            return


def _create_staging_table(conn: Connection[tuple[object, ...]], staging: str, month_start: int, month_end: int) -> None:
    conn.execute(f"DROP TABLE IF EXISTS warehouse.{staging}")
    conn.execute(
        f"""
        CREATE TABLE warehouse.{staging} (
            LIKE warehouse.fact_taxi_trips INCLUDING DEFAULTS INCLUDING CONSTRAINTS
        )
        """
    )
    conn.execute(
        f"ALTER TABLE warehouse.{staging} ADD CONSTRAINT {staging}_month_check "
        f"CHECK (pickup_date_key >= {month_start} AND pickup_date_key < {month_end})"
    )


def _surrogate_map(conn: Connection[tuple[object, ...]], table: str) -> dict[int, int]:
    return {
        _as_int(business_key): _as_int(surrogate_key)
        for business_key, surrogate_key in conn.execute(
            f"SELECT business_key, surrogate_key FROM warehouse.{table} WHERE is_current"
        ).fetchall()
    }


def _fact_row(
    row: dict[str, object],
    source_asset_id: str,
    source_version: str,
    zone_keys: Mapping[int, int],
    vendor_keys: Mapping[int, int],
    payment_keys: Mapping[int, int],
    rate_keys: Mapping[int, int],
) -> tuple[object, ...]:
    pickup = row["pickup_at_local"]
    dropoff = row["dropoff_at_local"]
    if not isinstance(pickup, datetime) or not isinstance(dropoff, datetime):
        raise TypeError("accepted trip timestamps must be datetimes")
    return (
        int(pickup.strftime("%Y%m%d")),
        int(dropoff.strftime("%Y%m%d")),
        pickup.hour * 60 + pickup.minute,
        dropoff.hour * 60 + dropoff.minute,
        zone_keys.get(_as_int(row["pickup_location_id"]), 0),
        zone_keys.get(_as_int(row["dropoff_location_id"]), 0),
        payment_keys.get(_as_int(row["payment_type_id"]), 0),
        vendor_keys.get(_as_int(row["vendor_id"]), 0),
        rate_keys.get(_as_int(row["rate_code_id"]), 0),
        pickup,
        dropoff,
        row["duration_seconds"],
        _optional_int(row["passenger_count"]),
        row["distance_millimiles"],
        row["store_and_fwd_flag"],
        row["fare_amount_cents"],
        row["extra_cents"],
        row["mta_tax_cents"],
        row["tip_amount_cents"],
        row["tolls_amount_cents"],
        row["improvement_surcharge_cents"],
        row["total_amount_cents"],
        row["congestion_surcharge_cents"],
        row["airport_fee_cents"],
        source_asset_id,
        row["source_row_number"],
        source_version,
        row["has_statistical_outlier"],
        row["has_quality_issue"],
    )


def _record_run(
    conn: Connection[tuple[object, ...]],
    result: TransformResult,
    *,
    source_version: str,
    started_at: datetime | None,
) -> None:
    finished_at = datetime.now(UTC)
    started_at = started_at or finished_at
    dag_id = os.environ.get("AIRFLOW_CTX_DAG_ID", "local")
    run_id = os.environ.get("AIRFLOW_CTX_DAG_RUN_ID", f"local-{result.source_month}-{source_version[:12]}")
    conn.execute(
        """
        INSERT INTO ops.pipeline_run (
            dag_id, run_id, task_id, source_month, status, started_at, finished_at, duration_seconds,
            source_rows, accepted_rows, rejected_rows, flagged_rows, source_version
        ) VALUES (%s, %s, %s, %s, 'success', %s, %s, %s, %s, %s, %s, %s, %s)
        """,
        (
            dag_id,
            run_id,
            os.environ.get("AIRFLOW_CTX_TASK_ID"),
            result.source_month,
            started_at,
            finished_at,
            (finished_at - started_at).total_seconds(),
            result.source_rows,
            result.accepted_rows,
            result.rejected_rows,
            result.flagged_rows,
            source_version,
        ),
    )


def _record_quality(conn: Connection[tuple[object, ...]], result: TransformResult) -> None:
    conn.execute("DELETE FROM ops.quality_result_summary WHERE source_month = %s", (result.source_month,))
    for issue_code, count in result.issues.group_by("issue_code").len().iter_rows() if len(result.issues) else []:
        conn.execute(
            """
            INSERT INTO ops.quality_result_summary (source_month, issue_code, severity, row_count)
            VALUES (%s, %s, 'warning', %s)
            """,
            (result.source_month, issue_code, count),
        )


def _duplicate_source_count(
    conn: Connection[tuple[object, ...]], source_month: str, source_asset_id: str, source_version: str
) -> int:
    month_start, month_end = _month_key_bounds(source_month)
    row = conn.execute(
        """
        SELECT count(*) - count(DISTINCT (pickup_date_key, source_asset_id, source_version, source_row_number))
        FROM warehouse.fact_taxi_trips
        WHERE pickup_date_key >= %s AND pickup_date_key < %s AND source_asset_id = %s AND source_version = %s
        """,
        (month_start, month_end, source_asset_id, source_version),
    ).fetchone()
    return _as_int(row[0]) if row else 0


def _record_trip_quality_issues(conn: Connection[tuple[object, ...]], result: TransformResult) -> None:
    conn.execute("DELETE FROM ops.trip_quality_issue WHERE source_month = %s", (result.source_month,))
    issues = result.issues
    if not len(issues):
        return
    rows = issues.to_dicts()
    with conn.cursor() as cur:
        for row in rows:
            cur.execute(
                """
                INSERT INTO ops.trip_quality_issue (source_month, source_row_number, issue_code, severity)
                VALUES (%s, %s, %s, 'warning')
                """,
                (result.source_month, row["source_row_number"], row["issue_code"]),
            )


def _populate_analytics_mart(conn: Connection[tuple[object, ...]], source_month: str) -> None:
    month_start, month_end = _month_key_bounds(source_month)
    conn.execute(
        "DELETE FROM analytics.trip_metrics_hourly WHERE pickup_date_key >= %s AND pickup_date_key < %s",
        (month_start, month_end),
    )
    conn.execute(
        """
        INSERT INTO analytics.trip_metrics_hourly (
            pickup_date_key, pickup_hour, pickup_zone_key, payment_type_key, vendor_key, rate_code_key,
            has_statistical_outlier, has_quality_issue,
            trip_count, passenger_count_sum, passenger_sum,
            distance_millimiles_sum, duration_seconds_sum,
            fare_amount_cents_sum, extra_cents_sum, mta_tax_cents_sum, tip_amount_cents_sum,
            tolls_amount_cents_sum, improvement_surcharge_cents_sum,
            total_amount_cents_sum, congestion_surcharge_cents_sum, airport_fee_cents_sum
        )
        SELECT
            pickup_date_key,
            (pickup_time_key / 60)::smallint AS pickup_hour,
            pickup_zone_key, payment_type_key, vendor_key, rate_code_key,
            has_statistical_outlier, has_quality_issue,
            COUNT(*)::bigint,
            COALESCE(SUM(passenger_count), 0)::bigint,
            SUM(COALESCE(passenger_count, 0))::bigint,
            SUM(distance_millimiles)::bigint,
            SUM(duration_seconds)::bigint,
            SUM(fare_amount_cents)::bigint,
            COALESCE(SUM(extra_cents), 0)::bigint,
            COALESCE(SUM(mta_tax_cents), 0)::bigint,
            COALESCE(SUM(tip_amount_cents), 0)::bigint,
            COALESCE(SUM(tolls_amount_cents), 0)::bigint,
            COALESCE(SUM(improvement_surcharge_cents), 0)::bigint,
            SUM(total_amount_cents)::bigint,
            COALESCE(SUM(congestion_surcharge_cents), 0)::bigint,
            COALESCE(SUM(airport_fee_cents), 0)::bigint
        FROM warehouse.fact_taxi_trips
        WHERE pickup_date_key >= %s AND pickup_date_key < %s
        GROUP BY pickup_date_key, pickup_hour, pickup_zone_key, payment_type_key, vendor_key, rate_code_key,
            has_statistical_outlier, has_quality_issue
        """,
        (month_start, month_end),
    )


def _month_key_bounds(source_month: str) -> tuple[int, int]:
    year = int(source_month[:4])
    month = int(source_month[5:7])
    start = year * 10000 + month * 100 + 1
    if month == 12:
        return start, (year + 1) * 10000 + 101
    return start, year * 10000 + (month + 1) * 100 + 1


def _as_int(value: object) -> int:
    if isinstance(value, int | float | str):
        return int(value)
    raise TypeError(f"expected int-compatible value, got {type(value).__name__}")


def _optional_int(value: object) -> int | None:
    if value is None:
        return None
    return _as_int(value)
