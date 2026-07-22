#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
INFRA_DIR="$ROOT_DIR/infra/local"

uv run pytest tests/phase8 tests/dags -q
helm template traefik traefik --repo https://traefik.github.io/charts \
    --version 34.1.0 --namespace ingress --values "$INFRA_DIR/values/traefik.yaml" >/dev/null
helm template dex dex --repo https://dexidp.github.io/helm-charts \
    --version 0.19.1 --namespace identity --values "$INFRA_DIR/values/dex.yaml" >/dev/null
helm template oauth2-proxy oauth2-proxy --repo https://oauth2-proxy.github.io/manifests \
    --version 7.12.0 --namespace identity --values "$INFRA_DIR/values/oauth2-proxy.yaml" >/dev/null
helm template minio minio --repo https://charts.min.io/ \
    --version 5.4.0 --namespace data-platform --values "$INFRA_DIR/values/minio.yaml" >/dev/null
helm template airflow airflow --repo https://airflow.apache.org \
    --version 1.15.0 --namespace data-platform --values "$INFRA_DIR/values/airflow.yaml" >/dev/null

printf 'Phase 8 static and render checks passed\n'
