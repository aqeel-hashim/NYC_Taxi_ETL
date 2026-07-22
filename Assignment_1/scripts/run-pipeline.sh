#!/usr/bin/env bash
set -euo pipefail

exec uv run python -m nyc_taxi_etl.pipeline "$@"
