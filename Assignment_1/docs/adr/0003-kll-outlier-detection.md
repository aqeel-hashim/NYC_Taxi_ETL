# ADR-0003: KLL Sketch Statistical Outlier Detection

## Status

Accepted.

## Context

Taxi trip data contains extreme values (e.g., $10,000 fare for a 0.1-mile trip, 24-hour duration) that distort aggregate metrics. Traditional approaches like fixed thresholds or standard-deviation-based trimming are brittle across different months and metrics.

The assignment requires financial/unit metrics to exclude statistical outliers by default while demand counts retain all hard-valid rows.

## Decision

Use **Apache DataSketches KLL** sketches (`k=4096`) to compute distribution tails for four metrics: duration, distance, speed, and fare-per-mile.

Values below the 0.001 quantile or above the 0.999 quantile are flagged with `has_statistical_outlier = true`. Values equal to a bound are not outliers. The threshold version is calibrated once from January-February 2023 data and activated as `2023-baseline-v1`.

Recalibration uses quarterly trailing-12-month data and requires review before activation.

## Alternatives Considered

- **Z-score / IQR**: Parametric assumptions; fares and distances are heavy-tailed. KLL is nonparametric.
- **Fixed thresholds**: Brittle; taxi fares change over time.
- **Winsorization**: The plan explicitly forbids overwriting observed values.

## Consequences

- Adds DataSketches dependency (Python wrapper or JNI bridge).
- `arm64` wheel availability must be verified for both `amd64` and `arm64` builds.
- KLL merge is order-sensitive for identical byte output; reproducibility comes from persisting the activated artifact, not byte-identical rebuilds.
- Exact fixture quantiles validate rank error stays within the library-reported bound.
- Rejected rows never enter KLL; only hard-valid rows contribute to calibration.
