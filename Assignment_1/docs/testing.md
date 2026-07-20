# Testing

## Command Order

```bash
uv run ruff check .                    # Lint
uv run ruff format --check .           # Format check
uv run mypy src tests                  # Type check
uv run pytest tests/unit               # Unit tests
uv run pytest tests/integration        # Integration tests (requires PostgreSQL)
uv run pytest --cov --cov-branch --cov-fail-under=85  # Coverage gate
```

## Test Suites

| Suite | Directory | Requirements |
|-------|-----------|-------------|
| Unit | `tests/unit/` | None — pure Python |
| Integration | `tests/integration/` | PostgreSQL at localhost:5432 |
| DAG | `tests/dags/` | Airflow package importable |
| Dashboard | `tests/dashboard/` | Requires `streamlit` dep group |

## Run Specific Tests

```bash
uv run pytest tests/unit/test_version.py -v
uv run pytest tests/unit/transform/ -v
uv run pytest tests/unit/test_kll.py -v
uv run pytest tests/unit/test_contract.py -v
uv run pytest tests/unit/storage/ -v
uv run pytest tests/unit/load/ -v
```

## Fixtures

Minimal fixture data lives in `tests/fixtures/`. Transform tests use inline test data via `_valid_row()` helper.

## Coverage Gate

- Minimum: 85% branch coverage
- Source paths: `src/` only
- Excluded: `TYPE_CHECKING` blocks, `NotImplementedError`, `pragma: no cover`

## Release Gates

- CI: ruff, mypy, pytest + coverage, SQLFluff
- Release: all CI checks + image builds + kind smoke (requires Kubernetes cluster)
- Manual: Playwright dashboard smoke, backup/restore drill, failure drill
