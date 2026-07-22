# Plan 001: Make Warehouse Contract Executable And Verified

> **Executor instructions**: Follow steps exactly. Run each gate before continuing. If a STOP condition occurs, report; do not improvise. Update `plans/README.md` when done.
>
> **Drift check**: `git diff --stat dd3a4b9..HEAD -- Assignment_1/alembic Assignment_1/sql Assignment_1/tests/integration Assignment_1/scripts/verify.sh`
> Compare live code with current-state excerpts below. Stop on material drift.

## Status

- **State**: PASS
- **Priority**: P1
- **Effort**: M
- **Risk**: HIGH
- **Depends on**: none
- **Category**: bug, migration, tests
- **Planned at**: commit `dd3a4b9`, 2026-07-21

## Why This Matters

Clean migration succeeds, but no fact partition accepts data. Mandatory revenue SQL references a nonexistent column. Peak-hour SQL groups minute labels, not hours. Current CI never executes required SQL. This plan creates first trustworthy database boundary.

## Current State

- `Assignment_1/alembic/versions/0001_initial_star_schema.py:95-163` creates partitioned parents without child partitions.
- `Assignment_1/alembic/versions/0001_initial_star_schema.py:97-132` has no source-row uniqueness or dimension foreign keys.
- `Assignment_1/sql/queries/revenue_by_payment_type.sql:5` selects nonexistent `p.payment_type_key`.
- `Assignment_1/sql/queries/peak_ride_hours.sql:5-11` groups minute-specific `hour_label`.
- Local clean-DB evidence:

```text
FAIL query revenue_by_payment_type.sql | column p.payment_type_key does not exist
FAIL fact insert | no partition of relation "fact_taxi_trips" found for row
```

- Fixture evidence: two trips at 01:00 and 01:01 produce two hour-1 rows; expected one row with count 2.
- Migration source is Alembic; `sql/schema.sql` is generated offline SQL. Preserve this direction for this plan.

## Commands

Run from `Assignment_1/`.

| Purpose | Command | Expected |
|---------|---------|----------|
| Unit tests | `.venv/bin/pytest tests/unit -q` | 48+ pass |
| SQL lint | `.venv/bin/sqlfluff lint sql/queries --dialect postgres` | `All Finished!` |
| Migration | `DATABASE_URL="$TEST_DATABASE_URL" .venv/bin/alembic upgrade head` | exit 0 on empty DB |
| Offline schema | `DATABASE_URL="$TEST_DATABASE_URL" .venv/bin/alembic upgrade head --sql > /tmp/schema.sql` | exit 0 |
| Static | `.venv/bin/ruff check . && .venv/bin/mypy src tests` | exit 0 |

Disposable PostgreSQL harness for every integration gate:

```bash
export TEST_DB_PASSWORD="$(openssl rand -hex 16)"
docker rm -f a1-test-postgres >/dev/null 2>&1 || true
docker run --rm -d --name a1-test-postgres \
  -e POSTGRES_DB=taxi_warehouse -e POSTGRES_USER=taxi_app \
  -e POSTGRES_PASSWORD="$TEST_DB_PASSWORD" -p 127.0.0.1:55432:5432 \
  pgvector/pgvector:pg17
export TEST_DATABASE_URL="postgresql+psycopg://taxi_app:${TEST_DB_PASSWORD}@127.0.0.1:55432/taxi_warehouse"
for i in $(seq 1 60); do docker exec a1-test-postgres pg_isready -U taxi_app -d taxi_warehouse && break; sleep 1; done
DATABASE_URL="$TEST_DATABASE_URL" .venv/bin/alembic upgrade head
.venv/bin/pytest tests/integration/test_warehouse_contract.py -q
docker rm -f a1-test-postgres
```

Expected: ready within 60 seconds; pytest passes; cleanup exits 0. Any committed helper adds a cleanup `trap`.

## Scope

**In scope**:
- `Assignment_1/alembic/versions/0001_initial_star_schema.py`
- `Assignment_1/sql/schema.sql`
- `Assignment_1/sql/queries/*.sql`
- `Assignment_1/tests/integration/test_warehouse_contract.py` (create)
- `Assignment_1/scripts/verify.sh`
- `Assignment_1/pyproject.toml` only if a pytest marker/config is required

