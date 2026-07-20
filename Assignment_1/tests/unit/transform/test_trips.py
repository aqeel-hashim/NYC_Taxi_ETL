"""Tests for trip transform: validation, conversion, reconciliation invariants."""

from datetime import datetime

import polars as pl

from nyc_taxi_etl.quality.issues import IssueCode
from nyc_taxi_etl.transform.trips import transform


def _valid_row(row_id: int = 1) -> dict[str, object]:
    return {
        "VendorID": 1,
        "tpep_pickup_datetime": datetime(2023, 1, 15, 10, 0, 0),
        "tpep_dropoff_datetime": datetime(2023, 1, 15, 10, 30, 0),
        "passenger_count": 1,
        "trip_distance": 2.5,
        "RatecodeID": 1,
        "store_and_fwd_flag": "N",
        "PULocationID": 100,
        "DOLocationID": 200,
        "payment_type": 1,
        "fare_amount": 15.0,
        "extra": 0.5,
        "mta_tax": 0.5,
        "tip_amount": 3.0,
        "tolls_amount": 0.0,
        "improvement_surcharge": 0.3,
        "total_amount": 19.3,
        "congestion_surcharge": 2.5,
        "airport_fee": 0.0,
    }


def _build_df(rows: list[dict[str, object]]) -> pl.DataFrame:
    return pl.DataFrame(rows)


class TestRejectionRules:
    def test_rejects_missing_pickup(self) -> None:
        row = _valid_row()
        row["tpep_pickup_datetime"] = None
        result = transform(_build_df([row]), "2023-01")
        assert result.source_rows == 1
        assert result.accepted_rows == 0
        assert result.rejected_rows == 1

    def test_rejects_missing_dropoff(self) -> None:
        row = _valid_row()
        row["tpep_dropoff_datetime"] = None
        result = transform(_build_df([row]), "2023-01")
        assert result.rejected_rows == 1

    def test_rejects_non_positive_distance(self) -> None:
        row = _valid_row()
        row["trip_distance"] = 0.0
        result = transform(_build_df([row]), "2023-01")
        assert result.rejected_rows == 1

    def test_rejects_negative_distance(self) -> None:
        row = _valid_row()
        row["trip_distance"] = -0.5
        result = transform(_build_df([row]), "2023-01")
        assert result.rejected_rows == 1

    def test_rejects_negative_fare(self) -> None:
        row = _valid_row()
        row["fare_amount"] = -5.0
        result = transform(_build_df([row]), "2023-01")
        assert result.rejected_rows == 1

    def test_rejects_negative_total(self) -> None:
        row = _valid_row()
        row["total_amount"] = -1.0
        result = transform(_build_df([row]), "2023-01")
        assert result.rejected_rows == 1

    def test_rejects_pickup_before_month(self) -> None:
        row = _valid_row()
        row["tpep_pickup_datetime"] = datetime(2022, 12, 31, 23, 59, 0)
        result = transform(_build_df([row]), "2023-01")
        assert result.rejected_rows == 1

    def test_rejects_pickup_after_month(self) -> None:
        row = _valid_row()
        row["tpep_pickup_datetime"] = datetime(2023, 2, 1, 0, 0, 0)
        result = transform(_build_df([row]), "2023-01")
        assert result.rejected_rows == 1

    def test_rejects_dropoff_before_pickup(self) -> None:
        row = _valid_row()
        row["tpep_dropoff_datetime"] = datetime(2023, 1, 14, 10, 0, 0)
        result = transform(_build_df([row]), "2023-01")
        assert result.rejected_rows == 1

    def test_allows_dropoff_at_month_edge(self) -> None:
        row = _valid_row()
        row["tpep_pickup_datetime"] = datetime(2023, 1, 31, 23, 30, 0)
        row["tpep_dropoff_datetime"] = datetime(2023, 2, 1, 1, 30, 0)
        result = transform(_build_df([row]), "2023-01")
        assert result.accepted_rows == 1
        assert result.rejected_rows == 0

    def test_rejects_dropoff_past_window(self) -> None:
        row = _valid_row()
        row["tpep_pickup_datetime"] = datetime(2023, 1, 31, 23, 0, 0)
        row["tpep_dropoff_datetime"] = datetime(2023, 2, 2, 1, 0, 0)
        result = transform(_build_df([row]), "2023-01")
        assert result.rejected_rows == 1


class TestFlagRules:
    def test_flags_unknown_vendor(self) -> None:
        row = _valid_row()
        row["VendorID"] = 99
        result = transform(_build_df([row]), "2023-01")
        assert result.accepted_rows == 1
        assert result.flagged_rows == 1
        assert result.issues["issue_code"].to_list() == [IssueCode.UNKNOWN_VENDOR.value]

    def test_flags_unknown_payment(self) -> None:
        row = _valid_row()
        row["payment_type"] = 99
        result = transform(_build_df([row]), "2023-01")
        assert IssueCode.UNKNOWN_PAYMENT.value in result.issues["issue_code"].to_list()

    def test_rejects_null_fare_amount(self) -> None:
        row = _valid_row()
        row["fare_amount"] = None
        result = transform(_build_df([row]), "2023-01")
        assert result.rejected_rows == 1
        assert result.flagged_rows == 0

    def test_flags_null_tip(self) -> None:
        row = _valid_row()
        row["tip_amount"] = None
        result = transform(_build_df([row]), "2023-01")
        assert IssueCode.NULL_TIP.value in result.issues["issue_code"].to_list()

    def test_flags_multiple_issues(self) -> None:
        row = _valid_row()
        row["VendorID"] = 99
        row["payment_type"] = 99
        result = transform(_build_df([row]), "2023-01")
        codes = result.issues["issue_code"].to_list()
        assert len(codes) == 2
        assert IssueCode.UNKNOWN_VENDOR.value in codes
        assert IssueCode.UNKNOWN_PAYMENT.value in codes

    def test_clean_row_no_flags(self) -> None:
        row = _valid_row()
        result = transform(_build_df([row]), "2023-01")
        assert result.accepted_rows == 1
        assert result.flagged_rows == 0
        assert result.rejected_rows == 0


