#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# sourcing logging helpers
source "${SCRIPT_DIR}/scripts/lib/logging.sh"

PROFILE="${PROFILE:-auto}"
TOOLS="${TOOLS:-core}"
START_STAGE="${START_STAGE:-preflight}"
NON_INTERACTIVE="${NON_INTERACTIVE:-false}"
OFFLINE="${OFFLINE:-false}"

log_info "NYC Taxi ETL Setup"
log_info "Profile: ${PROFILE}"
log_info "Project: ${REPO_ROOT}"

usage() {
    echo "Usage: ./setup.sh [--profile auto|staged|concurrent] [--from STAGE|--only STAGE] [--non-interactive]"
    echo "Stages: preflight, tools, python_env, database, data, verify"
}

ONLY_STAGE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --profile) PROFILE="${2:-}"; shift 2 ;;
        --from) START_STAGE="${2:-}"; shift 2 ;;
        --only) ONLY_STAGE="${2:-}"; START_STAGE="${ONLY_STAGE}"; shift 2 ;;
        --non-interactive) NON_INTERACTIVE="true"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
done

# docker and curl validation. and also system mem check for staged vs full execution
preflight() {
    log_info "=== Preflight ==="
    command -v docker >/dev/null 2>&1 || { log_error "Docker required"; exit 1; }
    command -v curl >/dev/null 2>&1 || { log_error "curl required"; exit 1; }
    command -v uv >/dev/null 2>&1 || [[ -x .tools/uv ]] || { log_error "uv required"; exit 1; }

    local cpu mem
    cpu=$(docker info --format '{{.NCPU}}' 2>/dev/null || echo 0)
    mem_bytes=$(docker info --format '{{.MemTotal}}' 2>/dev/null || echo 0)
    mem_gib=$((mem_bytes / 1073741824))

    log_info "Docker: ${cpu} CPUs, ${mem_gib} GiB RAM"
    log_info "Disk: $(df -h . | tail -1 | awk '{print $4}') free"

    if [[ "${PROFILE}" == "auto" ]]; then
        if [[ $cpu -ge 4 && $mem_gib -ge 8 ]]; then
            PROFILE="concurrent"
        else
            PROFILE="staged"
        fi
    fi
    log_info "Selected profile: ${PROFILE}"

    if ! docker info >/dev/null 2>&1; then
        log_error "Docker daemon not running"
        exit 1
    fi
}

# uv tooling and other tooling bootstrap for use
tools() {
    log_info "=== Tools ==="
    if [[ ! -x .tools/uv ]] && ! command -v uv >/dev/null 2>&1; then
        log_error "uv not found. Install: curl -LsSf https://astral.sh/uv/install.sh | sh"
        exit 1
    fi
    "${SCRIPT_DIR}/bootstrap-tools.sh"
}

python_env() {
    log_info "=== Python Environment ==="
    uv python install 3.12 2>/dev/null || true
    uv sync --group dev
    uv run pre-commit install
    log_success "Python environment ready"
}

# pg setup, compose
database() {
    log_info "=== Database ==="
    if [[ -f "${SCRIPT_DIR}/.env" ]]; then
        set -a
        source "${SCRIPT_DIR}/.env"
        set +a
    fi
    docker compose -f "${SCRIPT_DIR}/../infra/local/compose.postgres.yaml" up -d --wait
    until docker compose -f "${SCRIPT_DIR}/../infra/local/compose.postgres.yaml" exec -T postgres pg_isready -U taxi_app -d taxi_warehouse 2>/dev/null; do
        sleep 1
    done
    DATABASE_URL="${DATABASE_URL:?DATABASE_URL must be set in .env or environment}" uv run alembic upgrade head
    log_success "Database ready"
}

data() {
    log_info "=== Source Data ==="
    "${SCRIPT_DIR}/scripts/download-sources.sh"
    log_success "January and February 2023 data downloaded"
}

verify() {
    log_info "=== Verify ==="
    uv run pytest -q
    .venv/bin/ruff check .
    .venv/bin/mypy src tests --no-error-summary
    log_success "All checks pass"
}

main() {
    local stages=("preflight" "tools" "python_env" "database" "data" "verify")
    [[ " ${stages[*]} " == *" ${START_STAGE} "* ]] || {
        usage >&2
        exit 2
    }
    local started=false
    for stage in "${stages[@]}"; do
        if [[ "${stage}" == "${START_STAGE}" ]]; then
            started=true
        fi
        if $started; then
            $stage
            [[ -z "${ONLY_STAGE}" ]] || break
        fi
    done
    log_success "Setup complete"
    echo ""
    log_info "Database: postgresql://localhost:5432/taxi_warehouse"
    log_info "Run ETL: ./scripts/run-pipeline.sh"
}

main "$@"
