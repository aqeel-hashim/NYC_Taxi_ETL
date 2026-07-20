#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/logging.sh"

PURGE="${PURGE:-none}"

log_warn "Tearing down local platform..."

if [[ "${PURGE}" == "all" ]]; then
    echo "This will delete ALL data including MinIO, PostgreSQL volumes, caches."
    read -r -p "Type 'DELETE' to confirm: " confirm
    [[ "${confirm}" == "DELETE" ]] || exit 0
    docker compose -f "${SCRIPT_DIR}/../infra/local/compose.postgres.yaml" down -v
    rm -rf "${SCRIPT_DIR}/.venv" "${SCRIPT_DIR}/.tools" "${SCRIPT_DIR}/minio-data"
    log_info "Full purge complete"
elif [[ "${PURGE}" == "cache" ]]; then
    rm -rf "${SCRIPT_DIR}/.tools/cache" "${SCRIPT_DIR}/.pytest_cache"
    log_info "Cache purge complete"
else
    docker compose -f "${SCRIPT_DIR}/../infra/local/compose.postgres.yaml" down
    log_info "Services stopped (data preserved)"
fi
