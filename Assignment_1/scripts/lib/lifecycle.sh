#!/usr/bin/env bash

CLUSTER_NAME="${CLUSTER_NAME:-nyc-taxi-etl}"
LIFECYCLE_STAGES=(
  preflight tools python secrets tls cache cluster storage images platform
  applications schema calibration etl presentation acceptance summary
)

lifecycle_die() {
  log_error "$*"
  return 1
}

lifecycle_has_value() {
  local wanted="$1"
  shift
  local value
  for value in "$@"; do
    [[ "${value}" == "${wanted}" ]] && return 0
  done
  return 1
}

lifecycle_validate_profile() {
  lifecycle_has_value "$1" auto staged concurrent
}

lifecycle_validate_tools() {
  lifecycle_has_value "$1" core all
}

lifecycle_validate_stage() {
  lifecycle_has_value "$1" "${LIFECYCLE_STAGES[@]}"
}

docker_cpu_count() {
  docker info --format '{{.NCPU}}' 2>/dev/null
}

docker_memory_bytes() {
  docker info --format '{{.MemTotal}}' 2>/dev/null
}

select_resource_profile() {
  local requested="$1"
  local cpus memory
  cpus="$(docker_cpu_count)"
  memory="$(docker_memory_bytes)"
  [[ "${cpus}" =~ ^[0-9]+$ && "${memory}" =~ ^[0-9]+$ ]] || lifecycle_die "Cannot measure Docker CPU/RAM"

  if [[ "${requested}" == auto ]]; then
    if ((cpus >= 4 && memory >= 8589934592)); then
      printf 'concurrent\n'
    else
      printf 'staged\n'
    fi
    return
  fi

  if [[ "${requested}" == concurrent ]] && ((cpus < 4 || memory < 8589934592)); then
    [[ "${FORCE_PROFILE:-false}" == true ]] || lifecycle_die \
      "Concurrent profile needs Docker >=4 CPUs and >=8 GiB RAM; use --profile staged or --force-profile"
    log_warn "Forcing concurrent profile below supported Docker resource floor" >&2
  fi
  printf '%s\n' "${requested}"
}

kind_cluster_exists() {
  command -v kind >/dev/null 2>&1 && kind get clusters 2>/dev/null | grep -Fxq "${CLUSTER_NAME}"
}

kubectl_resource_exists() {
  kubectl "$@" >/dev/null 2>&1
}

airflow_pod() {
  local pods
  pods="$(kubectl -n data-platform get pods -l component=webserver \
    --field-selector=status.phase=Running -o name 2>/dev/null)"
  pods="${pods%%$'\n'*}"
  [[ -n "${pods}" ]] || return 1
  printf '%s\n' "${pods}"
}

airflow_cli() {
  local pod
  pod="$(airflow_pod)" || return 1
  kubectl -n data-platform exec "${pod}" -- airflow "$@"
}

airflow_run_succeeded() {
  local dag_id="$1"
  local run_prefix="$2"
  airflow_cli dags list-runs --dag-id "${dag_id}" --state success -o json 2>/dev/null \
    | grep -Fq "${run_prefix}"
}

wait_for_airflow_run() {
  local dag_id="$1"
  local run_id="$2"
  local timeout_seconds="${3:-7200}"
  local elapsed=0 state
  while ((elapsed < timeout_seconds)); do
    state="$(airflow_cli dags state "${dag_id}" "${run_id}" 2>/dev/null || true)"
    case "${state}" in
      success) return 0 ;;
      failed) lifecycle_die "Airflow run failed: ${dag_id}/${run_id}"; return ;;
    esac
    sleep 10
    elapsed=$((elapsed + 10))
  done
  lifecycle_die "Timed out waiting for Airflow run: ${dag_id}/${run_id}"
}

trigger_airflow_run() {
  local dag_id="$1"
  local run_prefix="$2"
  local conf="${3:-}"
  local run_id="${run_prefix}-$(date -u +%Y%m%dT%H%M%SZ)"
  local args=(dags trigger "${dag_id}" --run-id "${run_id}")
  [[ -z "${conf}" ]] || args+=(--conf "${conf}")
  airflow_cli "${args[@]}"
  wait_for_airflow_run "${dag_id}" "${run_id}"
}

core_tools_ready() {
  local bin="${ROOT_DIR}/.tools/bin"
  [[ -x "${bin}/uv" && "$("${bin}/uv" --version 2>/dev/null)" == "uv 0.8.3" ]] || return 1
  [[ -x "${bin}/kind" ]] && "${bin}/kind" version 2>/dev/null | grep -Fq v0.27.0 || return 1
  [[ -x "${bin}/kubectl" ]] && "${bin}/kubectl" version --client 2>/dev/null | grep -Fq v1.32.1 || return 1
  [[ -x "${bin}/helm" ]] && "${bin}/helm" version --short 2>/dev/null | grep -Fq v3.17.0 || return 1
  [[ -x "${bin}/helmfile" ]] && "${bin}/helmfile" --version 2>/dev/null | grep -Fq 0.171.0 || return 1
  [[ -x "${bin}/gum" ]] && "${bin}/gum" --version 2>/dev/null | grep -Fq 0.14.5 || return 1
  [[ -x "${bin}/mkcert" ]] && "${bin}/mkcert" -version 2>/dev/null | grep -Fq v1.4.4
}

