# ADR-0004: Reference Dimension Versioning

## Status

Schema capability reserved; evaluator loader uses static references.

## Decision

Taxi zone, payment, vendor, and rate dimensions have surrogate keys and observed-time columns. The constraints permit a future ingestion-time SCD2 implementation without changing fact foreign keys.

The current loader inserts missing bundled reference rows with a fixed initial observation timestamp and `ON CONFLICT DO NOTHING`. It does not close versions, insert successors, populate `reference_snapshot_id`, or pin facts to snapshots.

## Rationale

The two-month assessment uses one bundled TLC lookup version. Static loading is sufficient and easier to explain. SCD2 should be implemented only when multiple reference snapshots are actually ingested.
