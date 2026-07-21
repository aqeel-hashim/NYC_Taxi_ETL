# Plan 004: Deliver Minimal Working Streamlit Dashboard

> **Executor instructions**: Implement only required metrics first. Use Plan 001 SQL and Plan 002 fixture. Update index when done.
>
> **Drift check**: `git diff --stat dd3a4b9..HEAD -- Assignment_1/dashboard Assignment_1/docker/dashboard.Dockerfile Assignment_1/tests/dashboard`

## Status

- **State**: DONE
- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: `plans/001-warehouse-contract.md`, `plans/002-local-etl-vertical-slice.md`
- **Category**: bug, tests, performance
- **Planned at**: commit `dd3a4b9`, 2026-07-21

## Why This Matters

Current page has broken month filtering, unused outlier/cache controls, SQL text placeholders, no quality/explorer implementation, and embedded privileged DB credential. Dashboard image builds but exits because Polars is missing. Assignment requires one working page showing three metrics, not five placeholder tabs.

## Current State

- `dashboard/app.py:31-34` compares `YYYYMM` expression against `YYYY` parameter.
- `dashboard/app.py:43-74` renders placeholders for four tabs.
- `dashboard/app.py:17-18` reads custom cache but never uses/saves it.
- `dashboard/queries.py:8-26` uses one global transactional connection and fixed loopback endpoint.
- Local image import: `ModuleNotFoundError: No module named 'polars'`.

## Commands

| Purpose | Command | Expected |
|---------|---------|----------|
| App tests | `.venv/bin/pytest tests/dashboard -q` | all pass |
| Image build | `docker build -f docker/dashboard.Dockerfile -t nyc-taxi-dashboard:test .` | success |
| Import smoke | `docker run --rm nyc-taxi-dashboard:test python -c 'import dashboard.queries'` | exit 0 |
| UI smoke | commands below | health body `ok` |

```bash
# Prerequisite: Plan 001 harness is running/migrated and Plan 002 fixture load passed.
docker rm -f a1-dashboard-test >/dev/null 2>&1 || true
docker run -d --network host --name a1-dashboard-test \
  -e DATABASE_URL="$TEST_DATABASE_URL" nyc-taxi-dashboard:test
for i in $(seq 1 60); do body="$(curl -fsS http://127.0.0.1:8501/_stcore/health 2>/dev/null)" && break; sleep 1; done
test "$body" = "ok"
docker rm -f a1-dashboard-test
```

Expected: `ok` within 60 seconds; cleanup exits 0. Committed smoke helper adds a cleanup `trap`.

## Scope

**In scope**:
- `Assignment_1/dashboard/app.py`
- `Assignment_1/dashboard/queries.py`
- `Assignment_1/dashboard/state.py` (delete if replaced)
- `Assignment_1/docker/dashboard.Dockerfile`
- `Assignment_1/tests/dashboard/` (create)
- `Assignment_1/pyproject.toml` dashboard group
- `Assignment_1/uv.lock`

**Out of scope**:
- Five-tab executive design, maps, geometry, keyset explorer.
- OIDC, Traefik, Kubernetes deployment.
- Warehouse formula changes; Plan 001 owns SQL.

## Git Workflow

- Use `feature/a1-dashboard` if requested.
- Do not commit/push without instruction.
- Suggested commit: `feat(a1): show required taxi metrics`.

## Steps

### Step 1: Make Query Layer Configurable And Safe

Read connection URL from environment/Streamlit secret; no literal credential. Use read-only autocommit connection pool or short-lived connections. Parameterize values. Query approved SQL/views only. Roll back/discard failed connections.

**Verify**: query tests cover success, timeout/error, no credential in source.

### Step 2: Implement Three Required Metrics

One page:

1. Average fare per mile, ratio-of-sums.
2. Peak pickup hour, 24-hour grain.
3. Revenue by payment type.

Use Plan 001 SQL or thin parameterized variants. Add month selector with explicit date-key range. Outlier policy applies only where documented. Render tables/native Streamlit charts; avoid Plotly unless required feature cannot use native charts.

**Verify**: fixture values match integration SQL exactly.

### Step 3: Remove False Features

Delete placeholder quality/explorer tabs and unused custom cache. If caching is needed, use `st.cache_data` keyed by filters and publication version; otherwise no cache.

**Verify**: no `Not connected`, SQL source placeholders, or unused cache variable remains.

### Step 4: Handle Empty And Error States

Display zero/empty/no-publication states without formatting `None`. Log detailed DB errors server-side; show generic user message and correlation ID. Preserve labels and keyboard accessibility.

**Verify**: AppTest covers populated, empty, and DB-error states.

### Step 5: Build And Start Image

Install frozen dashboard dependency group and project package. Run as non-root. Configure database endpoint externally. Health-check page startup.

**Verify**: build, import, startup, health request pass.

## Test Plan

- Streamlit AppTest for three metrics and filters.
- Query unit tests using fake cursor/pool only for error behavior.
- PostgreSQL fixture agreement test against Plan 001.
- Container import/start smoke.

## Done Criteria

- [ ] Three required metrics display correct fixture values.
- [ ] Month selection works.
- [ ] Outlier policy matches SQL.
- [ ] No embedded credential or raw DB error UI.
- [ ] Image builds and starts non-root.
- [ ] Dashboard tests pass.
- [ ] Placeholder features removed.

## STOP Conditions

- Plan 001 SQL outputs are unstable.
- Plan 002 fixture is unavailable.
- Correct page requires changing warehouse formulas.
- Streamlit native chart lacks an explicit assignment-required capability.

## Maintenance Notes

Add maps/explorer only after measured user need. Reviewer should compare dashboard values directly with SQL fixture output.
