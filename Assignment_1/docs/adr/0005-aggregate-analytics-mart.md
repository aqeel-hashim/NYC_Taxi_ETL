# ADR-0005: Incremental Aggregate Analytics Mart

## Status

Accepted.

## Context

The fact table may contain millions of rows per month. The dashboard requires sub-second cached responses for aggregate queries (average fare per mile, peak hours, revenue by payment type). Repeated full fact scans on every dashboard load are unacceptable.

## Decision

Build an **incrementally rebuilt analytics mart** (`analytics.trip_metrics_hourly`) as the dashboard's primary query target.

- Grain: pickup date, pickup hour, pickup zone, payment type, vendor, rate code, outlier flag, quality-issue flag.
- Additive measures: trip count, passenger count/sum, distance, duration, every money component (all integer cents/millimiles/seconds).
- Required ratios use **ratio-of-sums**: `SUM(numerator) / SUM(denominator)`, never average-of-ratios.
- Monthly partition; rebuilt only for the target month during publish.
- Cache key: filters + published warehouse version. New publish invalidates cache.

## Alternatives Considered

- **Live fact scans**: Too slow for interactive dashboard. Cannot meet sub-second target on full data.
- **Materialized views**: PostgreSQL materialized views require full refresh; incremental rebuild is faster.
- **Pre-computed ratios only**: Loses additive measures needed for different filter combinations.

## Consequences

- Adds `analytics` schema and mart table.
- Mart rebuild is part of the atomic monthly publish transaction.
- Financial/unit metrics exclude statistical outliers by default; demand counts include all hard-valid rows.
- Dashboard queries are simple aggregations over the mart, not complex joins over the star schema.
- Performance budgets measured as uncached p95 with documented hardware.
