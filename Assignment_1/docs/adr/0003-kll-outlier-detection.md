# ADR-0003: KLL Outlier Flags

## Status

Implemented for monthly duration and distance distributions.

## Decision

The transform builds Apache DataSketches KLL sketches from accepted rows for each source month. Duration and distance values outside the computed 0.001 and 0.999 quantile bounds set `has_statistical_outlier`.

Outliers remain in the fact table. Demand metrics include them; dashboard unit metrics exclude them by default and expose an include-outliers toggle. The required total-revenue SQL includes every accepted row.

## Limits

- Bounds are recalculated per month, not loaded from a persisted baseline.
- Speed and fare-per-mile are not independently sketched.
- Rejected rows do not contribute to calibration.

Persisted cross-month calibration is an extension, not part of the validated evaluator path.
