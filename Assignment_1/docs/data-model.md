# Data Model

## Star Schema

Six role-playing dimensions, one fact table, one aggregate mart.

### Dimensions

| Dimension | Key Type | SCD Type | Business Key |
|-----------|----------|----------|-------------|
| `dim_date` | Integer (`YYYYMMDD`) | Static seed | Calendar date |
| `dim_time` | Smallint (`0..1439`) | Static seed | Minute of day |
| `dim_taxi_zone` | Integer surrogate | SCD2 (observed) | `LocationID` |
| `dim_payment_type` | Integer surrogate | SCD2 (observed) | Payment code |
| `dim_vendor` | Integer surrogate | SCD2 (observed) | Vendor code |
| `dim_rate_code` | Integer surrogate | SCD2 (observed) | Rate code |

All dimension surrogate keys start at 1. Key `0` is Unknown.

### Fact: `warehouse.fact_taxi_trips`

- Grain: one hard-valid source row.
- Monthly range partition on `pickup_date_key` (`YYYYMMDD`).
- Composite PK: `pickup_date_key`, `trip_key`.
- Unique source identity: pickup partition + source asset ID/version + source row number.
- Role-playing FKs: pickup/dropoff date, time, zone (reuse dim_date, dim_time, dim_taxi_zone).
- Integer cents for all money columns.
- Integer millimiles for distance.
- Integer seconds for duration.
- `has_statistical_outlier` and `has_quality_issue` boolean flags.

### Mart: `analytics.trip_metrics_hourly`

- Grain: pickup date, pickup hour, pickup zone, payment, vendor, rate, stat_outlier flag, quality_issue flag.
- All measures are additive SUMs.
- Required ratios use ratio-of-sums, never average-of-ratios.
- Monthly partitioned.

### SCD2 Observed-Time Semantics

- `observed_from`: timestamp when this version was first ingested.
- `observed_to`: NULL for current, timestamp of successor ingestion otherwise.
- `is_current` = (`observed_to IS NULL`).
- Exclusion constraint: no overlap on business key + `[observed_from, observed_to)`.
- Each monthly ETL pins a reference snapshot; reruns reuse that snapshot.

### Metric Definitions

| Metric | Formula | Outlier Policy |
|--------|---------|----------------|
| Average fare per mile | `10.0 * SUM(fare_amount_cents) / NULLIF(SUM(distance_millimiles), 0)` | Exclude outliers |
| Peak ride hours | `COUNT(*) GROUP BY pickup_hour` | Include all hard-valid |
| Revenue by payment type | `SUM(total_amount_cents) / 100.0` | Exclude outliers |
| Recorded card tip rate | `100.0 * SUM(tip_amount_cents) / NULLIF(SUM(fare_amount_cents), 0)` | Credit card only, exclude outliers |
| Weighted network speed | `3.6 * SUM(distance_millimiles) / NULLIF(SUM(duration_seconds), 0)` | Exclude outliers |

### Source Reconciliation

```
source_rows = accepted_rows + rejected_rows
flagged_rows <= accepted_rows
staged_fact_rows = loaded_fact_rows = published_fact_rows = accepted_rows
```
