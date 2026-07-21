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

| Suite | Directory | Status |
|-------|-----------|--------|
| Unit | `tests/unit/` | PASS |
| Integration | `tests/integration/` | PASS (needs PostgreSQL) |
| Dashboard | `tests/dashboard/` | PASS |
| DAG | `tests/dags/` | NOT_STARTED |
| E2E | `tests/e2e/` | NOT_STARTED |

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

- CI: ruff, mypy, pytest + coverage, SQLFluff (PASS)
- Release: kind smoke, Playwright, backup/restore, failure drill (NOT_STARTED, blocked on K8s)
- Manual: Playwright dashboard smoke (NOT_STARTED)
