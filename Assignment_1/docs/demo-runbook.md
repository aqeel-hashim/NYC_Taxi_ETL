# Demo Runbook

## Prerequisites

- Docker engine running
- `uv` installed (`curl -LsSf https://astral.sh/uv/install.sh | sh`)
- 40 GiB free disk space
- Big PC: WSL2 with Docker integration
- Small PC: native Linux with Docker

## Quick Start

```bash
cd Assignment_1
./setup.sh
```

Setup stages: `preflight > tools > python_env > database > verify`.

To start from a specific stage after failure:
```bash
./setup.sh --from database
```

## Available Commands

| Command | Purpose |
|---------|---------|
| `./setup.sh` | Full reproducible setup |
| `./teardown.sh` | Stop services, keep data |
| `./teardown.sh --purge all` | Delete all data and caches |
| `./scripts/verify.sh` | Run all static checks + tests |
| `./scripts/run-pipeline.sh 2023-01` | Run ETL for a month |
| `uv run pytest -v` | Run unit tests |
| `uv run alembic upgrade head` | Apply DB migrations |
| `uv run alembic downgrade -1` | Rollback last migration |

## Verify

```bash
uv run ruff check .
uv run mypy src tests
uv run pytest --cov --cov-branch --cov-fail-under=85
```

## Database

PostgreSQL runs via Docker Compose at `localhost:5432`.

Schema: `warehouse.*` (facts/dims), `analytics.*` (marts), `ops.*` (pipeline metadata).

Required SQL queries in `sql/queries/`:
- `average_fare_per_mile.sql`
- `peak_ride_hours.sql`
- `revenue_by_payment_type.sql`

## Demo Flow

1. `./setup.sh`
2. Run ETL for January 2023: `./scripts/run-pipeline.sh 2023-01`
3. Run ETL for February 2023: `./scripts/run-pipeline.sh 2023-02`
4. Run required SQL queries against PostgreSQL
5. Verify reconciliation: `source_rows = accepted_rows + rejected_rows`
6. Start Streamlit dashboard: `uv run streamlit run dashboard/app.py`
7. Explore metrics: avg fare/mile, peak hours, revenue by payment type
8. Tear down: `./teardown.sh`

## Troubleshooting

- **Docker not running**: `sudo service docker start` or `sudo systemctl start docker`
- **Port 5432 in use**: Stop other PostgreSQL instances first
- **Migration fails**: `docker compose -f infra/local/compose.postgres.yaml down -v` then re-run setup
