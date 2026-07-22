from __future__ import annotations

import os
from collections.abc import Generator
from decimal import Decimal
from pathlib import Path

import psycopg
import pytest
from psycopg import Connection
from psycopg.errors import ForeignKeyViolation, UniqueViolation

from alembic import command
from alembic.config import Config

ROOT = Path(__file__).resolve().parents[2]


@pytest.fixture(scope="session")
def database_url() -> str:
    url = os.environ.get("TEST_DATABASE_URL")
    if not url:
        pytest.skip("TEST_DATABASE_URL is required for warehouse contract tests")
    return url


@pytest.fixture(scope="session", autouse=True)
def migrated_database(database_url: str) -> None:
    config = Config(str(ROOT / "alembic.ini"))
    config.set_main_option("script_location", str(ROOT / "alembic"))
    config.set_main_option("sqlalchemy.url", database_url)
    command.downgrade(config, "base")
    command.upgrade(config, "head")


@pytest.fixture()
def conn(database_url: str) -> Generator[Connection[tuple[object, ...]]]:
    psycopg_url = database_url.replace("postgresql+psycopg://", "postgresql://")
    with psycopg.connect(psycopg_url) as connection:
        connection.execute("TRUNCATE warehouse.fact_taxi_trips")
        yield connection
        connection.rollback()


def insert_trip(
    conn: Connection[tuple[object, ...]],
    *,
    pickup_date_key: int = 20230101,
    dropoff_date_key: int = 20230101,
    pickup_time_key: int = 60,
    source_row_number: int = 1,
    fare_amount_cents: int = 1500,
    total_amount_cents: int = 2000,
    distance_millimiles: int = 1000,
    has_statistical_outlier: bool = False,
    payment_type_key: int = 0,
) -> None:
    conn.execute(
        """
        INSERT INTO warehouse.fact_taxi_trips (
            pickup_date_key, dropoff_date_key, pickup_time_key, dropoff_time_key,
            pickup_zone_key, dropoff_zone_key, payment_type_key, vendor_key, rate_code_key,
            pickup_at_local, dropoff_at_local, duration_seconds, passenger_count,
            distance_millimiles, fare_amount_cents, extra_cents, mta_tax_cents,
            tip_amount_cents, tolls_amount_cents, improvement_surcharge_cents,
            total_amount_cents, congestion_surcharge_cents, airport_fee_cents,
            source_asset_id, source_row_number, source_version, has_statistical_outlier,
            has_quality_issue
        ) VALUES (
            %(pickup_date_key)s, %(dropoff_date_key)s, %(pickup_time_key)s, %(pickup_time_key)s,
            0, 0, %(payment_type_key)s, 0, 0,
            '2023-01-01 01:00:00', '2023-01-01 01:10:00', 600, 1,
            %(distance_millimiles)s, %(fare_amount_cents)s, 0, 0, 0, 0, 0,
            %(total_amount_cents)s, 0, 0, 'fixture', %(source_row_number)s, 'v1',
            %(has_statistical_outlier)s, false
        )
        """,
        {
            "pickup_date_key": pickup_date_key,
            "dropoff_date_key": dropoff_date_key,
            "pickup_time_key": pickup_time_key,
            "source_row_number": source_row_number,
            "fare_amount_cents": fare_amount_cents,
            "total_amount_cents": total_amount_cents,
            "distance_millimiles": distance_millimiles,
            "has_statistical_outlier": has_statistical_outlier,
            "payment_type_key": payment_type_key,
        },
    )


def test_migration_seeds_time_and_unknown_rows(conn: Connection[tuple[object, ...]]) -> None:
    assert conn.execute("SELECT count(*) FROM warehouse.dim_time").fetchone() == (1440,)
    for table in ("dim_taxi_zone", "dim_payment_type", "dim_vendor", "dim_rate_code"):
        assert conn.execute(f"SELECT label FROM warehouse.{table} WHERE surrogate_key = 0").fetchone() == ("Unknown",)


def test_assignment_month_partitions_accept_parent_inserts(conn: Connection[tuple[object, ...]]) -> None:
    insert_trip(conn, pickup_date_key=20230101, dropoff_date_key=20230101, source_row_number=1)
    insert_trip(conn, pickup_date_key=20230201, dropoff_date_key=20230201, source_row_number=2)
    assert conn.execute("SELECT count(*) FROM warehouse.fact_taxi_trips").fetchone() == (2,)


def test_duplicate_source_identity_is_rejected(conn: Connection[tuple[object, ...]]) -> None:
    insert_trip(conn)
    with pytest.raises(UniqueViolation):
        insert_trip(conn)


def test_invalid_dimension_key_is_rejected(conn: Connection[tuple[object, ...]]) -> None:
    with pytest.raises(ForeignKeyViolation):
        insert_trip(conn, payment_type_key=999)


def test_required_sql_executes_and_matches_golden_values(conn: Connection[tuple[object, ...]]) -> None:
    insert_trip(conn, source_row_number=1, pickup_time_key=60)
    insert_trip(
        conn,
        source_row_number=2,
        pickup_time_key=61,
        fare_amount_cents=99900,
        total_amount_cents=99900,
        has_statistical_outlier=True,
    )

    average = conn.execute((ROOT / "sql/queries/average_fare_per_mile.sql").read_text()).fetchall()
    peak = conn.execute((ROOT / "sql/queries/peak_ride_hours.sql").read_text()).fetchall()
    revenue = conn.execute((ROOT / "sql/queries/revenue_by_payment_type.sql").read_text()).fetchall()

    assert average == [(20230101, Decimal("15.00"))]
    assert peak[0][:4] == (1, "Late Night", "01:00", 2)
    assert revenue == [(0, "Unknown", Decimal("1019.00"), 2, Decimal("509.50"))]
