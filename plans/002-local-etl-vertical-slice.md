# Plan 002: Deliver One Real Local ETL Vertical Slice

> **Executor instructions**: Follow every step and gate. Do not report success until fixture data reaches PostgreSQL and required SQL returns expected values. Update plan index when done.
>
> **Drift check**: `git diff --stat dd3a4b9..HEAD -- Assignment_1/setup.sh Assignment_1/scripts Assignment_1/src Assignment_1/tests Assignment_1/references`

## Status

- **State**: DONE
- **Priority**: P1
- **Effort**: L
- **Risk**: HIGH
- **Depends on**: `plans/001-warehouse-contract.md`
- **Category**: bug, architecture, tests
- **Planned at**: commit `dd3a4b9`, 2026-07-21

## Why This Matters

No executable path loads taxi trips. `run-pipeline.sh` currently raises Python syntax error, then would only import a type. Setup fails before preflight because helper paths are wrong. This plan delivers minimum real flow: acquire one month, validate, transform, load, reconcile, rerun safely.

## Current State

- `setup.sh:8,56,70` points to nonexistent logging/bootstrap/Compose paths.
- `scripts/run-pipeline.sh:19-24` is a stub. Local `2023-01` run fails with `SyntaxError`.
- `src/nyc_taxi_etl/transform/trips.py` returns accepted/rejected/issues frames but no loader exists.
- `airflow/dags/taxi_monthly_etl.py:63-74` writes only a `running` metadata row; Plan 003 owns Airflow.
- Official source pattern: `https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_YYYY-MM.parquet`.
- Required invariant: `source = accepted + rejected`; published accepted rows must not duplicate on rerun.

## Commands

Run from `Assignment_1/`. First start the Plan 001 disposable PostgreSQL harness through its readiness loop, then run:

```bash
DATABASE_URL="$TEST_DATABASE_URL" .venv/bin/alembic upgrade head
DATABASE_URL="$TEST_DATABASE_URL" ./scripts/run-pipeline.sh 2023-01 --fixture
DATABASE_URL="$TEST_DATABASE_URL" ./scripts/run-pipeline.sh 2023-01 --fixture
DATABASE_URL="$TEST_DATABASE_URL" .venv/bin/pytest tests/unit tests/integration -q
```

The implementation establishes `DATABASE_URL` as the single local pipeline connection contract. Cleanup uses Plan 001's container command.

| Purpose | Command | Expected |
|---------|---------|----------|
| Setup smoke | `./setup.sh --only preflight` | exit 0, no mutation beyond checks |
| Fixture pipeline | `DATABASE_URL="$TEST_DATABASE_URL" ./scripts/run-pipeline.sh 2023-01 --fixture` | exit 0; source 6, accepted 4, rejected 2, flagged trips 1, issue rows 2 |
| Real pipeline | `DATABASE_URL="$TEST_DATABASE_URL" ./scripts/run-pipeline.sh 2023-01` | exit 0 after download/load |
| Rerun | same real-pipeline command | same business results, zero duplicates |
| Tests | `.venv/bin/pytest tests/unit tests/integration -q` | all pass |

## Scope

**In scope**:
- `Assignment_1/setup.sh`
- `Assignment_1/teardown.sh`
- `Assignment_1/scripts/run-pipeline.sh`
- `Assignment_1/scripts/lib/logging.sh`
- `Assignment_1/src/nyc_taxi_etl/pipeline.py` (create)
- `Assignment_1/src/nyc_taxi_etl/load/` (create)
- `Assignment_1/src/nyc_taxi_etl/contracts/source.py`
- `Assignment_1/src/nyc_taxi_etl/transform/trips.py` only where required for load contract
- `Assignment_1/tests/integration/test_pipeline.py` (create)
- `Assignment_1/tests/fixtures/` (create)
- `Assignment_1/README.md` command/status section

**Out of scope**:
- Airflow DAG behavior; Plan 003.
- Dashboard; Plan 004.
- Kubernetes, MinIO, KLL recalibration, AWS.
- Statistical-outlier implementation beyond preserving current fields.

## Git Workflow

- Use `feature/a1-local-etl` if requested.
- Do not commit/push without instruction.
- Suggested commit: `feat(a1): load one month end to end`.

## Steps

