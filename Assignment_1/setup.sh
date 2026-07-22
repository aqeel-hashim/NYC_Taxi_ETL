#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PATH="${ROOT_DIR}/.tools/bin:${PATH}"
export UV_CACHE_DIR="${ROOT_DIR}/.tools/cache/uv"
export UV_PYTHON_INSTALL_DIR="${ROOT_DIR}/.tools/python"
source "${ROOT_DIR}/scripts/lib/logging.sh"
source "${ROOT_DIR}/scripts/lib/lifecycle.sh"
source "${ROOT_DIR}/scripts/lib/cache.sh"

PROFILE="${PROFILE:-auto}"
TOOLS="${TOOLS:-core}"
START_STAGE="${START_STAGE:-preflight}"
ONLY_STAGE=""
NON_INTERACTIVE="${NON_INTERACTIVE:-false}"
OFFLINE="${OFFLINE:-false}"
ALLOW_SYNTHETIC_FALLBACK="${ALLOW_SYNTHETIC_FALLBACK:-false}"
FORCE_PROFILE="${FORCE_PROFILE:-false}"
RECREATE_CLUSTER="${RECREATE_CLUSTER:-false}"
LOCAL_DEMO=false
NO_DASHBOARD=false
CURRENT_STAGE=""

usage() {
  cat <<'EOF'
Usage: ./setup.sh [OPTIONS]

Options:
  --profile auto|staged|concurrent  Resource profile (default: auto)
  --tools core|all                  Tool profile (default: core)
  --from STAGE                      Resume at STAGE
  --only STAGE                      Run only STAGE
  --offline                         Forbid network access; require complete cache
  --allow-synthetic-fallback        Use fixture only after verified source failure
  --non-interactive                 Disable prompts and decorative UI
  --force-profile                   Permit unsupported concurrent profile
  --recreate-cluster                Delete partial kind cluster before cluster stage
  --local-demo                      Run distro-neutral PostgreSQL + local Airflow + Streamlit demo
  --no-dashboard                    With --local-demo, validate ETL and exit without Streamlit
  -h, --help                        Show this help

Stages:
  preflight tools python secrets tls cache cluster storage images platform
  applications schema calibration etl presentation acceptance summary
EOF
}

need_value() {
  [[ $# -ge 2 && -n "$2" ]] || {
    log_error "$1 requires a value"
    usage >&2
    exit 2
  }
}

while (($#)); do
  case "$1" in
    --profile) need_value "$@"; PROFILE="$2"; shift 2 ;;
    --tools) need_value "$@"; TOOLS="$2"; shift 2 ;;
    --from) need_value "$@"; START_STAGE="$2"; shift 2 ;;
    --only) need_value "$@"; ONLY_STAGE="$2"; START_STAGE="$2"; shift 2 ;;
    --offline) OFFLINE=true; shift ;;
    --allow-synthetic-fallback) ALLOW_SYNTHETIC_FALLBACK=true; shift ;;
    --non-interactive) NON_INTERACTIVE=true; shift ;;
    --force-profile) FORCE_PROFILE=true; shift ;;
    --recreate-cluster) RECREATE_CLUSTER=true; shift ;;
    --local-demo) LOCAL_DEMO=true; shift ;;
    --no-dashboard) NO_DASHBOARD=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) log_error "Unknown option: $1"; usage >&2; exit 2 ;;
  esac
done

if [[ "${LOCAL_DEMO}" == true ]]; then
  args=()
  [[ "${NO_DASHBOARD}" == false ]] || args+=(--no-dashboard)
  exec "${ROOT_DIR}/scripts/local-demo.sh" "${args[@]}"
fi
[[ "${NO_DASHBOARD}" == false ]] || { log_error "--no-dashboard requires --local-demo"; exit 2; }

lifecycle_validate_profile "${PROFILE}" || { log_error "Invalid profile: ${PROFILE}"; exit 2; }
lifecycle_validate_tools "${TOOLS}" || { log_error "Invalid tools profile: ${TOOLS}"; exit 2; }
lifecycle_validate_stage "${START_STAGE}" || { log_error "Invalid stage: ${START_STAGE}"; exit 2; }

resume_command() {
  local command="./setup.sh --from ${CURRENT_STAGE} --profile ${PROFILE} --tools ${TOOLS}"
  [[ "${OFFLINE}" == true ]] && command+=" --offline"
  [[ "${NON_INTERACTIVE}" == true ]] && command+=" --non-interactive"
  [[ "${ALLOW_SYNTHETIC_FALLBACK}" == true ]] && command+=" --allow-synthetic-fallback"
  printf '%s\n' "${command}"
}

