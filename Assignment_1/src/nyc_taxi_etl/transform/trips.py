"""Trip transform: clean, validate, convert, and split accepted/issues/rejected rows.

Pure function — no DB, no Airflow, no I/O.
Takes a raw Polars DataFrame matching the TLC source contract and returns a
TransformResult with three output DataFrames plus reconciliation counts.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta

import polars as pl

from nyc_taxi_etl.quality.issues import IssueCode
from nyc_taxi_etl.quality.kll import DEFAULT_K, ThresholdBounds, build_sketch_from_iterable, compute_bounds
from nyc_taxi_etl.transform.reference import PAYMENT_TYPE_LOOKUP, RATE_CODE_LOOKUP, VENDOR_LOOKUP

MONTH_WINDOW_HOURS = 24  # dropoff allowed within 24h after month end


@dataclass
class TransformResult:
    accepted: pl.DataFrame
    rejected: pl.DataFrame
    issues: pl.DataFrame

    source_rows: int
    accepted_rows: int
    rejected_rows: int
    flagged_rows: int

    source_month: str


def transform(
    raw: pl.DataFrame,
    source_month: str,
    vendor_lookup: dict[int, str] | None = None,
    payment_lookup: dict[int, str] | None = None,
    rate_code_lookup: dict[int, str] | None = None,
) -> TransformResult:
    """Transform raw TLC DataFrame into accepted, rejected, and issue records."""
    if vendor_lookup is None:
        vendor_lookup = VENDOR_LOOKUP
    if payment_lookup is None:
        payment_lookup = PAYMENT_TYPE_LOOKUP
    if rate_code_lookup is None:
        rate_code_lookup = RATE_CODE_LOOKUP

    month_start, month_end = _month_bounds(source_month)

    source_rows = len(raw)

    # 1. Column contract validation (basic existence/non-null checks)
    raw = raw.with_row_index("_source_row", offset=1)
    raw = raw.with_columns(
        raw["tpep_pickup_datetime"].cast(pl.Datetime("us")).alias("_pickup"),
        raw["tpep_dropoff_datetime"].cast(pl.Datetime("us")).alias("_dropoff"),
    )

    # Cast numeric columns to avoid Null-type comparison errors
    raw = raw.with_columns(
        pl.col("trip_distance").cast(pl.Float64, strict=False),
        pl.col("fare_amount").cast(pl.Float64, strict=False),
        pl.col("total_amount").cast(pl.Float64, strict=False),
    )

    # Build boolean rejection mask columns
    raw = raw.with_columns(
        _rej_missing=(raw["tpep_pickup_datetime"].is_null() | raw["tpep_dropoff_datetime"].is_null()),
        _rej_distance_null=raw["trip_distance"].is_null(),
        _rej_distance_bad=raw["trip_distance"].is_not_null() & (raw["trip_distance"] <= 0.0),
        _rej_fare_null=raw["fare_amount"].is_null(),
        _rej_fare_bad=raw["fare_amount"].is_not_null() & (raw["fare_amount"] < 0.0),
        _rej_total_null=raw["total_amount"].is_null(),
        _rej_total_bad=raw["total_amount"].is_not_null() & (raw["total_amount"] < 0.0),
    )

    non_finite_cols = [
        "trip_distance",
        "fare_amount",
        "total_amount",
        "extra",
        "mta_tax",
        "tip_amount",
        "tolls_amount",
        "improvement_surcharge",
        "congestion_surcharge",
        "airport_fee",
    ]
    for col in non_finite_cols:
        if col in raw:
            raw = raw.with_columns(
                (pl.col(col).is_not_null() & ~pl.col(col).is_finite()).alias(f"_rej_nonfinite_{col}")
            )

    raw = raw.with_columns(
        _rej_month_before=raw["_pickup"].is_not_null() & (raw["_pickup"] < month_start),
        _rej_month_after=raw["_pickup"].is_not_null() & (raw["_pickup"] >= month_end),
    )

    pickup_ok = raw["_pickup"].is_not_null()
    dropoff_ok = raw["_dropoff"].is_not_null()
    both_ok = pickup_ok & dropoff_ok
    window_end = month_end + timedelta(hours=MONTH_WINDOW_HOURS)

    raw = raw.with_columns(
        _rej_dropoff_before=both_ok & (raw["_dropoff"] <= raw["_pickup"]),
        _rej_dropoff_window=both_ok & (raw["_dropoff"] >= window_end),
    )

    rejection_columns = [
        "_rej_missing",
        "_rej_distance_null",
        "_rej_distance_bad",
        "_rej_fare_null",
        "_rej_fare_bad",
        "_rej_total_null",
        "_rej_total_bad",
        "_rej_month_before",
        "_rej_month_after",
        "_rej_dropoff_before",
        "_rej_dropoff_window",
    ]
    rejection_columns.extend(f"_rej_nonfinite_{col}" for col in non_finite_cols if f"_rej_nonfinite_{col}" in raw)

    raw = raw.with_columns(pl.any_horizontal(rejection_columns).alias("_is_rejected"))

    rejected = raw.filter(pl.col("_is_rejected"))
    candidates = raw.filter(~pl.col("_is_rejected"))

    # 2. Build quality flags on accepted candidates
    candidates = candidates.with_columns(
        _flag_unknown_vendor=~pl.col("VendorID").is_in(list(vendor_lookup.keys())),
        _flag_unknown_payment=~pl.col("payment_type").is_in(list(payment_lookup.keys())),
        _flag_unknown_rate=~pl.col("RatecodeID").is_in(list(rate_code_lookup.keys())),
        _flag_bad_passenger=pl.col("passenger_count").is_null() | (pl.col("passenger_count") < 0),
    )

    nullable_money = [
        ("fare_amount", "_flag_null_fare"),
        ("extra", "_flag_null_extra"),
        ("mta_tax", "_flag_null_mta"),
        ("tip_amount", "_flag_null_tip"),
        ("tolls_amount", "_flag_null_tolls"),
        ("improvement_surcharge", "_flag_null_improvement"),
        ("total_amount", "_flag_null_total"),
        ("congestion_surcharge", "_flag_null_congestion"),
        ("airport_fee", "_flag_null_airport"),
    ]
    for col, flag in nullable_money:
        candidates = candidates.with_columns(
            pl.when(pl.col(col).is_null()).then(pl.lit(True)).otherwise(pl.lit(False)).alias(flag)
        )

    flag_columns = [
        "_flag_unknown_vendor",
        "_flag_unknown_payment",
        "_flag_unknown_rate",
        "_flag_bad_passenger",
        "_flag_null_fare",
        "_flag_null_extra",
        "_flag_null_mta",
        "_flag_null_tip",
        "_flag_null_tolls",
        "_flag_null_improvement",
        "_flag_null_total",
        "_flag_null_congestion",
        "_flag_null_airport",
    ]

    candidates = candidates.with_columns(pl.any_horizontal(flag_columns).alias("_has_any_flag"))

    # 3. Build issue records (sparse — only flagged rows)
    flagged_candidates = candidates.filter(pl.col("_has_any_flag"))
    issues = _build_issues(flagged_candidates)

    # 4. Compute KLL outlier bounds on accepted candidates
    kll_bounds = _compute_kll_bounds(candidates)

    # 5. Convert to output schema
    accepted = _convert_accepted(candidates, kll_bounds=kll_bounds)

    return TransformResult(
        accepted=accepted,
        rejected=rejected,
        issues=issues,
        source_rows=source_rows,
        accepted_rows=len(accepted),
        rejected_rows=len(rejected),
        flagged_rows=issues["source_row_number"].n_unique() if len(issues) else 0,
        source_month=source_month,
    )


def _month_bounds(source_month: str) -> tuple[datetime, datetime]:
    y, m = int(source_month[:4]), int(source_month[5:7])
    start = datetime(y, m, 1, tzinfo=None)
    end = datetime(y + 1, 1, 1, tzinfo=None) if m == 12 else datetime(y, m + 1, 1, tzinfo=None)
    return start, end


def _compute_kll_bounds(candidates: pl.DataFrame) -> dict[str, ThresholdBounds]:
    seconds = (candidates["_dropoff"] - candidates["_pickup"]).dt.total_seconds()
    dist = candidates["trip_distance"] * 1000.0

    bounds: dict[str, ThresholdBounds] = {}
    if len(seconds) > 100:
        sketch = build_sketch_from_iterable((float(s) for s in seconds if s is not None and 0 < s < 86400), k=DEFAULT_K)
        bounds["duration_seconds"] = compute_bounds(sketch, "duration_seconds")
    if len(dist) > 100:
        sketch = build_sketch_from_iterable(
            (float(d) for d in dist if d is not None and 0 < d < 1_000_000), k=DEFAULT_K
        )
        bounds["distance_millimiles"] = compute_bounds(sketch, "distance_millimiles")
    return bounds


def _convert_accepted(df: pl.DataFrame, *, kll_bounds: dict[str, ThresholdBounds]) -> pl.DataFrame:
    seconds_expr = (df["_dropoff"] - df["_pickup"]).dt.total_seconds().round(0).cast(pl.Int64)
    distance_expr = (df["trip_distance"] * 1000.0).round(0).cast(pl.Int64)

    outlier = pl.lit(False)
    if "duration_seconds" in kll_bounds:
        b = kll_bounds["duration_seconds"]
        outlier = outlier | seconds_expr.lt(b.low_bound) | seconds_expr.gt(b.high_bound)
    if "distance_millimiles" in kll_bounds:
        b = kll_bounds["distance_millimiles"]
        outlier = outlier | distance_expr.lt(b.low_bound) | distance_expr.gt(b.high_bound)

    return df.select(
        [
            pl.col("_source_row").alias("source_row_number"),
            pl.col("_pickup").alias("pickup_at_local"),
            pl.col("_dropoff").alias("dropoff_at_local"),
            seconds_expr.alias("duration_seconds"),
            pl.col("VendorID").fill_null(0).cast(pl.Int32).alias("vendor_id"),
            pl.col("tpep_pickup_datetime").alias("pickup_datetime_raw"),
            pl.col("tpep_dropoff_datetime").alias("dropoff_datetime_raw"),
            pl.col("passenger_count"),
            pl.col("PULocationID").fill_null(0).cast(pl.Int32).alias("pickup_location_id"),
            pl.col("DOLocationID").fill_null(0).cast(pl.Int32).alias("dropoff_location_id"),
            distance_expr.alias("distance_millimiles"),
            pl.col("RatecodeID").fill_null(0).cast(pl.Int32).alias("rate_code_id"),
            pl.col("store_and_fwd_flag"),
            pl.col("payment_type").fill_null(0).cast(pl.Int32).alias("payment_type_id"),
            (pl.col("fare_amount") * 100.0).round(0).cast(pl.Int64).alias("fare_amount_cents"),
            (pl.col("extra") * 100.0).round(0).cast(pl.Int64).alias("extra_cents"),
            (pl.col("mta_tax") * 100.0).round(0).cast(pl.Int64).alias("mta_tax_cents"),
            (pl.col("tip_amount") * 100.0).round(0).cast(pl.Int64).alias("tip_amount_cents"),
            (pl.col("tolls_amount") * 100.0).round(0).cast(pl.Int64).alias("tolls_amount_cents"),
            (pl.col("improvement_surcharge") * 100.0).round(0).cast(pl.Int64).alias("improvement_surcharge_cents"),
            (pl.col("total_amount") * 100.0).round(0).cast(pl.Int64).alias("total_amount_cents"),
            (pl.col("congestion_surcharge") * 100.0).round(0).cast(pl.Int64).alias("congestion_surcharge_cents"),
            (pl.col("airport_fee") * 100.0).round(0).cast(pl.Int64).alias("airport_fee_cents"),
            pl.col("_has_any_flag").alias("has_quality_issue"),
            outlier.alias("has_statistical_outlier"),
        ]
    )


def _build_issues(df: pl.DataFrame) -> pl.DataFrame:
    """Build sparse issue rows from flagged candidates. One row per flag per row."""
    issue_rows: list[dict[str, object]] = []
    mapping: list[tuple[str, IssueCode]] = [
        ("_flag_unknown_vendor", IssueCode.UNKNOWN_VENDOR),
        ("_flag_unknown_payment", IssueCode.UNKNOWN_PAYMENT),
        ("_flag_unknown_rate", IssueCode.UNKNOWN_RATE),
        ("_flag_bad_passenger", IssueCode.INVALID_PASSENGER_COUNT),
        ("_flag_null_fare", IssueCode.NULL_FARE),
        ("_flag_null_extra", IssueCode.NULL_EXTRA),
        ("_flag_null_mta", IssueCode.NULL_MTA_TAX),
        ("_flag_null_tip", IssueCode.NULL_TIP),
        ("_flag_null_tolls", IssueCode.NULL_TOLLS),
        ("_flag_null_improvement", IssueCode.NULL_IMPROVEMENT),
        ("_flag_null_total", IssueCode.NULL_TOTAL),
        ("_flag_null_congestion", IssueCode.NULL_CONGESTION),
        ("_flag_null_airport", IssueCode.NULL_AIRPORT_FEE),
    ]

    row_dicts = df.select(["_source_row"] + [c for c, _ in mapping]).to_dicts()
    for row in row_dicts:
        source_row = row["_source_row"]
        for col, code in mapping:
            if row.get(col):
                issue_rows.append(
                    {
                        "source_row_number": source_row,
                        "issue_code": code.value,
                    }
                )

    if not issue_rows:
        return pl.DataFrame(schema={"source_row_number": pl.Int64, "issue_code": pl.Utf8})
    return pl.DataFrame(issue_rows)
