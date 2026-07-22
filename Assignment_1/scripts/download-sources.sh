#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA_DIR="${DATA_DIR:-${ROOT_DIR}/data}"
mkdir -p "${DATA_DIR}"

parquet_valid() {
  local path="$1"
  [[ -s "${path}" ]] && [[ "$(dd if="${path}" bs=4 count=1 2>/dev/null)" == PAR1 ]] &&
    [[ "$(tail -c 4 "${path}")" == PAR1 ]]
}

declare -A EXPECTED_SHA256=(
  [2023-01]="32df6f67578fa86c484a6b5ef23a5281992ff085521082340b0f9e5889e9a572"
  [2023-02]="4809e6aaac64f05a62d16a25d55713be1537ad64fc261e895eaf2d2120fe750a"
)

source_valid() {
  local path="$1"
  local month="$2"
  parquet_valid "${path}" && [[ "$(sha256sum "${path}" | awk '{print $1}')" == "${EXPECTED_SHA256[${month}]}" ]]
}

for month in 2023-01 2023-02; do
  path="${DATA_DIR}/yellow_tripdata_${month}.parquet"
  url="https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_${month}.parquet"
  source_valid "${path}" "${month}" && continue
  rm -f "${path}.part"
  curl --fail --location --retry 5 --retry-all-errors \
    --connect-timeout 15 --speed-limit 1024 --speed-time 30 --continue-at - \
    "${url}" --output "${path}.part"
  source_valid "${path}.part" "${month}" || { printf 'Invalid Parquet download: %s\n' "${url}" >&2; exit 1; }
  mv "${path}.part" "${path}"
done
