# ADR-0004: Observed-Time SCD2 for Reference Dimensions

## Status

Accepted.

## Context

Dimension tables (taxi zone, payment type, vendor, rate code) change over time: TLC updates zone definitions, payment codes may be added, vendors change. The warehouse must:

1. Reference the version of a dimension that was current when a trip was ingested.
2. Support reruns that pin the same reference snapshot.
3. Avoid overwriting historical dimension-to-fact relationships.

Traditional "effective-time" SCD2 implies the business effective date, which may not match when the warehouse first observed the change. The warehouse cannot know the true effective date — only when it ingested the reference data.

## Decision

Use **ingestion-time (observed-time) SCD2** with `observed_from` and nullable `observed_to` columns.

- `observed_from`: timestamp when this version was first ingested into the warehouse.
- `observed_to`: timestamp when a newer version was ingested (NULL for current).
- `is_current` = (`observed_to IS NULL`).
- Exclusion constraint: no overlapping `[observed_from, observed_to)` for the same business key.
- Each monthly ETL pins a reference snapshot ID; reruns reuse that snapshot.

## Alternatives Considered

- **Effective-time SCD2**: Requires business knowledge of when a zone/payment/vendor actually changed. The warehouse only knows when it ingested the change.
- **SCD1 (overwrite)**: Loses history. Cannot explain why past reports used different dimension labels.
- **SCD3 (limited history)**: Insufficient for auditing.

## Consequences

- Column names `observed_from`/`observed_to` are explicit about semantics.
- Requires `btree_gist` extension for exclusion constraint.
- Historical dimension changes are fully auditable by ingestion timeline.
- Each monthly partition's stuck-to-snapshot behavior prevents mid-month dimension changes from altering published results.
