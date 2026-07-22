#!/usr/bin/env bash

cache_download() {
  local url="$1" destination="$2"
  if [[ -s "${destination}" ]]; then
    return 0
  fi
  [[ "${OFFLINE}" == false ]] || lifecycle_die "Offline cache miss: ${destination}"
  mkdir -p "$(dirname "${destination}")"
  local temporary="${destination}.part"
  rm -f "${temporary}"
  curl --fail --location --retry 3 --retry-all-errors "${url}" --output "${temporary}" || {
    rm -f "${temporary}"
    return 1
  }
  [[ -s "${temporary}" ]] || lifecycle_die "Downloaded empty artifact: ${url}"
  mv "${temporary}" "${destination}"
}

cache_source() {
  local path="$1" url="$2"
  if [[ -e "${ROOT_DIR}/${path}" ]] && ! parquet_file_valid "${ROOT_DIR}/${path}"; then
    [[ "${OFFLINE}" == false ]] || lifecycle_die "Offline source is corrupt: ${ROOT_DIR}/${path}"
    log_warn "Replacing corrupt source: ${path}"
    rm -f "${ROOT_DIR}/${path}"
  fi
  if cache_download "${url}" "${ROOT_DIR}/${path}"; then
    return 0
  fi
  [[ "${ALLOW_SYNTHETIC_FALLBACK}" == true ]] || lifecycle_die "Source unavailable: ${url}"
  [[ "${OFFLINE}" == false ]] || lifecycle_die "Cannot verify source unavailability while offline"
  if curl --fail --silent --show-error --head --max-time 10 "${url}" >/dev/null; then
    lifecycle_die "Source is reachable; synthetic fallback forbidden after local download failure: ${url}"
  fi
  local fixture="${ROOT_DIR}/tests/fixtures/yellow_tripdata_fixture.parquet"
  [[ -s "${fixture}" ]] || lifecycle_die "Synthetic fixture unavailable: ${fixture}"
  cp "${fixture}" "${ROOT_DIR}/${path}"
  printf '%s synthetic fallback: verified download failure for %s\n' "$(date -Iseconds)" "${url}" \
    >>"${ROOT_DIR}/data/SYNTHETIC"
  log_warn "Synthetic fallback used for ${path}"
}

cache_image() {
  local reference="$1"
  docker image inspect "${reference}" >/dev/null 2>&1 && return 0
  [[ "${OFFLINE}" == false ]] || lifecycle_die "Offline image miss: ${reference}"
  docker pull "${reference}"
}

cache_chart() {
  local filename="$1" reference="$2"
  local chart="${reference%@*}"
  local version="${reference##*@}"
  local destination="${ROOT_DIR}/.tools/cache/charts/${filename}"
  helm show chart "${destination}" >/dev/null 2>&1 && return 0
  [[ ! -e "${destination}" || "${OFFLINE}" == false ]] || lifecycle_die "Offline chart is corrupt: ${destination}"
  rm -f "${destination}"
  [[ "${OFFLINE}" == false ]] || lifecycle_die "Offline chart miss: ${destination}"
  mkdir -p "${ROOT_DIR}/.tools/cache/charts"
  helm pull "${chart}" --version "${version}" --destination "${ROOT_DIR}/.tools/cache/charts"
  [[ -s "${destination}" ]] || lifecycle_die "Helm produced unexpected chart filename for ${reference}"
}

populate_cache_manifest() {
  if [[ "${OFFLINE}" == false ]]; then
    helm repo add cnpg https://cloudnative-pg.github.io/charts --force-update
    helm repo add minio https://charts.min.io/ --force-update
    helm repo add apache-airflow https://airflow.apache.org --force-update
    helm repo add traefik https://traefik.github.io/charts --force-update
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update
    helm repo add grafana https://grafana.github.io/helm-charts --force-update
    helm repo add dex https://charts.dexidp.io --force-update
    helm repo add oauth2-proxy https://oauth2-proxy.github.io/manifests --force-update
    helm repo add mailpit https://jouve.github.io/charts/ --force-update
    helm repo update
  fi
  local kind profile name reference
  while IFS='|' read -r kind profile name reference; do
    [[ -n "${kind}" && "${kind}" != \#* ]] || continue
    [[ "${profile}" == core || "${TOOLS}" == all ]] || continue
    case "${kind}" in
      source) cache_source "${name}" "${reference}" ;;
      image) cache_image "${reference}" ;;
      chart) cache_chart "${name}" "${reference}" ;;
      *) lifecycle_die "Unknown cache manifest kind: ${kind}" ;;
    esac
  done <"${ROOT_DIR}/scripts/cache-manifest.tsv"
}
