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

for month in 2023-01 2023-02; do
  path="${DATA_DIR}/yellow_tripdata_${month}.parquet"
  url="https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_${month}.parquet"
  parquet_valid "${path}" && continue
  rm -f "${path}.part"
  curl --fail --location --retry 5 --retry-all-errors "${url}" --output "${path}.part"
  parquet_valid "${path}.part" || { printf 'Invalid Parquet download: %s\n' "${url}" >&2; exit 1; }
  mv "${path}.part" "${path}"
done
