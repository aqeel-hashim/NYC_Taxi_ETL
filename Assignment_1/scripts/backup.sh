#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GENERATED_DIR="$ROOT_DIR/infra/local/generated"
PLUGIN_VERSION="0.5.0"

command -v kubectl >/dev/null || { printf 'Missing kubectl\n' >&2; exit 1; }
[[ -f "$GENERATED_DIR/credentials.env" ]] || { printf 'Run Phase 8 secret generation first\n' >&2; exit 1; }
# shellcheck disable=SC1090
source "$GENERATED_DIR/credentials.env"

kubectl apply -f "https://github.com/cloudnative-pg/plugin-barman-cloud/releases/download/v${PLUGIN_VERSION}/manifest.yaml"
kubectl create secret generic cnpg-barman-s3 -n data-platform \
  --from-literal=ACCESS_KEY_ID="$MINIO_ROOT_USER" \
  --from-literal=SECRET_ACCESS_KEY="$MINIO_ROOT_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f "$ROOT_DIR/infra/local/manifests/phase9-backup.yaml"
backup_name="$(kubectl create -n data-platform -f - -o name <<'EOF'
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata:
  generateName: taxi-warehouse-
spec:
  cluster: {name: taxi-warehouse}
  method: plugin
  pluginConfiguration: {name: barman-cloud.cloudnative-pg.io}
EOF
)"
kubectl wait -n data-platform --for=jsonpath='{.status.phase}'=completed "$backup_name" --timeout=10m
printf 'CNPG base backup completed; WAL archiving is enabled by the Cluster plugin.\n'
