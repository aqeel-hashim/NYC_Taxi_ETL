#!/usr/bin/env bash
set -euo pipefail

DATA_DIR="${DATA_DIR:-data}"
mkdir -p "${DATA_DIR}"

for month in 2023-01 2023-02; do
  path="${DATA_DIR}/yellow_tripdata_${month}.parquet"
  url="https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_${month}.parquet"
  [[ -f "${path}" ]] || curl -fL "${url}" -o "${path}"
done
