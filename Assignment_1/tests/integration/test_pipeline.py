from __future__ import annotations

import hashlib
import os
import subprocess
from pathlib import Path

import psycopg
import pytest

from alembic import command
from alembic.config import Config
from nyc_taxi_etl.pipeline import run_pipeline
from tests.fixtures.generate_taxi_fixture import write_fixture

ROOT = Path(__file__).resolve().parents[2]


@pytest.fixture(scope="session")
def database_url() -> str:
    url = os.environ.get("TEST_DATABASE_URL")
    if not url:
        pytest.skip("TEST_DATABASE_URL is required for pipeline integration tests")
    return url


@pytest.fixture(autouse=True)
def migrated_database(database_url: str) -> None:
    config = Config(str(ROOT / "alembic.ini"))
    config.set_main_option("script_location", str(ROOT / "alembic"))
    config.set_main_option("sqlalchemy.url", database_url)
    command.downgrade(config, "base")
    command.upgrade(config, "head")


def test_fixture_generator_is_stable(tmp_path: Path) -> None:
    first = write_fixture(tmp_path / "first.parquet")
    second = write_fixture(tmp_path / "second.parquet")
    assert _sha256(first) == _sha256(second)


def test_fixture_pipeline_loads_and_reruns(database_url: str) -> None:
    first = run_pipeline("2023-01", database_url=database_url, fixture=True)
    second = run_pipeline("2023-01", database_url=database_url, fixture=True)
    assert (first.source_rows, first.accepted_rows, first.rejected_rows, first.flagged_rows, first.issue_rows) == (
        6,
        4,
        2,
        1,
        2,
    )
    assert second == first

    with psycopg.connect(database_url.replace("postgresql+psycopg://", "postgresql://")) as conn:
        assert conn.execute("SELECT count(*) FROM warehouse.fact_taxi_trips").fetchone() == (4,)
        assert conn.execute(
            "SELECT count(*) FROM warehouse.fact_taxi_trips WHERE pickup_zone_key = 0 OR dropoff_zone_key = 0"
        ).fetchone() == (0,)
        assert conn.execute(
            "SELECT count(*) FROM ops.trip_quality_issue WHERE source_month = '2023-01'"
        ).fetchone() == (2,)
        assert conn.execute(
            "SELECT sum(row_count) FROM ops.quality_result_summary WHERE source_month = '2023-01'"
        ).fetchone() == (2,)
        assert conn.execute(
            """
            SELECT count(*) - count(DISTINCT (pickup_date_key, source_asset_id, source_version, source_row_number))
            FROM warehouse.fact_taxi_trips
            """
        ).fetchone() == (0,)
        assert conn.execute((ROOT / "sql/queries/peak_ride_hours.sql").read_text()).fetchone() == (
            1,
            "Late Night",
            "01:00",
            2,
        )


def test_pipeline_exit_codes(database_url: str) -> None:
    invalid = subprocess.run(["./scripts/run-pipeline.sh", "2023-99"], cwd=ROOT, check=False)
    missing_db = subprocess.run(["./scripts/run-pipeline.sh", "2023-01", "--fixture"], cwd=ROOT, check=False)
    assert invalid.returncode == 2
    assert missing_db.returncode == 4


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()
