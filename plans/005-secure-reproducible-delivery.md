# Plan 005: Secure And Reproduce Setup, Images, CI, Release

> **Executor instructions**: Apply only after Plans 001-004 are green. Never include secret values in commits, logs, plans, or tests. Update index when done.
>
> **Drift check**: `git diff --stat dd3a4b9..HEAD -- Assignment_1/.gitignore Assignment_1/pyproject.toml Assignment_1/uv.lock Assignment_1/scripts Assignment_1/infra/local/compose.postgres.yaml Assignment_1/alembic.ini Assignment_1/docker .github/workflows`

## Status

- **State**: DONE (actionlint image pull unavailable locally)
- **Priority**: P1
- **Effort**: L
- **Risk**: MED
- **Depends on**: Plans 001-004
- **Category**: security, dependencies, dx, CI
- **Planned at**: commit `dd3a4b9`, 2026-07-21

## Why This Matters

Repository-known PostgreSQL credential is embedded across Compose, migration, DAG, dashboard; port is not loopback-bound. Tool downloads are unchecked. `uv.lock` is ignored and resolves a different Airflow major than runtime image. CI excludes runtime surfaces; release workflow cannot be reused or publish safely.

## Current State

- Credential locations: `infra/local/compose.postgres.yaml`, `alembic.ini`, DAG, dashboard. Never copy values.
- `scripts/bootstrap-tools.sh:25-95` downloads executable artifacts without checksum/signature verification.
- `.gitignore:9-10` ignores `uv.lock`.
- `uv.lock:242-249` resolves Airflow 3.3.0; current image uses 2.10.5.
- CI uses unfrozen sync and checks only `src tests`.
- Release calls CI without `workflow_call`; build job lacks registry authentication/permission.
- No `.dockerignore`; local Assignment directory measured about 650 MB because ignored environments/caches enter normal context.

## Commands

Run lock, sync, verifier, Compose, image, secret, and context commands from `Assignment_1/`. Run workflow lint from repository root as `Assignment_1/.tools/actionlint .github/workflows/*.yml`.

| Purpose | Command | Expected |
|---------|---------|----------|
| Lock | `uv lock --check` | exit 0 |
| Frozen sync | `uv sync --frozen --all-groups` | exit 0 |
| Verify | `./scripts/verify.sh` | all implemented gates pass |
| Compose | `docker compose -f infra/local/compose.postgres.yaml config --quiet` | exit 0 |
| Images | `docker build -f docker/airflow.Dockerfile -t nyc-taxi-airflow:test . && docker build -f docker/dashboard.Dockerfile -t nyc-taxi-dashboard:test .` | both succeed |
| Secret scan | `uv run detect-secrets-hook $(git ls-files -- Assignment_1 .github)` from repository root | exit 0 |
| Workflow lint | `Assignment_1/.tools/actionlint .github/workflows/*.yml` from repository root | exit 0 |
| Context bound | `./scripts/check-docker-context.sh` | exit 0; reports less than 5,000,000 bytes |

## Scope

**In scope**:
- `Assignment_1/.gitignore`
- `Assignment_1/.dockerignore` (create)
- `Assignment_1/uv.lock`
- `Assignment_1/pyproject.toml`
- `Assignment_1/.env.example`
- `Assignment_1/infra/local/compose.postgres.yaml`
- `Assignment_1/alembic.ini`, `alembic/env.py`
- `Assignment_1/alembic/versions/0002_roles_and_views.py` (create)
- `Assignment_1/tests/integration/test_database_roles.py` (create)
- `Assignment_1/tests/unit/test_verify_script.py` (create)
- `Assignment_1/.secrets.baseline` (create)
- `Assignment_1/scripts/bootstrap-tools.sh`, `scripts/verify.sh`, `scripts/check-docker-context.sh` (create)
- `Assignment_1/docker/*.Dockerfile`
- `.github/workflows/assignment-1-ci.yml`
- `.github/workflows/assignment-1-release.yml`
- Runtime config files from Plans 003-004 only for secret injection

**Out of scope**:
- Kubernetes/OIDC implementation, AWS Terraform, Assignment 2.
- Changing ETL formulas or fact/dimension shape. Security roles and approved views are in scope.
- Publishing images/releases during implementation without operator approval.

## Git Workflow

- Use `feature/a1-secure-delivery` if requested.
- Do not commit/push/publish without instruction.
- Suggested commit: `ci(a1): lock and secure delivery gates`.

## Steps

### Step 1: Rotate And Externalize Credentials

Treat all committed credentials as burned. Replace literals with environment references documented in `.env.example`; local values live only in ignored `.env`, and CI values use GitHub environment secrets. Compose binds PostgreSQL to `127.0.0.1`. Create separate migrator, loader, dashboard read-only roles and approved analytics views in `0002_roles_and_views.py`; dashboard gets views only. Integration tests prove grants.

Do not print or record replacement values.