### Step 1: Repair Entry Point Paths And CLI Parsing

Resolve all files relative to `Assignment_1/`:

- logging: `scripts/lib/logging.sh`
- bootstrap: `scripts/bootstrap-tools.sh`
- Compose: `infra/local/compose.postgres.yaml`

Implement strict parsing for documented `--profile`, `--from`, `--only`, `--non-interactive`, and teardown purge flags. Reject unsupported options. If an option remains unimplemented, remove it from docs and CLI rather than ignoring it.

**Verify**: `./setup.sh --only preflight` exits 0; invalid flag exits nonzero with usage.

### Step 2: Create Deterministic Fixture

Create tiny Parquet fixture containing clean, unknown-reference, multiple-issue, hard-reject, month-boundary, and duplicate-source cases. Store generation code, not a large binary, unless fixture is under repository size policy.

Fixture contract: 6 source rows: two ordinary clean accepted rows; one accepted row with unknown vendor and payment producing one flagged trip and two issue rows; one zero-distance reject; one negative-fare reject; one accepted January 31 pickup with February 1 dropoff inside the allowed boundary. Final counts are accepted 4, rejected 2, flagged trips 1, issue rows 2. Generate twice and require identical SHA-256. Exit codes: success `0`, invalid CLI/month `2`, source/contract/transform failure `3`, database/publication failure `4`.

**Verify**: two generator runs have matching `sha256sum`; fixture contract test asserts exact values above.

### Step 3: Implement Pipeline Service

Create one Python service callable from CLI and later Airflow. Responsibilities:

1. Validate exact `YYYY-MM`.
2. Resolve fixture or official source path.
3. For real mode, invoke shared `curl` downloader through argument array; no shell interpolation.
4. Validate required columns/types before transform.
5. Transform.
6. Load reference dimensions idempotently.
7. Bulk load accepted rows into assignment-month partition using psycopg COPY/staging.
8. Persist run counts and quality summary.
9. Commit atomically; rollback on any invariant failure.
10. Return structured result object and process exit status.

Do not put business logic in shell.

**Verify**: fixture pipeline integration test passes.

### Step 4: Implement Idempotent Load

Map date/time and reference business keys to warehouse surrogate keys. Preserve source asset/version/row identity from Plan 001. On rerun, either replace target month transactionally or conflict-safe insert with explicit reconciliation. Never silently ignore changed source versions.

**Verify**: two identical fixture runs produce same row count/checksum and zero duplicate source identities.

### Step 5: Make `run-pipeline.sh` Thin

Validate arguments, ensure PostgreSQL health, invoke Python module once, propagate its status. Remove inline Python and false success logging.

**Verify**: fixture, invalid month, transform failure, database failure all return expected statuses.

### Step 6: Prove Real January Download

Run official January 2023 source with recorded URL, bytes, SHA-256, schema, source rows, accepted/rejected/flagged rows, elapsed time. Do not run February until January passes.

**Verify**: three required SQL queries execute against published January data.

### Step 7: Update Truthful Documentation

Document only verified commands and current limitations. Mark Kubernetes/AWS/dashboard as pending. Include exact fixture and real-run commands.

**Verify**: every README command executes or is explicitly marked planned.

## Test Plan

- Unit: month parser, source metadata, reconciliation, dimension mapping.
- Integration: fixture load, rollback, rerun, duplicate rejection, query outputs.
- Shell: setup path/argument smoke, pipeline exit propagation.
- Use Plan 001 database fixture pattern.

## Done Criteria

- [ ] Setup preflight works.
- [ ] Fixture pipeline downloads/resolves, validates, transforms, loads, reconciles.
- [ ] January real source loads through same service.
- [ ] Rerun produces no duplicates or metric changes.
- [ ] Failures rollback and return nonzero.
- [ ] Required SQL matches fixture golden values.
- [ ] All checks pass.
- [ ] Docs contain no fake success commands.

## STOP Conditions

- Plan 001 constraints/tests are not green.
- Official schema differs from source contract beyond additive columns.
- Memory exceeds measured Docker/host envelope; stop and report profile/peak.
- Correct idempotency requires changing source identity semantics.

## Maintenance Notes

Plan 003 must call `pipeline.py`; never duplicate transform/load code in DAGs. Future object storage can replace local paths behind a real need, not before.
