"""Tests for source contract validation."""

from datetime import datetime

import polars as pl

from nyc_taxi_etl.contracts.source import ContractStatus, validate_contract


def _valid_schema() -> pl.DataFrame:
    return pl.DataFrame(
        {
            "VendorID": [1],
            "tpep_pickup_datetime": [datetime(2023, 1, 15, 10, 0, 0)],
            "tpep_dropoff_datetime": [datetime(2023, 1, 15, 10, 30, 0)],
            "passenger_count": [1],
            "trip_distance": [2.5],
            "RatecodeID": [1],
            "store_and_fwd_flag": ["N"],
            "PULocationID": [100],
            "DOLocationID": [200],
            "payment_type": [1],
            "fare_amount": [15.0],
            "extra": [0.5],
            "mta_tax": [0.5],
            "tip_amount": [3.0],
            "tolls_amount": [0.0],
            "improvement_surcharge": [0.3],
            "total_amount": [19.3],
            "congestion_surcharge": [2.5],
            "airport_fee": [0.0],
        }
    )


class TestValidContract:
    def test_valid_schema_passes(self) -> None:
        df = _valid_schema()
        contract = validate_contract(df)
        assert contract.is_valid
        assert contract.status == ContractStatus.VALID
        assert contract.source_row_count == 1

    def test_extra_columns_allowed(self) -> None:
        df = _valid_schema().with_columns(pl.lit("extra").alias("unknown_col"))
        contract = validate_contract(df)
        assert contract.is_valid
        assert "unknown_col" in contract.extra_column_names


class TestInvalidContract:
    def test_missing_required_column(self) -> None:
        df = _valid_schema().drop("fare_amount")
        contract = validate_contract(df)
        assert not contract.is_valid
        assert contract.status == ContractStatus.MISSING_COLUMNS
        assert "fare_amount" in contract.missing_required

    def test_multiple_missing_columns(self) -> None:
        df = _valid_schema().drop(["fare_amount", "total_amount"])
        contract = validate_contract(df)
        assert "fare_amount" in contract.missing_required
        assert "total_amount" in contract.missing_required

    def test_zero_rows(self) -> None:
        df = _valid_schema().clear()
        contract = validate_contract(df)
        assert not contract.is_valid
        assert contract.status == ContractStatus.ZERO_ROWS