all_tools_ready() {
  local tool
  core_tools_ready || return 1
  for tool in terraform tflint checkov infracost aws cloudflared trivy syft cosign mmdc gh; do
    [[ -x "${ROOT_DIR}/.tools/bin/${tool}" ]] || return 1
  done
}

secrets_ready() {
  local key
  [[ -s "${ROOT_DIR}/.env" ]] || return 1
  ! grep -Eq 'change-me|=$' "${ROOT_DIR}/.env" || return 1
  for key in POSTGRES_PASSWORD DATABASE_URL AIRFLOW_DB_PASSWORD MINIO_ACCESS_KEY MINIO_SECRET_KEY; do
    grep -Eq "^${key}=.+" "${ROOT_DIR}/.env" || return 1
  done
}

parquet_file_valid() {
  local path="$1"
  [[ -s "${path}" ]] || return 1
  [[ "$(dd if="${path}" bs=4 count=1 2>/dev/null)" == PAR1 && "$(tail -c 4 "${path}")" == PAR1 ]]
}

cache_manifest_complete() {
  local line kind profile name reference
  while IFS='|' read -r kind profile name reference; do
    [[ -n "${kind}" && "${kind}" != \#* ]] || continue
    [[ "${profile}" == core || "${TOOLS}" == all ]] || continue
    case "${kind}" in
      source) parquet_file_valid "${ROOT_DIR}/${name}" || return 1 ;;
      image) docker image inspect "${reference}" >/dev/null 2>&1 || return 1 ;;
      chart) helm show chart "${ROOT_DIR}/.tools/cache/charts/${name}" >/dev/null 2>&1 || return 1 ;;
      *) lifecycle_die "Unknown cache manifest kind: ${kind}"; return ;;
    esac
  done <"${ROOT_DIR}/scripts/cache-manifest.tsv"
}

warehouse_schema_ready() {
  local pod
  pod="$(kubectl -n data-platform get pods \
    -l cnpg.io/cluster=taxi-warehouse,cnpg.io/podRole=instance \
    --field-selector=status.phase=Running -o name 2>/dev/null)"
  pod="${pod%%$'\n'*}"
  [[ -n "${pod}" ]] || return 1
  kubectl -n data-platform exec "${pod}" -- psql -U taxi_app -d taxi_warehouse -Atqc \
    "SELECT to_regclass('warehouse.fact_taxi_trips') IS NOT NULL" 2>/dev/null | grep -Fxq t
}

stage_is_complete() {
  local stage="$1"
  case "${stage}" in
    preflight|acceptance|summary) return 1 ;;
    tools)
      if [[ "${TOOLS}" == all ]]; then
        all_tools_ready
      else
        core_tools_ready
      fi
      ;;
    python) [[ -x "${ROOT_DIR}/.venv/bin/python" ]] ;;
    secrets) secrets_ready ;;
    tls)
      [[ -s "${ROOT_DIR}/.tools/tls/taxi.localhost.pem" &&
        -s "${ROOT_DIR}/.tools/tls/taxi.localhost-key.pem" &&
        -s "${ROOT_DIR}/.tools/tls/ca.pem" ]]
      ;;
    cache) cache_manifest_complete ;;
    cluster) kind_cluster_exists && kubectl cluster-info >/dev/null 2>&1 ;;
    storage)
      kubectl_resource_exists -n data-platform get cluster taxi-warehouse &&
        kubectl_resource_exists -n data-platform get service minio
      ;;
    images)
      docker image inspect taxi-airflow:latest taxi-dashboard:latest taxi-alert-receiver:latest >/dev/null 2>&1
      ;;
    platform)
      helm -n data-platform status airflow >/dev/null 2>&1 &&
        kubectl_resource_exists -n monitoring get deployment kube-prometheus-stack-operator &&
        kubectl_resource_exists -n ingress get deployment traefik
      ;;
    applications)
      airflow_cli dags list 2>/dev/null | grep -Fq taxi_monthly_etl &&
        airflow_cli pools get taxi_etl_pool 2>/dev/null | grep -Eq '(^|[^0-9])1([^0-9]|$)'
      ;;
    schema) warehouse_schema_ready ;;
    calibration) airflow_run_succeeded taxi_quality_calibration phase11-calibration ;;
    etl)
      airflow_run_succeeded taxi_monthly_etl phase11-2023-01 &&
        airflow_run_succeeded taxi_monthly_etl phase11-2023-02
      ;;
    presentation)
      kubectl_resource_exists -n monitoring get deployment kube-prometheus-stack-grafana &&
        kubectl_resource_exists -n taxi-app get deployment taxi-dashboard
      ;;
    *) lifecycle_die "Unknown lifecycle stage: ${stage}" ;;
  esac
}

scale_optional_deployment() {
  local namespace="$1" deployment="$2" replicas="$3"
  if kubectl_resource_exists -n "${namespace}" get deployment "${deployment}"; then
    kubectl -n "${namespace}" scale deployment "${deployment}" --replicas="${replicas}"
  fi
}

apply_etl_resource_profile() {
  [[ "${PROFILE}" == staged ]] || return 0
  log_info "Staged profile: scaling presentation workloads down for ETL"
  scale_optional_deployment monitoring kube-prometheus-stack-grafana 0
  scale_optional_deployment taxi-app taxi-dashboard 0
}

apply_presentation_resource_profile() {
  scale_optional_deployment monitoring kube-prometheus-stack-grafana 1
  scale_optional_deployment taxi-app taxi-dashboard 1
}
