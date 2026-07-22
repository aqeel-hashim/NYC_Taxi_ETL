# Assignment 1 v0.1.0 Release Evidence

Validated locally on 2026-07-22 with official TLC Parquet files.

## Real Two-Month ETL

| Month | Source | Accepted | Rejected | Flagged | Quality issues | Duplicates |
|---|---:|---:|---:|---:|---:|---:|
| 2023-01 | 3,066,766 | 2,998,637 | 68,129 | 75,415 | 203,815 | 0 |
| 2023-02 | 2,913,955 | 2,850,602 | 63,353 | 82,782 | 227,192 | 0 |

Source SHA-256:

- January: `32df6f67578fa86c484a6b5ef23a5281992ff085521082340b0f9e5889e9a572`
- February: `4809e6aaac64f05a62d16a25d55713be1537ad64fc261e895eaf2d2120fe750a`

Database assertions:

- 5,849,239 total facts across exactly two monthly partitions;
- zero unknown pickup-zone keys;
- 258 pickup zones across eight boroughs;
- dashboard mart sums to all facts;
- quality detail and summary totals match each month;
- immediate reruns preserve counts and hashes.

## Dashboard

Live database AppTest:

- zero uncaught exceptions;
- zero rendered errors;
- five tabs;
- nine Plotly charts;
- fifteen data tables;
- 263-feature official TLC taxi-zone GeoJSON;
- desktop and 390 px mobile captures in `docs/images/`.

## Automated Validation

Command: `VERIFY_IMAGES=false ./scripts/verify.sh`

- Ruff lint and format: pass
- strict mypy: pass
- pytest: 95 passed
- branch coverage: 86.31% (required: 85%)
- Alembic fresh migration: pass
- SQLFluff: pass
- lifecycle shell tests: pass
- Compose validation: pass

Image builds are a separate CI/release concern. The evaluator E2E does not require Kubernetes or application image builds.