on_error() {
  local status=$?
  [[ -n "${CURRENT_STAGE}" ]] && log_error "Resume: $(resume_command)"
  exit "${status}"
}
trap on_error ERR

preflight() {
  [[ "$(uname -s)" == Linux ]] || lifecycle_die "Only Linux and WSL2 are supported"
  case "$(uname -m)" in
    x86_64|aarch64|arm64) ;;
    *) lifecycle_die "Unsupported architecture: $(uname -m)" ;;
  esac
  command -v docker >/dev/null 2>&1 || lifecycle_die "Docker is required"
  command -v curl >/dev/null 2>&1 || lifecycle_die "curl is required"
  docker info >/dev/null 2>&1 || lifecycle_die "Docker daemon is not reachable"

  local requested_profile="${PROFILE}"
  PROFILE="$(select_resource_profile "${PROFILE}")"
  local cpus memory_bytes disk_kib
  cpus="$(docker_cpu_count)"
  memory_bytes="$(docker_memory_bytes)"
  disk_kib="$(df -Pk "${ROOT_DIR}" | awk 'NR == 2 {print $4}')"
  log_info "Docker resources: ${cpus} CPUs, $((memory_bytes / 1073741824)) GiB RAM"
  log_info "Free disk: $((disk_kib / 1048576)) GiB"
  ((disk_kib >= 41943040)) || lifecycle_die "At least 40 GiB free disk is required"
  [[ -w "${ROOT_DIR}" ]] || lifecycle_die "Project directory is not writable: ${ROOT_DIR}"
  [[ "$(date +%s)" =~ ^[0-9]+$ ]] || lifecycle_die "System clock is unavailable"
  if [[ "${OFFLINE}" == false ]]; then
    curl --fail --silent --show-error --head --max-time 10 \
      https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2023-01.parquet \
      >/dev/null || lifecycle_die "TLC source network check failed"
  fi
  if ! kind_cluster_exists; then
    local port
    for port in 8080 8443; do
      if (exec 3<>"/dev/tcp/127.0.0.1/${port}") 2>/dev/null; then
        lifecycle_die "Required port is in use: 127.0.0.1:${port}"
      fi
    done
  fi
  log_success "Profile: ${PROFILE} (requested ${requested_profile})"
}

tools() {
  local args=(--profile "${TOOLS}")
  [[ "${OFFLINE}" == false ]] || args+=(--offline)
  "${ROOT_DIR}/scripts/bootstrap-tools.sh" "${args[@]}"
  hash -r
}

python() {
  command -v uv >/dev/null 2>&1 || lifecycle_die "uv is unavailable after tools stage"
  if [[ "${OFFLINE}" == true ]]; then
    uv sync --frozen --all-groups --offline
  else
    uv python install 3.12
    uv sync --frozen --all-groups
  fi
  uv run pre-commit install
}

secrets() {
  if [[ -s "${ROOT_DIR}/.env" ]]; then
    lifecycle_die ".env exists but contains placeholders; repair it or remove it explicitly"
  fi
  command -v openssl >/dev/null 2>&1 || lifecycle_die "openssl is required to generate secrets"
  local postgres_password airflow_password minio_password
  postgres_password="$(openssl rand -hex 24)"
  airflow_password="$(openssl rand -hex 24)"
  minio_password="$(openssl rand -hex 24)"
  umask 077
  cat >"${ROOT_DIR}/.env" <<EOF
POSTGRES_DB=taxi_warehouse
POSTGRES_USER=taxi_app
POSTGRES_PASSWORD=${postgres_password}
DATABASE_URL=postgresql+psycopg://taxi_app:${postgres_password}@127.0.0.1:5432/taxi_warehouse
AIRFLOW_DB_NAME=airflow
AIRFLOW_DB_USER=airflow
AIRFLOW_DB_PASSWORD=${airflow_password}
MINIO_ACCESS_KEY=taxi_admin
MINIO_SECRET_KEY=${minio_password}
EOF
}

