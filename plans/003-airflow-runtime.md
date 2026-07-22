# Plan 003: Make Airflow Orchestration And Runtime Image Executable

> **Executor instructions**: Wrap Plan 002 service; do not rewrite ETL inside DAGs. Run DAG import and task execution gates. Update index when done.
>
> **Drift check**: `git diff --stat dd3a4b9..HEAD -- Assignment_1/airflow Assignment_1/docker/airflow.Dockerfile Assignment_1/pyproject.toml`

## Status

- **State**: PARTIAL (DAGs import and fixture run passes; full task graph and K8s pending)
- **Priority**: P1
- **Effort**: L
- **Risk**: HIGH
- **Depends on**: `plans/002-local-etl-vertical-slice.md`
- **Category**: bug, tests, architecture
- **Planned at**: commit `dd3a4b9`, 2026-07-21

## Why This Matters

Three DAGs import, but calibration task execution fails before its body with `AttributeError: Can't get local object ... calibrate`. Monthly DAG shares task-local `/data`, never loads facts, and may log completion before load. Custom Airflow image does not build. Airflow requirement remains unmet until one fixture DAG run succeeds.

## Current State

- `taxi_monthly_etl.py:40-74` uses runtime-created virtualenvs and outer-scope globals.
- `taxi_monthly_etl.py:63-74` only inserts running metadata.
- `taxi_monthly_etl.py:92-97` completion metrics do not depend on load success.
- `taxi_quality_calibration.py:39-54` uses empty sketches and print-only activation.
- `docker/airflow.Dockerfile` omits package README/lock; local build fails metadata generation.
- DAG import gate found exactly three DAGs and no import errors.
- DAG execution gate failed before task body, then waited through five-minute retries.

## Commands

| Purpose | Command | Expected |
|---------|---------|----------|
| Image build | `docker build -f docker/airflow.Dockerfile -t nyc-taxi-airflow:test .` | success |
| Import/list | container command below | no import errors; three project DAGs |
| Fixture DAG | container command below | success |
| Failure DAG | same container shape, failure DAG ID | expected failed task plus callback evidence |

```bash
docker run --rm --network host --entrypoint bash -v "$PWD/tests/fixtures:/opt/airflow/tests/fixtures:ro" \
  -e AIRFLOW__DATABASE__SQL_ALCHEMY_CONN=sqlite:////tmp/airflow.db nyc-taxi-airflow:test -c \
  'airflow db migrate >/dev/null && airflow dags list-import-errors && airflow dags list --output plain'
docker run --rm --network host --entrypoint bash -v "$PWD/tests/fixtures:/opt/airflow/tests/fixtures:ro" \
  -e AIRFLOW__DATABASE__SQL_ALCHEMY_CONN=sqlite:////tmp/airflow.db -e NYC_TAXI_FIXTURE_MODE=true \
  -e DATABASE_URL="$TEST_DATABASE_URL" \
  nyc-taxi-airflow:test -c \
  'airflow db migrate >/dev/null && airflow dags test taxi_monthly_etl 2023-01-05'
```

Expected: after Plan 001 harness is migrated, commands run without host Airflow or public network; list contains exactly three project DAG IDs; fixture DAG publishes to disposable PostgreSQL. Failure-drill uses the same command shape and must exit nonzero after callback assertion.

Failure-drill contract and command:

```bash
evidence_dir="$(mktemp -d)" && chmod 777 "$evidence_dir"
! docker run --rm --network host --entrypoint bash -v "$evidence_dir:/evidence" \
  -e AIRFLOW__DATABASE__SQL_ALCHEMY_CONN=sqlite:////tmp/airflow.db \
  -e ALERT_EVIDENCE_PATH=/evidence/callback.json nyc-taxi-airflow:test -c \
  'airflow db migrate >/dev/null && airflow dags test taxi_failure_drill 2023-01-05'
python -c 'import json,sys; d=json.load(open(sys.argv[1])); assert all(d.get(k) for k in ("dag_id","run_id","task_id"))' \
  "$evidence_dir/callback.json"
rm -rf "$evidence_dir"
```

