#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
INFRA_DIR="$ROOT_DIR/infra/local"
GENERATED_DIR="$INFRA_DIR/generated"
CLUSTER_NAME="nyc-taxi-etl"
MODE=full
source "$SCRIPT_DIR/lib/kind-registry.sh"

case "${1:-}" in
    "") ;;
    --secrets-only) MODE=secrets ;;
    --identity-only) MODE=identity ;;
    --finish) MODE=finish ;;
    *) printf 'Usage: %s [--secrets-only|--identity-only|--finish]\n' "$0" >&2; exit 2 ;;
esac
[[ $# -le 1 ]] || { printf 'Too many arguments\n' >&2; exit 2; }

for command_name in docker helm kind kubectl openssl; do
    command -v "$command_name" >/dev/null 2>&1 || { printf 'Missing: %s\n' "$command_name" >&2; exit 1; }
done

if [[ ("$MODE" == secrets || "$MODE" == full) && -t 0 ]]; then
    "$SCRIPT_DIR/generate-phase8-security.sh"
else
    "$SCRIPT_DIR/generate-phase8-security.sh" --non-interactive
fi
# shellcheck disable=SC1091
source "$GENERATED_DIR/credentials.env"

apply_secret() {
    local namespace="$1" name="$2"
    shift 2
    kubectl create secret generic "$name" --namespace "$namespace" "$@" \
        --dry-run=client -o yaml | kubectl apply --server-side --force-conflicts --field-manager=taxi-phase8 -f - >/dev/null
}

for namespace in ingress identity data-platform taxi-app; do
    kubectl create secret tls taxi-tls-cert --namespace "$namespace" \
        --cert "$GENERATED_DIR/tls.crt" --key "$GENERATED_DIR/tls.key" \
        --dry-run=client -o yaml | kubectl apply --server-side --force-conflicts --field-manager=taxi-phase8 -f - >/dev/null
    apply_secret "$namespace" taxi-ca \
        "--from-file=rootCA.pem=$GENERATED_DIR/rootCA.pem" \
        "--from-file=ca-bundle.pem=$GENERATED_DIR/ca-bundle.pem" \
        "--from-file=public.crt=$GENERATED_DIR/rootCA.pem"
done

apply_secret monitoring alertmanager-webhook "--from-literal=token=$ALERT_WEBHOOK_TOKEN"

apply_secret identity dex-config "--from-file=config.yaml=$GENERATED_DIR/dex-config.yaml"
apply_secret identity dex-client-secrets \
    "--from-literal=DEX_OAUTH2_PROXY_SECRET=$DEX_OAUTH2_PROXY_SECRET" \
    "--from-literal=DEX_AIRFLOW_SECRET=$DEX_AIRFLOW_SECRET" \
    "--from-literal=DEX_MINIO_SECRET=$DEX_MINIO_SECRET" \
    "--from-literal=DEX_CLI_SECRET=$DEX_CLI_SECRET"
apply_secret identity oauth2-proxy-secrets \
    --from-literal=client-id=oauth2-proxy \
    "--from-literal=client-secret=$DEX_OAUTH2_PROXY_SECRET" \
    "--from-literal=cookie-secret=$OAUTH2_COOKIE_SECRET"
apply_secret taxi-app alert-receiver "--from-literal=webhook-token=$ALERT_WEBHOOK_TOKEN"
apply_secret data-platform minio-root-credentials \
    "--from-literal=rootUser=$MINIO_ROOT_USER" \
    "--from-literal=rootPassword=$MINIO_ROOT_PASSWORD"
apply_secret data-platform minio-oidc \
    --from-literal=client-id=minio \
    "--from-literal=client-secret=$DEX_MINIO_SECRET"
apply_secret data-platform taxi-app-password \
    --from-literal=username=taxi_app \
    "--from-literal=password=$TAXI_APP_DB_PASSWORD"
apply_secret data-platform airflow-password \
    --from-literal=username=airflow \
    "--from-literal=password=$AIRFLOW_DB_PASSWORD"
apply_secret data-platform database-bootstrap-sql \
    "--from-literal=bootstrap.sql=CREATE ROLE airflow LOGIN PASSWORD '$AIRFLOW_DB_PASSWORD'; CREATE DATABASE airflow OWNER airflow;"
apply_secret data-platform airflow-metadata \
    "--from-literal=connection=postgresql+psycopg2://airflow:$AIRFLOW_DB_PASSWORD@taxi-warehouse-rw.data-platform:5432/airflow?sslmode=disable"
apply_secret data-platform airflow-webserver-key \
    "--from-literal=webserver-secret-key=$AIRFLOW_WEBSERVER_SECRET"
apply_secret data-platform airflow-platform-secrets \
    "--from-literal=DATABASE_URL=postgresql+psycopg://taxi_app:$TAXI_APP_DB_PASSWORD@taxi-warehouse-rw.data-platform:5432/taxi_warehouse" \
    --from-literal=MINIO_ENDPOINT=minio.data-platform:9000 \
    "--from-literal=MINIO_ACCESS_KEY=$MINIO_ROOT_USER" \
    "--from-literal=MINIO_SECRET_KEY=$MINIO_ROOT_PASSWORD" \
    --from-literal=AIRFLOW_OIDC_CLIENT_ID=airflow \
    "--from-literal=AIRFLOW_OIDC_CLIENT_SECRET=$DEX_AIRFLOW_SECRET" \
    --from-literal=SSL_CERT_FILE=/etc/taxi-ca/ca-bundle.pem \
    --from-literal=REQUESTS_CA_BUNDLE=/etc/taxi-ca/ca-bundle.pem \
    --from-literal=ALERT_WEBHOOK_URL=http://alert-receiver.taxi-app.svc.cluster.local:8000/webhook \
    "--from-literal=ALERT_WEBHOOK_TOKEN=$ALERT_WEBHOOK_TOKEN" \
    "--from-literal=SMTP_HOST=${SMTP_HOST:-mailpit.taxi-app.svc.cluster.local}" \
    "--from-literal=SMTP_PORT=${SMTP_PORT:-1025}" \
    "--from-literal=SMTP_STARTTLS=${SMTP_STARTTLS:-false}" \
    "--from-literal=SMTP_SSL=${SMTP_SSL:-false}" \
    "--from-literal=SMTP_USERNAME=${SMTP_USERNAME:-}" \
    "--from-literal=SMTP_PASSWORD=${SMTP_PASSWORD:-}" \
    "--from-literal=SMTP_FROM=${SMTP_FROM:-airflow@taxi.local}" \
    "--from-literal=ALERT_EMAIL_TO=${ALERT_EMAIL_TO:-admin@taxi.local}"

kubectl create configmap airflow-webserver-config --namespace data-platform \
    "--from-file=webserver_config.py=$INFRA_DIR/config/airflow_webserver_config.py" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null

if [[ "$MODE" == secrets ]]; then
    exit 0
fi

if [[ "$MODE" != finish ]]; then
    kind_registry_mirror docker.io/library/traefik:v3.3.2
    kind_registry_mirror ghcr.io/dexidp/dex:v2.41.1
    kind_registry_mirror quay.io/oauth2-proxy/oauth2-proxy:v7.8.1
    helm upgrade --install traefik traefik \
        --namespace ingress --repo https://traefik.github.io/charts \
        --version 34.1.0 --values "$INFRA_DIR/values/traefik.yaml" \
        --wait --timeout 5m
    kubectl apply -f "$INFRA_DIR/manifests/coredns.yaml"
    kubectl rollout restart deployment/coredns --namespace kube-system
    kubectl rollout status deployment/coredns --namespace kube-system --timeout=120s

    helm upgrade --install dex dex \
        --namespace identity --repo https://dexidp.github.io/helm-charts \
        --version 0.19.1 --values "$INFRA_DIR/values/dex.yaml" \
        --wait --timeout 5m
    helm upgrade --install oauth2-proxy oauth2-proxy \
        --namespace identity --repo https://oauth2-proxy.github.io/manifests \
        --version 7.12.0 --values "$INFRA_DIR/values/oauth2-proxy.yaml" \
        --wait --timeout 5m
fi

if [[ "$MODE" == identity ]]; then
    exit 0
fi

docker build -t taxi-alert-receiver:latest -f "$ROOT_DIR/docker/alert-receiver.Dockerfile" "$ROOT_DIR"
kind_registry_push taxi-alert-receiver:latest
kind_registry_mirror docker.io/axllent/mailpit:v1.21.8
kubectl apply -f "$INFRA_DIR/manifests/phase8-apps.yaml"
kubectl rollout status deployment/mailpit --namespace taxi-app --timeout=180s
kubectl rollout status deployment/alert-receiver --namespace taxi-app --timeout=180s
kubectl apply -f "$INFRA_DIR/manifests/phase8-routes.yaml"
kubectl apply -f "$INFRA_DIR/manifests/phase8-network-policies.yaml"

printf 'Phase 8 deployed. Run: ./scripts/test-phase8-live.sh\n'
