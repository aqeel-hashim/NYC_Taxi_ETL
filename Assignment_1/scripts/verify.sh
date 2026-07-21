#!/usr/bin/env bash
set -euo pipefail

# static analysis script, needs to be expanded as we go along of course

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/logging.sh"

log_info "Running verification..."
uv run ruff check . || { log_error "Ruff checks failed"; exit 1; }
uv run ruff format --check . || { log_error "Ruff format failed"; exit 1; }
uv run mypy src tests || { log_error "mypy checks failed"; exit 1; }
uv run pytest --cov --cov-branch --cov-report=term --cov-fail-under=85 || { log_error "Tests failed"; exit 1; }
uv run sqlfluff lint sql/queries --dialect postgres || { log_error "SQL lint failed"; exit 1; }

if [[ -n "${TEST_DATABASE_URL:-}" ]]; then
  uv run pytest tests/integration/test_warehouse_contract.py -q || { log_error "Warehouse contract failed"; exit 1; }
else
  log_info "Skipping warehouse contract: TEST_DATABASE_URL not set"
fi

log_success "All verifications passed"