`taxi_failure_drill` has one deterministic task that raises after startup. Its failure callback atomically writes the three non-secret identifiers above when `ALERT_EVIDENCE_PATH` is set; normal runtime uses the configured alert sink.

## Scope

**In scope**:
- `Assignment_1/airflow/dags/*.py`
- `Assignment_1/docker/airflow.Dockerfile`
- `Assignment_1/tests/dags/` (create)
- `Assignment_1/pyproject.toml` Airflow group/version
- `Assignment_1/uv.lock`
- `Assignment_1/.dockerignore` (create)

**Out of scope**:
- KubernetesExecutor deployment/Helm values.
- Dashboard, alert receiver, KLL algorithm redesign.
- Loader internals from Plan 002.

## Git Workflow

- Use `feature/a1-airflow-runtime` if requested.
- Do not commit/push without instruction.
- Suggested commit: `feat(a1): execute fixture ETL through Airflow`.

## Steps

### Step 1: Choose One Airflow Version

Align image, pyproject, providers, lock, and tests to one supported release. Current lock resolves Airflow 3.3.0 while image uses 2.10.5. Verify provider compatibility from official constraints. Record choice in README.

**Verify**: frozen Airflow group sync succeeds; `airflow version` equals image version.

### Step 2: Build Reproducible Image

Copy `README.md`, package source, DAGs, and frozen dependency artifacts. Install from lock/export, not broad shell requirements. Quote all requirement strings. Add `.dockerignore` excluding `.venv`, caches, data, secrets, graph DB.

**Verify**: image builds from normal context; package import and DAG list work inside image.

### Step 3: Remove Per-Task Virtualenv Resolution

Use standard task execution in immutable image. Move task callables to importable top-level package modules where needed. Every callable imports its own direct dependencies. Do not pass full Airflow context into isolated subprocesses.

**Verify**: fixture task executes immediately without pickling or package-install errors.

### Step 4: Make Monthly DAG Thin And Correct

- Validate manual `source_month`; derive scheduled month from data interval.
- Call Plan 002 pipeline service.
- Pass paths/manifests/counts only.
- Set explicit dependency: download -> validate/transform/load/publish -> completion.
- Update one unique run record through running/succeeded/failed.
- Keep retries for transient failures only; deterministic fixture failures get zero retries.

**Verify**: DAG topology tests and fixture DAG test pass.

### Step 5: Make Failure Drill Prove Callback

Use fixture and selected fail point; never touch published partition. Add failure callback producing structured sanitized event. Test callback invocation and run-state update. External Mailpit/webhook proof remains deferred until infrastructure exists.

**Verify**: failure test exits as expected; callback evidence contains DAG/run/task IDs, no credential or row payload.

### Step 6: Quarantine Calibration Stub

Until real calibration is implemented, make DAG fail fast with explicit `NotImplementedError` or disable it from acceptance. Never print success from empty sketches. Do not mark Phase 3/6 complete based on this DAG.

**Verify**: calibration cannot report successful activation without persisted nonempty artifact.

## Test Plan

- DAG import and exact task dependency tests.
- Schedule/data-interval/month override tests.
- Fixture DAG execution in image.
- Failure callback sanitization.
- Image package import smoke.

## Done Criteria

- [ ] Image builds reproducibly from tracked lock.
- [ ] Three DAGs import; monthly fixture DAG succeeds.
- [ ] Monthly DAG publishes data through Plan 002 service.
- [ ] Completion waits for publication.
- [ ] Failure callback tested.
- [ ] Calibration cannot falsely succeed.
- [ ] No runtime dependency installation inside tasks.

## STOP Conditions

- No supported Airflow/provider version satisfies Python 3.12 and chosen executor.
- Plan 002 service is not callable without shell orchestration.
- DAG execution requires Kubernetes to test basic fixture semantics.
- Airflow version migration changes authentication/database scope outside this plan.

## Maintenance Notes

KubernetesExecutor comes later. First preserve identical DAG behavior under local test execution. Reviewer should reject business logic added directly to DAG files.
