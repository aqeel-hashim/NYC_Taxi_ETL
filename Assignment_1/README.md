# Assignment 1: Batch ETL

Status: Assignment 1 warehouse contract works; local ETL vertical slice in progress.

## Verified Local Commands

Run from `Assignment_1/`.

```bash
./setup.sh --only preflight
DATABASE_URL="$TEST_DATABASE_URL" .venv/bin/alembic upgrade head
DATABASE_URL="$TEST_DATABASE_URL" ./scripts/run-pipeline.sh 2023-01 --fixture
TEST_DATABASE_URL="$TEST_DATABASE_URL" ./scripts/verify.sh
```

Use the disposable PostgreSQL harness in `../plans/001-warehouse-contract.md` for `TEST_DATABASE_URL`. Real January load uses the same command without `--fixture`; Kubernetes, Airflow runtime images, dashboard, and AWS remain planned.

Airflow runtime image:

```bash
docker build -f docker/airflow.Dockerfile -t nyc-taxi-airflow:test .
```

Dashboard:

```bash
docker build -f docker/dashboard.Dockerfile -t nyc-taxi-dashboard:test .
docker run --rm --network host -e DATABASE_URL="$TEST_DATABASE_URL" nyc-taxi-dashboard:test
```

[Implementation plan](docs/implementation-plan.md) | [Architecture](docs/architecture.md) | [Data model](docs/data-model.md)

## Requirement Traceability

| Requirement | Owner Phase |
|-------------|-------------|
| Bash `setup.sh`, virtual env, Docker PostgreSQL, `curl`/`wget` download | Phase 1, 11 |
| `schema.sql` with fact table + ≥3 dimensions | Phase 4 |
| Modern orchestrator (Airflow) | Phase 6, 7 |
| Structured logging (start/end, row counts, errors) | Phase 6 |
| Orchestrator alerts on failure | Phase 8, 9 |
| SQL: average fare per mile | Phase 4 |
| SQL: peak ride hours | Phase 4 |
| SQL: revenue by payment type | Phase 4 |
| Single-page Streamlit dashboard | Phase 10 |

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
