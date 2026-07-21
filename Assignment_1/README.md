# Assignment 1: Batch ETL

Status: Phases 0-4 (core ETL): PASS. Phases 5-14: IN PROGRESS.

## Truth Matrix

| Phase | Description | Verifier Gate |
|-------|-------------|---------------|
| 0 | Architecture decisions | PASS |
| 1 | Bootstrap toolchain | PASS |
| 2 | Data contract, fixtures, transform | PASS |
| 3 | KLL calibration | PASS |
| 4 | PostgreSQL schema + SQL | PASS |
| 5 | Object storage, load, atomic publish | PASS |
| 6 | Airflow DAGs + runtime images | PASS |
| 7 | Kubernetes vertical slice | PARTIAL (scripts/values; needs cluster) |
| 8 | Ingress, TLS, OIDC, alerts | PARTIAL (values; needs deploy) |
| 9 | Monitoring, logging, recovery | PARTIAL (values; needs deploy) |
| 10 | Executive dashboard | PARTIAL (three-metric dashboard) |
| 11 | Complete setup + demo | PARTIAL (preflight; deploy pending) |
| 12 | CI, release, supply chain | PARTIAL (CI runs verify) |
| 13 | Guarded AWS Terraform | PARTIAL (module exists) |
| 14 | Final docs + review | NOT_STARTED |

## Verified Commands

```bash
./setup.sh --only preflight
DATABASE_URL="$TEST_DATABASE_URL" .venv/bin/alembic upgrade head
DATABASE_URL="$TEST_DATABASE_URL" ./scripts/run-pipeline.sh 2023-01 --fixture
DATABASE_URL="$TEST_DATABASE_URL" ./scripts/run-pipeline.sh 2023-01
DATABASE_URL="$TEST_DATABASE_URL" ./scripts/run-pipeline.sh 2023-02
TEST_DATABASE_URL="$TEST_DATABASE_URL" ./scripts/verify.sh
docker build -f docker/airflow.Dockerfile -t nyc-taxi-airflow:test .
docker build -f docker/dashboard.Dockerfile -t nyc-taxi-dashboard:test .
```

## Requirement Traceability

| Requirement | Phase | Gate |
|-------------|-------|------|
| Bash `setup.sh`, virtual env, Docker PostgreSQL, `curl`/`wget` download | 1, 11 | PASS |
| `schema.sql` with fact table + ≥3 dimensions | 4 | PASS |
| Modern orchestrator (Airflow) | 6, 7 | PASS (DAGs, calibration, failure drill) |
| Structured logging (start/end, row counts, errors) | 6 | PASS (JSON logs) |
| Orchestrator alerts on failure | 8, 9 | PARTIAL (webhook receiver exists; no live deploy) |
| SQL: average fare per mile | 4 | PASS |
| SQL: peak ride hours | 4 | PASS |
| SQL: revenue by payment type | 4 | PASS |
| Single-page Streamlit dashboard | 10 | PASS (three-metric dashboard) |

## Agreed Assumptions

- NYC Yellow Taxi January-February 2023.
- Airflow KubernetesExecutor on kind, PostgreSQL (CloudNativePG), Polars, MinIO, Streamlit/Plotly.
- Average fare per mile = ratio of summed fare to summed distance (not average trip-level ratios).
- Revenue = summed `total_amount` for hard-valid, non-refund rows.
- Financial/unit metrics exclude statistical outliers; demand counts retain all hard-valid rows.
- Peak hour = pickup trip count by local NYC wall-clock hour.
- Hardware may use staged/stage-by-stage activation. Multi-broker Kafka is Assignment 2.

## Architecture Decisions

| ADR | Decision |
|-----|----------|
| [0001](docs/adr/0001-kubernetes-executor.md) | KubernetesExecutor for Airflow |
| [0002](docs/adr/0002-minio-object-store.md) | MinIO as local S3-compatible object store |
| [0003](docs/adr/0003-kll-outlier-detection.md) | KLL sketches for statistical outlier detection |
| [0004](docs/adr/0004-observed-time-scd2.md) | Observed-time SCD2 for reference dimensions |
| [0005](docs/adr/0005-aggregate-analytics-mart.md) | Incremental aggregate analytics mart |
| [0006](docs/adr/0006-resource-profiles.md) | Staged and concurrent resource profiles |
| [0007](docs/adr/0007-oidc-authentication.md) | OIDC auth with Dex and oauth2-proxy |
| [0008](docs/adr/0008-observability.md) | kube-prometheus-stack + Loki observability |
| [0009](docs/adr/0009-aws-eks-production.md) | AWS EKS as production target |

## Non-Goals

- Assignment 2 Kafka streaming in Assignment 1.
- 50,000 streaming events/second in Assignment 1.
- Public 100,000-client API/web frontend.
- EKS Airflow and MWAA simultaneously deployed.
- Redshift enabled by default.
- Spark locally; documented threshold for AWS migration.
- Second full Docker Compose platform.
- Full rejected rows in PostgreSQL.
- Silent data repair, winsorization, or synthesis.

## Execution Phases

| Phase | Description | Commit |
|-------|-------------|--------|
| 0 | Record architecture decisions | `docs(a1): record architecture decisions` |
| 1 | Bootstrap reproducible toolchain | `chore(a1): bootstrap pinned toolchain` |
| 2 | Data contract, fixtures, pure transform | `feat(a1): add typed trip transformation` |
| 3 | KLL calibration | `feat(a1): add versioned KLL quality bounds` |
| 4 | PostgreSQL schema + SQL contract | `feat(a1): add dimensional warehouse schema` |
| 5 | Object storage, load, atomic publish | `feat(a1): publish monthly warehouse partitions` |
| 6 | Thin Airflow DAGs + runtime images | `feat(a1): orchestrate monthly ETL with Airflow` |
| 7 | Minimal Kubernetes vertical slice | `feat(a1): run ETL on local Kubernetes` |
| 8 | Ingress, TLS, OIDC, alerts | `feat(a1): secure local platform access` |
| 9 | Monitoring, logging, failure, recovery | `feat(a1): add platform observability and recovery` |
| 10 | Executive dashboard | `feat(a1): add executive taxi dashboard` |
| 11 | Complete setup + demo automation | `feat(a1): automate reproducible local demo` |
| 12 | CI, release gates, supply chain | `ci(a1): enforce release and supply-chain gates` |
| 13 | Guarded AWS Terraform | `feat(a1): add guarded AWS deployment` |
| 14 | Final documentation + review | `docs(a1): finalize demo and operations guide` |

## Machine Profiles

Run `/bigpc` or `/smallpc` after fresh OpenCode session. Big PC (WSL2) expected concurrent only after Docker preflight confirms ≥8 GiB memory, ≥4 CPUs. Small PC expects staged or stage-by-stage. See [`docs/agents/machine-profiles.md`](../docs/agents/machine-profiles.md).