tls() {
  command -v mkcert >/dev/null 2>&1 || lifecycle_die "mkcert is unavailable after tools stage"
  mkdir -p "${ROOT_DIR}/.tools/tls"
  mkcert -cert-file "${ROOT_DIR}/.tools/tls/taxi.localhost.pem" \
    -key-file "${ROOT_DIR}/.tools/tls/taxi.localhost-key.pem" \
    taxi.localhost '*.taxi.localhost'
  cp "$(mkcert -CAROOT)/rootCA.pem" "${ROOT_DIR}/.tools/tls/ca.pem"
  log_warn "CA generated but not installed into host trust; trust-store mutation stays opt-in"
}

cache() {
  populate_cache_manifest
}

cluster() {
  if kind_cluster_exists; then
    [[ "${RECREATE_CLUSTER}" == true ]] || lifecycle_die \
      "Partial cluster exists; rerun with --recreate-cluster after reviewing preserved MinIO data"
    kind delete cluster --name "${CLUSTER_NAME}"
  fi
  [[ "${OFFLINE}" == false ]] || lifecycle_die "Clean cluster creation is not supported offline; resume against an existing cluster"
  "${ROOT_DIR}/scripts/deploy-local-platform.sh"
}

storage() {
  lifecycle_die "Storage missing after deploy-local-platform.sh"
}

images() {
  local args=()
  [[ "${OFFLINE}" == false ]] || args+=(--offline)
  "${ROOT_DIR}/scripts/build-images.sh" "${args[@]}"
}

platform() {
  helmfile --file "${ROOT_DIR}/infra/local/helmfile.yaml" apply
}

applications() {
  airflow_cli dags list 2>/dev/null | grep -Fq taxi_monthly_etl || lifecycle_die "Airflow DAGs are not ready"
  airflow_cli pools set taxi_etl_pool 1 "Single heavy ETL task for staged profile"
}

schema() {
  local pod
  pod="$(airflow_pod)" || lifecycle_die "Airflow webserver pod is unavailable"
  kubectl -n data-platform exec "${pod}" -- alembic upgrade head
}

calibration() {
  apply_etl_resource_profile
  trigger_airflow_run taxi_quality_calibration phase11-calibration
}

etl() {
  apply_etl_resource_profile
  trigger_airflow_run taxi_monthly_etl phase11-2023-01 '{"source_month":"2023-01"}'
  trigger_airflow_run taxi_monthly_etl phase11-2023-02 '{"source_month":"2023-02"}'
}

presentation() {
  apply_presentation_resource_profile
  kubectl wait --all-namespaces --for=condition=available --timeout=300s deployment
}

acceptance() {
  "${ROOT_DIR}/scripts/verify.sh"
  "${ROOT_DIR}/scripts/measure-resources.sh" --profile "${PROFILE}" \
    --host-label "${MACHINE_PROFILE:-unclassified}"
}

summary() {
  log_info "Profile: ${PROFILE}"
  if [[ -s "${ROOT_DIR}/data/SYNTHETIC" ]]; then
    log_warn "Data status: SYNTHETIC FALLBACK"
  else
    log_info "Data status: official TLC sources"
  fi
  log_info "Demo: ./scripts/demo.sh --profile ${PROFILE}"
  log_info "Teardown: ./teardown.sh"
}

main() {
  local started=false stage
  if [[ "${START_STAGE}" != preflight ]]; then
    command -v docker >/dev/null 2>&1 || lifecycle_die "Docker is required"
    docker info >/dev/null 2>&1 || lifecycle_die "Docker daemon is not reachable"
    PROFILE="$(select_resource_profile "${PROFILE}")"
  fi
  log_info "NYC Taxi ETL lifecycle: profile=${PROFILE}, tools=${TOOLS}, offline=${OFFLINE}"
  for stage in "${LIFECYCLE_STAGES[@]}"; do
    [[ "${stage}" == "${START_STAGE}" ]] && started=true
    [[ "${started}" == true ]] || continue
    CURRENT_STAGE="${stage}"
    if [[ "${stage}" != preflight ]] && stage_is_complete "${stage}"; then
      log_success "${stage}: already complete"
    else
      log_info "=== ${stage} ==="
      "${stage}"
      if [[ "${stage}" != preflight && "${stage}" != acceptance && "${stage}" != summary ]]; then
        stage_is_complete "${stage}" || lifecycle_die "${stage} did not reach ready state"
      fi
      log_success "${stage}: complete"
    fi
    [[ -z "${ONLY_STAGE}" ]] || break
  done
  CURRENT_STAGE=""
}

main