External rotation is an operator deployment precondition, not an implementation blocker. Disable publication until the operator attests rotation; repository completion requires only literal removal, secret-reference wiring, and passing scans.

**Verify**: using Plan 001 disposable PostgreSQL, `TEST_DATABASE_URL=... .venv/bin/pytest tests/integration/test_database_roles.py -q` passes; secret-scan command above exits 0.

### Step 2: Validate DAG Input

Use one strict calendar-month parser before URL/path construction. Never interpolate untrusted config into shell source. Prefer argument arrays or Python HTTP client only if curl requirement remains satisfied elsewhere.

**Verify**: valid month works; malformed/path/shell-like inputs reject before task creation.

### Step 3: Track One Frozen Dependency Lock

Remove `uv.lock` ignore; commit lock. Align versions chosen in Plan 003. Replace broad runtime installs with frozen group installs/exports. Remove unused dependencies after import search and runtime tests.

Add `detect-secrets` to the dev group. Commit reviewed `.secrets.baseline`; it stores fingerprints and locations, never values.

**Verify**: clean environment `uv sync --frozen --all-groups`; lock unchanged afterward.

### Step 4: Verify Tool Downloads

Separate binary and archive installers. Pin version, URL, published checksum/signature per OS/architecture. Download temporary, verify, then atomically install. Gum archive must be extracted before executable check.

Add `actionlint` to the checksum-verified tool manifest so workflow lint is reproducible.

**Verify**: valid checksum installs; altered fixture checksum fails before chmod/extract.

### Step 5: Make Verifier Authoritative

`scripts/verify.sh` owns:

- Ruff format/lint.
- mypy including implemented runtime paths.
- unit/integration/DAG/dashboard tests.
- SQLFluff and required SQL execution.
- Bash syntax plus ShellCheck when installed.
- Compose config.
- Docker image build/import/start smoke.
- Alembic/schema drift.

Setup and CI invoke verifier instead of duplicating subsets.

`tests/unit/test_verify_script.py` runs the verifier against temporary PATH command stubs. For each owned gate, make exactly that stub fail and assert verifier exits nonzero; with all stubs passing, assert exit 0. This tests gate propagation without modifying the worktree.

**Verify**: `.venv/bin/pytest tests/unit/test_verify_script.py -q` and `./scripts/verify.sh` both pass.

### Step 6: Repair CI

Use frozen sync. Add `workflow_call`. CI service applies migration and fixture, executes verifier. Cache only by lock digest. Runtime paths must not be omitted from mypy/tests.

**Verify**: from repository root, `Assignment_1/.tools/actionlint .github/workflows/*.yml` exits 0; pull-request job runs without publishing.

### Step 7: Repair Or Disable Release Publication

Until every retained image builds, set `push: false` or disable release workflow. When enabling: authenticate GHCR, grant package write to build job only, publish immutable digest tags, no secrets in logs. Remove alert-receiver matrix entry unless implementation exists.

**Verify**: dry-run builds all images; no registry push. Operator separately approves first publication.

### Step 8: Add Docker Context And Runtime Hardening

Create `.dockerignore`. Exclude `.venv`, caches, local data, `.env`, graph DB, Git metadata. `scripts/check-docker-context.sh` runs `tar --exclude-from=.dockerignore -czf - . | wc -c`, prints bytes, and fails at 5,000,000 or above. Run application images as fixed non-root UID; declare only needed writable paths. Retain Airflow and dashboard images only; alert receiver remains absent until implemented.

**Verify**: context-bound command above prints less than 5,000,000; `docker run --rm --entrypoint id <image> -u` prints nonzero UID; import/start checks pass.

## Test Plan

- Credential absence and role privilege integration tests.
- Month input rejection tests.
- Checksum installer tests with local fixtures.
- Frozen lock drift gate.
- CI workflow validation.
- Image build/start/non-root tests.

## Done Criteria

- [ ] No tracked active credential literals.
- [ ] PostgreSQL bound to loopback locally; roles separated.
- [ ] `uv.lock` tracked; frozen all-group sync passes.
- [ ] Airflow version identical across lock/image/tests.
- [ ] Tool downloads verify integrity before execution.
- [ ] One verifier catches every implemented surface.
- [ ] CI invokes verifier and passes.
- [ ] Release workflow cannot publish without explicit authenticated gate.
- [ ] Images build from bounded context and run non-root.

## STOP Conditions

- Credential rotation requires exposing a value to repository or logs.
- No official checksum/signature exists for a required tool.
- Frozen dependency resolution cannot satisfy chosen Airflow/provider/Python versions.
- Fix requires enabling cloud publication or changing protected GitHub settings without operator approval.

## Maintenance Notes

Every dependency/tool update must refresh lock/checksum and rerun full verifier. Reviewer should inspect workflow permissions, secret boundaries, image users, and whether release remained non-publishing during implementation.

Local actionlint validation could not run because the public Docker Registry reset the actionlint layer download twice. `check-yaml` and all local delivery gates passed; rerun actionlint when registry access is stable.
