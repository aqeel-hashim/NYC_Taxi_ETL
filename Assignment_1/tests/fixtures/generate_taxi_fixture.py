from __future__ import annotations

from pathlib import Path

import polars as pl

from nyc_taxi_etl.fixtures import build_taxi_fixture, write_taxi_fixture


def build_fixture() -> pl.DataFrame:
    return build_taxi_fixture()


def write_fixture(path: Path) -> Path:
    return write_taxi_fixture(path)


if __name__ == "__main__":
    write_fixture(Path("tests/fixtures/yellow_tripdata_fixture.parquet"))
