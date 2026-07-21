#!/usr/bin/env bash
set -euo pipefail

# Per month DAG pipeline execution script

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/logging.sh"

MONTH="${1:-}"
FIXTURE="false"
if [[ -z "${MONTH}" || ! "${MONTH}" =~ ^[0-9]{4}-(0[1-9]|1[0-2])$ ]]; then
    log_error "Usage: run-pipeline.sh YYYY-MM [--fixture]"
    exit 2
fi
shift || true
while [[ $# -gt 0 ]]; do
    case "$1" in
        --fixture) FIXTURE="true" ;;
        *) log_error "Unsupported option: $1"; exit 2 ;;
    esac
    shift
done

if [[ -z "${DATABASE_URL:-}" ]]; then
    log_error "DATABASE_URL is required"
    exit 4
fi

log_info "Running pipeline for ${MONTH}..."

args=("-m" "nyc_taxi_etl.pipeline" "${MONTH}")
if [[ "${FIXTURE}" == "true" ]]; then
    args+=("--fixture")
fi
uv run python "${args[@]}" || exit $?

log_success "Pipeline for ${MONTH} complete"
