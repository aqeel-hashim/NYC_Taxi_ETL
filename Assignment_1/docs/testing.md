# Testing

## Complete Gate

```bash
VERIFY_IMAGES=false ./scripts/verify.sh
```

The script creates a disposable PostgreSQL container when `TEST_DATABASE_URL` is absent, migrates it, and runs:

- frozen lock validation and dependency sync;
- Ruff lint and formatting;
- strict mypy across source, Airflow, dashboard, webhook, and tests;
- 95 unit, integration, DAG, dashboard, security, and manifest tests;
- minimum 85% branch coverage;
- shell lifecycle tests;
- SQLFluff for required SQL;
- Compose and Docker-context validation.

`VERIFY_IMAGES=true` additionally builds three runtime images. It is disabled on hosts where Docker/network behavior prevents deterministic image builds; CI performs image builds independently.

## Suites

| Suite | Directory | Coverage |
|---|---|---|
| Unit | `tests/unit/` | contracts, transforms, KLL, CLI/error categories |
| Integration | `tests/integration/` | migrations, roles, partitions, idempotent ETL, dimension keys, required SQL |
| Dashboard | `tests/dashboard/` | real tab rendering, state, SQL builders, geometry, migration, performance |
| DAG | `tests/dags/` | Airflow DAG import and task graph |
| Security/operations | `tests/phase8/`, `tests/phase9/` | alerts, manifests, observability |
| Shell | `tests/shell/` | lifecycle CLI contracts |

## Live E2E

```bash
bash ./setup.sh --local-demo --no-dashboard
```

This is the examiner-style E2E: official downloads, Docker PostgreSQL, local Airflow execution for both months, and final warehouse assertions. Run Streamlit afterward with:

```bash
set -a; source .env; set +a
.venv/bin/streamlit run dashboard/app.py --server.port 8501
```
