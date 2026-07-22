# Data Model

## Star Schema

Six role-playing dimensions, one fact table, one aggregate mart.

### Dimensions

| Dimension | Key Type | SCD Type | Business Key |
|-----------|----------|----------|-------------|
| `dim_date` | Integer (`YYYYMMDD`) | Static seed | Calendar date |
| `dim_time` | Smallint (`0..1439`) | Static seed | Minute of day |
| `dim_taxi_zone` | Integer surrogate | Static reference | `LocationID` |
| `dim_payment_type` | Integer surrogate | Static reference | Payment code |
| `dim_vendor` | Integer surrogate | Static reference | Vendor code |
| `dim_rate_code` | Integer surrogate | Static reference | Rate code |

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

### Reference Versioning

The schema reserves observed-time columns for future SCD2 handling. The evaluator loader treats the bundled TLC lookups as static references: it inserts missing business keys and does not create successor versions or pin snapshots.

### Metric Definitions

| Metric | Formula | Outlier Policy |
|--------|---------|----------------|
| Average fare per mile | `10.0 * SUM(fare_amount_cents) / NULLIF(SUM(distance_millimiles), 0)` | Exclude outliers |
| Peak ride hours | `COUNT(*) GROUP BY pickup_hour` | Include all hard-valid |
| Revenue by payment type | `SUM(total_amount_cents) / 100.0` | Include all accepted rows |
| Recorded card tip rate | `100.0 * SUM(tip_amount_cents) / NULLIF(SUM(fare_amount_cents), 0)` | Credit card only, exclude outliers |
| Weighted network speed | `3.6 * SUM(distance_millimiles) / NULLIF(SUM(duration_seconds), 0)` | Exclude outliers |

### Source Reconciliation

```
source_rows = accepted_rows + rejected_rows
flagged_rows <= accepted_rows
staged_fact_rows = loaded_fact_rows = published_fact_rows = accepted_rows
```
