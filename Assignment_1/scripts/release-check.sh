#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/lib/logging.sh"
export COMPOSE_PROJECT_NAME="nyc-taxi-a1-release-${$}"

cleanup() {
  docker compose --project-name "${COMPOSE_PROJECT_NAME}" --env-file "${ROOT_DIR}/.env" \
    -f "${ROOT_DIR}/infra/local/compose.postgres.yaml" down --volumes --remove-orphans >/dev/null 2>&1 || true
}
trap cleanup EXIT

VERIFY_IMAGES=false "${ROOT_DIR}/scripts/verify.sh"
bash "${ROOT_DIR}/setup.sh" --local-demo --no-dashboard
log_success "Release validation passed"
