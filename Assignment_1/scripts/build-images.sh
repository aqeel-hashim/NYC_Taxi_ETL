#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/lib/logging.sh"

OFFLINE=false
LOAD=auto
TAG="${TAG:-latest}"

usage() {
  cat <<'EOF'
Usage: ./scripts/build-images.sh [--offline] [--load|--no-load] [--tag TAG] [--help]

Builds taxi-airflow, taxi-dashboard, and taxi-alert-receiver. Loads into the
nyc-taxi-etl kind cluster when present unless --no-load is used.
EOF
}

while (($#)); do
  case "$1" in
    --offline) OFFLINE=true; shift ;;
    --load) LOAD=true; shift ;;
    --no-load) LOAD=false; shift ;;
    --tag) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; TAG="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

command -v docker >/dev/null 2>&1 || { log_error "Docker is required"; exit 1; }
docker info >/dev/null 2>&1 || { log_error "Docker daemon is not reachable"; exit 1; }

if [[ "${LOAD}" == auto ]]; then
  LOAD=false
  if command -v kind >/dev/null 2>&1 && kind get clusters 2>/dev/null | grep -Fxq nyc-taxi-etl; then
    LOAD=true
  fi
fi

build_args=(--pull=false)
[[ "${OFFLINE}" == false ]] || build_args+=(--network=none)

images=(
  "taxi-airflow|docker/airflow.Dockerfile"
  "taxi-dashboard|docker/dashboard.Dockerfile"
  "taxi-alert-receiver|docker/alert-receiver.Dockerfile"
)
for entry in "${images[@]}"; do
  name="${entry%%|*}"
  dockerfile="${entry##*|}"
  log_info "Building ${name}:${TAG}"
  docker build "${build_args[@]}" -t "${name}:${TAG}" -f "${ROOT_DIR}/${dockerfile}" "${ROOT_DIR}"
  if [[ "${LOAD}" == true ]]; then
    kind load docker-image "${name}:${TAG}" --name nyc-taxi-etl
  fi
done

log_success "Application images ready"