class TestReconciliationInvariants:
    def test_source_equals_accepted_plus_rejected(self) -> None:
        rows = [
            _valid_row(1),
            _valid_row(2),
            {**_valid_row(3), "trip_distance": -1.0},
            {**_valid_row(4), "VendorID": 99},
            {**_valid_row(5), "fare_amount": None},
        ]
        result = transform(_build_df(rows), "2023-01")
        assert result.source_rows == 5
        assert result.accepted_rows == 3
        assert result.rejected_rows == 2
        assert result.source_rows == result.accepted_rows + result.rejected_rows
        assert result.flagged_rows <= result.accepted_rows
        assert result.flagged_rows == 1
        assert result.accepted_rows == len(result.accepted)

    def test_all_accepted_no_rejects(self) -> None:
        rows = [_valid_row(i) for i in range(1, 11)]
        result = transform(_build_df(rows), "2023-01")
        assert result.source_rows == 10
        assert result.accepted_rows == 10
        assert result.rejected_rows == 0
        assert result.flagged_rows == 0

    def test_all_rejected(self) -> None:
        rows = [{**_valid_row(i), "trip_distance": 0.0} for i in range(1, 6)]
        result = transform(_build_df(rows), "2023-01")
        assert result.source_rows == 5
        assert result.accepted_rows == 0
        assert result.rejected_rows == 5


class TestConversions:
    def test_distance_to_millimiles(self) -> None:
        row = _valid_row()
        row["trip_distance"] = 3.456
        result = transform(_build_df([row]), "2023-01")
        assert result.accepted["distance_millimiles"][0] == 3456

    def test_fare_to_cents(self) -> None:
        row = _valid_row()
        row["fare_amount"] = 12.34
        result = transform(_build_df([row]), "2023-01")
        assert result.accepted["fare_amount_cents"][0] == 1234

    def test_duration_seconds(self) -> None:
        row = _valid_row()
        row["tpep_pickup_datetime"] = datetime(2023, 1, 15, 10, 0, 0)
        row["tpep_dropoff_datetime"] = datetime(2023, 1, 15, 10, 15, 30)
        result = transform(_build_df([row]), "2023-01")
        assert result.accepted["duration_seconds"][0] == 930

    def test_source_row_number_sequential(self) -> None:
        rows = [_valid_row(i) for i in range(1, 6)]
        result = transform(_build_df(rows), "2023-01")
        numbers = result.accepted["source_row_number"].to_list()
        assert numbers == [1, 2, 3, 4, 5]

    def test_null_zone_maps_to_zero(self) -> None:
        row = _valid_row()
        row["PULocationID"] = None
        row["DOLocationID"] = None
        result = transform(_build_df([row]), "2023-01")
        assert result.accepted["pickup_location_id"][0] == 0
        assert result.accepted["dropoff_location_id"][0] == 0

    def test_has_statistical_outlier_defaults_false(self) -> None:
        row = _valid_row()
        result = transform(_build_df([row]), "2023-01")
        assert not result.accepted["has_statistical_outlier"][0]

    def test_has_quality_issue_correct(self) -> None:
        row = _valid_row()
        row["tip_amount"] = None
        result = transform(_build_df([row]), "2023-01")
        assert result.accepted["has_quality_issue"][0]


class TestFebruaryMonth:
    def test_february_2023_bounds(self) -> None:
        row = _valid_row()
        row["tpep_pickup_datetime"] = datetime(2023, 2, 28, 23, 59, 0)
        row["tpep_dropoff_datetime"] = datetime(2023, 3, 1, 1, 0, 0)
        result = transform(_build_df([row]), "2023-02")
        assert result.accepted_rows == 1

    def test_february_jan_pickup_rejected(self) -> None:
        row = _valid_row()
        row["tpep_pickup_datetime"] = datetime(2023, 1, 15, 10, 0, 0)
        result = transform(_build_df([row]), "2023-02")
        assert result.rejected_rows == 1


class TestDecemberMonth:
    def test_december_year_boundary(self) -> None:
        row = _valid_row()
        row["tpep_pickup_datetime"] = datetime(2023, 12, 31, 23, 0, 0)
        row["tpep_dropoff_datetime"] = datetime(2024, 1, 1, 1, 0, 0)
        result = transform(_build_df([row]), "2023-12")
        assert result.accepted_rows == 1

    def test_december_outside_boundary_rejected(self) -> None:
        row = _valid_row()
        row["tpep_pickup_datetime"] = datetime(2024, 1, 1, 0, 0, 0)
        result = transform(_build_df([row]), "2023-12")
        assert result.rejected_rows == 1
