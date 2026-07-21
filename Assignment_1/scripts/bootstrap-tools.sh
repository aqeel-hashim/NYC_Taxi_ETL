#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/logging.sh"

command -v uv >/dev/null 2>&1 || {
  log_error "uv is required"
  exit 1
}

# ponytail: local ETL does not need Kubernetes platform binaries.
log_info "uv $(uv --version)"
log_info "Platform tool installation is deferred until Kubernetes work starts"
