#!/usr/bin/env bash
set -euo pipefail

bytes="$(tar \
  --exclude-vcs \
  --exclude='./.venv' --exclude='./.tools' --exclude='./data' --exclude='./dist' \
  --exclude='./.pytest_cache' --exclude='./.ruff_cache' --exclude='./.mypy_cache' \
  --exclude='./htmlcov' --exclude='./.env' --exclude='./.code-review-graph' \
  --exclude='*/__pycache__' --exclude='*.pyc' \
  -czf - . | wc -c)"
echo "docker_context_bytes=${bytes}"
test "${bytes}" -lt 5000000
