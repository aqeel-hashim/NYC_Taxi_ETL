#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAMESPACE="restore-drill"
START="$(date +%s)"

command -v kubectl >/dev/null || { printf 'Missing kubectl\n' >&2; exit 1; }
kubectl get objectstore taxi-backups -n data-platform >/dev/null 2>&1 || "$ROOT_DIR/scripts/backup.sh"
[[ -f "$ROOT_DIR/infra/local/generated/credentials.env" ]] || { printf 'Run Phase 8 secret generation first\n' >&2; exit 1; }
# shellcheck disable=SC1090
source "$ROOT_DIR/infra/local/generated/credentials.env"
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic cnpg-barman-s3 -n "$NAMESPACE" \
  --from-literal=ACCESS_KEY_ID="$MINIO_ROOT_USER" \
  --from-literal=SECRET_ACCESS_KEY="$MINIO_ROOT_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n "$NAMESPACE" -f - <<'EOF'
apiVersion: barmancloud.cnpg.io/v1
kind: ObjectStore
metadata: {name: taxi-backups}
spec:
  configuration:
    destinationPath: s3://cnpg-backups/taxi-warehouse
    endpointURL: http://minio.data-platform.svc.cluster.local:9000
    s3Credentials:
      accessKeyId: {name: cnpg-barman-s3, key: ACCESS_KEY_ID}
      secretAccessKey: {name: cnpg-barman-s3, key: SECRET_ACCESS_KEY}
---
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata: {name: taxi-restore}
spec:
  instances: 1
  imageName: ghcr.io/cloudnative-pg/postgresql:17.4
  storage: {size: 2Gi}
  bootstrap:
    recovery: {source: backup}
  externalClusters:
    - name: backup
      plugin:
        name: barman-cloud.cloudnative-pg.io
        parameters: {barmanObjectName: taxi-backups}
EOF
kubectl wait -n "$NAMESPACE" --for=condition=Ready cluster/taxi-restore --timeout=15m
kubectl exec -n "$NAMESPACE" taxi-restore-1 -- psql -U postgres -d taxi_warehouse -Atc "select count(*) from fact_taxi_trips" >/dev/null
printf 'Restore drill passed in %ss\n' "$(( $(date +%s) - START ))"
kubectl delete namespace "$NAMESPACE" --wait=true
