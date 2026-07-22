#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/lib/logging.sh"

cd "${ROOT_DIR}"

VERIFY_DB_CONTAINER=""
cleanup() {
  if [[ -n "${VERIFY_DB_CONTAINER}" ]]; then
    docker rm -f "${VERIFY_DB_CONTAINER}" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

log_info "Running verification..."
uv lock --check || { log_error "Dependency lock is stale"; exit 1; }
uv sync --frozen --all-groups || { log_error "Frozen dependency sync failed"; exit 1; }
uv run ruff check . || { log_error "Ruff checks failed"; exit 1; }
uv run ruff format --check . || { log_error "Ruff format failed"; exit 1; }
uv run mypy src airflow dashboard alert_receiver tests || { log_error "mypy checks failed"; exit 1; }

if [[ -z "${TEST_DATABASE_URL:-}" ]]; then
  case "$(uname -m)" in
    x86_64) postgres_digest="sha256:815bf5378222044da3b34d98e6a5fdac37b15c428b67d09c7c2d90a038e597bf" ;;
    aarch64|arm64) postgres_digest="sha256:555f6d1b6373d0f50ab7eb83062f0a7214ca17b9e5885fb60aaceeb082d58cb5" ;;
    *) log_error "Unsupported architecture for the PostgreSQL verification container"; exit 1 ;;
  esac
  VERIFY_DB_CONTAINER="a1-verify-postgres-${$}"
  verify_password="a1-verify-${RANDOM}-${RANDOM}"
  docker run --detach --rm --name "${VERIFY_DB_CONTAINER}" \
    --env POSTGRES_DB=taxi_warehouse \
    --env POSTGRES_USER=taxi_app \
    --env "POSTGRES_PASSWORD=${verify_password}" \
    --publish 127.0.0.1::5432 \
    "pgvector/pgvector@${postgres_digest}" >/dev/null || {
      log_error "Verification PostgreSQL failed to start"
      exit 1
    }
  verify_port="$(docker port "${VERIFY_DB_CONTAINER}" 5432/tcp | sed 's/.*://')"
  for _ in {1..60}; do
    docker exec "${VERIFY_DB_CONTAINER}" pg_isready -U taxi_app -d taxi_warehouse >/dev/null 2>&1 && break
    sleep 1
  done
  docker exec "${VERIFY_DB_CONTAINER}" pg_isready -U taxi_app -d taxi_warehouse >/dev/null || {
    log_error "Verification PostgreSQL did not become ready"
    exit 1
  }
  TEST_DATABASE_URL="postgresql+psycopg://taxi_app:${verify_password}@127.0.0.1:${verify_port}/taxi_warehouse"
  export TEST_DATABASE_URL
fi

DATABASE_URL="${TEST_DATABASE_URL}" uv run alembic upgrade head
uv run coverage erase
uv run pytest tests --cov=nyc_taxi_etl --cov-branch --cov-report= || {
  log_error "Tests failed"
  exit 1
}
uv run coverage report --fail-under=85 || { log_error "Aggregate coverage failed"; exit 1; }
for shell_test in tests/shell/test-*.sh; do
  [[ -e "${shell_test}" ]] || continue
  bash "${shell_test}" || { log_error "Shell test failed: ${shell_test}"; exit 1; }
done
uv run sqlfluff lint sql/queries --dialect postgres || { log_error "SQL lint failed"; exit 1; }
POSTGRES_PASSWORD=verify-only MINIO_SECRET_KEY=verify-only \
  docker compose -f infra/local/compose.postgres.yaml config --quiet || {
  log_error "Compose config failed"
  exit 1
}
./scripts/check-docker-context.sh >/dev/null || { log_error "Docker context too large"; exit 1; }

while IFS= read -r -d '' shell_file; do
  bash -n "${ROOT_DIR}/../${shell_file}" || { log_error "Bash syntax failed: ${shell_file}"; exit 1; }
done < <(git -C "${ROOT_DIR}/.." ls-files -z 'Assignment_1/*.sh' 'Assignment_1/**/*.sh')
bash -n "${BASH_SOURCE[0]}"

if [[ "${VERIFY_IMAGES:-true}" == true ]]; then
  for image in airflow dashboard alert-receiver; do
    docker build --file "docker/${image}.Dockerfile" --tag "nyc-taxi-${image}:verify" . || {
      log_error "${image} image build failed"
      exit 1
    }
  done
fi

log_success "All verifications passed"
