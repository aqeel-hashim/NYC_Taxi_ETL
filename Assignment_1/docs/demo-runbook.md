# Demo Runbook

## Current Capability

Core ETL works on disposable PostgreSQL. Full platform demo pending Phases 5-14.

## Prerequisites

- Docker engine running
- `uv` installed
- 1 GiB free disk space

## Core ETL Demo

```bash
cd Assignment_1
./setup.sh --only preflight
# Start disposable PostgreSQL (see plans/001-warehouse-contract.md):
export TEST_DB_PASSWORD="$(openssl rand -hex 16)"
docker run --rm -d --name a1-test-postgres \
  -e POSTGRES_DB=taxi_warehouse -e POSTGRES_USER=taxi_app \
  -e POSTGRES_PASSWORD="$TEST_DB_PASSWORD" -p 127.0.0.1:55432:5432 \
  pgvector/pgvector:pg17
export TEST_DATABASE_URL="postgresql+psycopg://taxi_app:${TEST_DB_PASSWORD}@127.0.0.1:55432/taxi_warehouse"
for i in $(seq 1 60); do docker exec a1-test-postgres pg_isready -U taxi_app -d taxi_warehouse && break; sleep 1; done
DATABASE_URL="$TEST_DATABASE_URL" .venv/bin/alembic upgrade head
# Fixture run:
DATABASE_URL="$TEST_DATABASE_URL" ./scripts/run-pipeline.sh 2023-01 --fixture
# Real runs (download required):
DATABASE_URL="$TEST_DATABASE_URL" ./scripts/run-pipeline.sh 2023-01
DATABASE_URL="$TEST_DATABASE_URL" ./scripts/run-pipeline.sh 2023-02
# Verify:
TEST_DATABASE_URL="$TEST_DATABASE_URL" ./scripts/verify.sh
# Dashboard:
DATABASE_URL="$TEST_DATABASE_URL" uv run streamlit run dashboard/app.py
# Cleanup:
docker rm -f a1-test-postgres
```

## Full Platform Demo

Pending Phase 11. Will replace above when kind, MinIO, CNPG, Airflow KubernetesExecutor, OIDC, Prometheus/Grafana/Loki, and backup/restore are implemented.

## Troubleshooting

- **Docker not running**: `sudo service docker start` or `sudo systemctl start docker`
- **Port 5432 in use**: Stop other PostgreSQL instances first
- **Migration fails**: `docker compose -f infra/local/compose.postgres.yaml down -v` then re-run setup
