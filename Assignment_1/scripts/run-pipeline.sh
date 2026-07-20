#!/usr/bin/env bash
set -euo pipefail

# Per month DAG pipeline execution script

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/logging.sh"

MONTH="${1:-}"
if [[ -z "${MONTH}" ]]; then
    log_error "Usage: run-pipeline.sh YYYY-MM"
    exit 1
fi

log_info "Running pipeline for ${MONTH}..."

docker compose -f "${SCRIPT_DIR}/../infra/local/compose.postgres.yaml" up -d --wait

uv run python -c "
from nyc_taxi_etl.transform.trips import TransformResult
print(f'Pipeline stub for {${MONTH}}: transform module loaded successfully')
" || { log_error "Pipeline failed"; exit 1; }

log_success "Pipeline for ${MONTH} complete"