**Out of scope**:
- Airflow DAGs, dashboard, Kubernetes, AWS.
- Loader implementation; Plan 002 owns it.
- KLL policy changes.
- New migration framework or ORM models.

## Git Workflow

- Use `feature/a1-warehouse-contract` if branching requested.
- Do not commit or push without operator instruction.
- Suggested commit when requested: `fix(a1): enforce warehouse SQL contract`.

## Steps

### Step 1: Add Red PostgreSQL Contract Tests

Create `tests/integration/test_warehouse_contract.py`. Read connection URL from `TEST_DATABASE_URL`; skip with explicit reason only when variable is absent. Tests must run against a fresh database and apply Alembic programmatically.

Add cases:

1. Migration creates exactly 1,440 time rows and Unknown rows.
2. January and February 2023 facts can insert through parent.
3. Duplicate `(pickup_date_key, source_asset_id, source_version, source_row_number)` is rejected.
4. Invalid dimension keys are rejected.
5. All three SQL files execute.
6. Fixture expected values: fare/mile `15.00`; hour 1 count `2`; revenue grouped by payment label.
7. Statistical outlier excluded from financial metrics but included in demand count.

Use psycopg parameterization. Never interpolate test values into SQL strings.

**Verify**: harness above reproduces current failures before fixes and passes after Step 4.

### Step 2: Add Assignment-Month Partitions

Create fact and mart partitions for `2023-01` and `2023-02` in migration. Use exact date-key bounds. Keep names deterministic. Do not add dynamic partition management here; Plan 002 may add it only if needed.

**Verify**: partition insertion tests pass.

### Step 3: Enforce Fact Integrity

Add partition-compatible unique source identity including partition key. Add role-playing foreign keys to date/time/zone plus payment/vendor/rate dimensions. Add supporting indexes only where PostgreSQL does not create them.

Seed required date rows for January-February 2023 plus March 1 boundary, or generate them set-wise in migration. Unknown key `0` remains valid for reference dimensions.

**Verify**: duplicate and orphan tests pass.

### Step 4: Correct Required SQL

- Revenue: select/group actual dimension business key or surrogate key consistently; keep label.
- Peak hours: group by `hour` and daypart only. Derive one hourly label; do not group by minute label.
- Fare/mile: retain ratio-of-sums and outlier exclusion.

**Verify**: golden fixture tests pass with exact values.

### Step 5: Regenerate Schema Snapshot

Generate `sql/schema.sql` from Alembic offline mode exactly as documented. Replace row-by-row time seeding with one set-wise operation if possible, preventing 4,000-line seed expansion.

**Verify**: regenerate again to `/tmp/schema.sql`; `diff -u sql/schema.sql /tmp/schema.sql` has no output.

### Step 6: Add Database Gate To Verifier

Extend `scripts/verify.sh` to run SQLFluff and integration tests when `TEST_DATABASE_URL` exists. In CI, absence must fail; local focused unit mode may skip explicitly.

**Verify**: with Plan 001 harness still running, `TEST_DATABASE_URL="$TEST_DATABASE_URL" ./scripts/verify.sh` exits 0.

## Test Plan

- Model style after `tests/unit/transform/test_trips.py`: deterministic fixtures, exact assertions.
- No network calls.
- Fresh database per CI job.
- Assert failure classes, not complete engine error strings.

## Done Criteria

- [ ] Fresh migration passes.
- [ ] Parent fact/mart inserts work for both assignment months.
- [ ] Duplicate source row and orphan key tests fail correctly.
- [ ] Three required SQL files execute and match golden results.
- [ ] Peak query returns one row per hour.
- [ ] `sql/schema.sql` matches regenerated output.
- [ ] Unit, integration, Ruff, mypy, SQLFluff pass.
- [ ] Only in-scope files plus `plans/README.md` changed.

## STOP Conditions

- PostgreSQL partition rules prevent planned uniqueness/FKs without changing fact identity.
- Existing schema differs materially from excerpts.
- Fix requires Airflow or loader changes.
- Migration cannot remain reversible without deleting unrelated schemas/extensions.

## Maintenance Notes

Plan 002 must use these constraints rather than bypassing them. Future months need dynamic partition creation before load. Review query grain whenever `dim_time.hour_label` changes.
