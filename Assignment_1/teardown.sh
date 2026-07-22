#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PATH="${ROOT_DIR}/.tools/bin:${PATH}"
source "${ROOT_DIR}/scripts/lib/logging.sh"

CLUSTER_NAME="${CLUSTER_NAME:-nyc-taxi-etl}"
PURGE=none
YES=false
NON_INTERACTIVE=false
LOCAL_ONLY=false

usage() {
  cat <<'EOF'
Usage: ./teardown.sh [--local] [--purge-cache|--purge-all] [--yes] [--non-interactive] [--help]

Default: stop recorded helper processes and delete kind cluster only.
  --purge-cache     Also delete .cache, tool download cache, source data, test caches
  --purge-all       Also delete repo-local tools, venv, secrets, TLS, MinIO host data
  --local           Stop the local Compose demo; preserve PostgreSQL data
  --yes             Confirm requested purge without prompt
  --non-interactive Fail a purge unless --yes is supplied
  -h, --help        Show this help
EOF
}

while (($#)); do
  case "$1" in
    --purge-cache) [[ "${PURGE}" == none ]] || { usage >&2; exit 2; }; PURGE=cache; shift ;;
    --purge-all) [[ "${PURGE}" == none ]] || { usage >&2; exit 2; }; PURGE=all; shift ;;
    --yes) YES=true; shift ;;
    --non-interactive) NON_INTERACTIVE=true; shift ;;
    --local) LOCAL_ONLY=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) log_error "Unknown option: $1"; usage >&2; exit 2 ;;
  esac
done

if [[ "${LOCAL_ONLY}" == true ]]; then
  [[ "${PURGE}" == none ]] || { log_error "--local cannot be combined with purge flags"; exit 2; }
  docker compose --project-name nyc-taxi-a1 --env-file "${ROOT_DIR}/.env" \
    -f "${ROOT_DIR}/infra/local/compose.postgres.yaml" down --remove-orphans
  log_success "Local demo stopped; PostgreSQL volume preserved"
  exit 0
fi

safe_remove() {
  local path="$1"
  [[ "${path}" == "${ROOT_DIR}/"* && "${path}" != "${ROOT_DIR}/" ]] || {
    log_error "Refusing unsafe delete path: ${path}"
    exit 1
  }
  rm -rf -- "${path}"
}

confirm_purge() {
  local phrase="$1"
  [[ "${YES}" == true ]] && return 0
  [[ "${NON_INTERACTIVE}" == false ]] || {
    log_error "Purge needs --yes in non-interactive mode"
    return 1
  }
  local answer
  read -r -p "Type '${phrase}' to continue: " answer
  [[ "${answer}" == "${phrase}" ]] || { log_warn "Purge cancelled"; return 1; }
}

stop_helpers() {
  local pid_file pid
  [[ -d "${ROOT_DIR}/.local/run" ]] || return 0
  for pid_file in "${ROOT_DIR}/.local/run/"*.pid; do
    [[ -f "${pid_file}" ]] || continue
    pid="$(<"${pid_file}")"
    if [[ "${pid}" =~ ^[0-9]+$ ]] && kill -0 "${pid}" 2>/dev/null &&
      tr '\0' ' ' <"/proc/${pid}/cmdline" 2>/dev/null | grep -Fq "${ROOT_DIR}"; then
      kill "${pid}"
    fi
    rm -f -- "${pid_file}"
  done
}

if [[ "${PURGE}" == cache ]]; then
  log_warn "Will delete: ${ROOT_DIR}/.cache ${ROOT_DIR}/.tools/cache ${ROOT_DIR}/data and test caches"
  confirm_purge "PURGE CACHE" || exit 3
elif [[ "${PURGE}" == all ]]; then
  log_warn "Will delete: tools, venv, caches, source data, .env, TLS, generated config, MinIO host data"
  log_warn "Cloud resources are never touched"
  confirm_purge "PURGE ALL" || exit 3
fi

stop_helpers
if command -v kind >/dev/null 2>&1 && kind get clusters 2>/dev/null | grep -Fxq "${CLUSTER_NAME}"; then
  kind delete cluster --name "${CLUSTER_NAME}"
else
  log_info "kind cluster absent"
fi

if [[ "${PURGE}" == cache ]]; then
  for path in .cache .tools/cache data .pytest_cache .ruff_cache .mypy_cache htmlcov; do
    safe_remove "${ROOT_DIR}/${path}"
  done
elif [[ "${PURGE}" == all ]]; then
  if command -v docker >/dev/null 2>&1; then
    docker compose --env-file "${ROOT_DIR}/.env.example" \
      -f "${ROOT_DIR}/infra/local/compose.postgres.yaml" down --volumes --remove-orphans || true
  fi
  for path in .tools .venv .cache data .env .local minio-data kubeconfig \
    .pytest_cache .ruff_cache .mypy_cache htmlcov; do
    safe_remove "${ROOT_DIR}/${path}"
  done
fi

log_success "Teardown complete (purge=${PURGE})"
