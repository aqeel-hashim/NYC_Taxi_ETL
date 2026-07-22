#!/usr/bin/env bash
set -euo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
GENERATED_DIR="$ROOT_DIR/infra/local/generated"
CAROOT="$GENERATED_DIR/mkcert-ca"
NON_INTERACTIVE=false
TRUST_HOST=false

usage() {
    printf '%s\n' \
        "Usage: $0 [--non-interactive] [--trust-host]" \
        "" \
        "Generates persistent local credentials and a mkcert CA under:" \
        "  $GENERATED_DIR" \
        "" \
        "--trust-host mutates the Linux trust store only after explicit consent." \
        "For Windows browsers under WSL2, run this in elevated PowerShell:" \
        "  certutil.exe -addstore -f ROOT <Windows path to mkcert-ca/rootCA.pem>"
}

while (($#)); do
    case "$1" in
        --non-interactive) NON_INTERACTIVE=true ;;
        --trust-host) TRUST_HOST=true ;;
        --help|-h) usage; exit 0 ;;
        *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

mkdir -p "$GENERATED_DIR" "$CAROOT"

MKCERT="${MKCERT:-}"
if [[ -z "$MKCERT" ]]; then
    for candidate in "$ROOT_DIR/.tools/bin/mkcert" "$ROOT_DIR/.tools/mkcert" "$(command -v mkcert || true)"; do
        if [[ -n "$candidate" && -x "$candidate" ]]; then
            MKCERT="$candidate"
            break
        fi
    done
fi
if [[ -z "$MKCERT" ]]; then
    printf 'mkcert not found; run ./scripts/bootstrap-tools.sh or set MKCERT=/path/to/mkcert\n' >&2
    exit 1
fi

random_hex() {
    openssl rand -hex "$1"
}

CREDENTIALS="$GENERATED_DIR/credentials.env"
if [[ ! -f "$CREDENTIALS" ]]; then
    cat >"$CREDENTIALS" <<EOF
ADMIN_PASSWORD=$(random_hex 16)
VIEWER_PASSWORD=$(random_hex 16)
DEX_OAUTH2_PROXY_SECRET=$(random_hex 32)
DEX_AIRFLOW_SECRET=$(random_hex 32)
DEX_MINIO_SECRET=$(random_hex 32)
DEX_CLI_SECRET=$(random_hex 32)
OAUTH2_COOKIE_SECRET=$(openssl rand -base64 32 | tr -d '\n')
ALERT_WEBHOOK_TOKEN=$(random_hex 32)
AIRFLOW_WEBSERVER_SECRET=$(random_hex 32)
TAXI_APP_DB_PASSWORD=$(random_hex 24)
AIRFLOW_DB_PASSWORD=$(random_hex 24)
MINIO_ROOT_USER=taxi-minio-admin
MINIO_ROOT_PASSWORD=$(random_hex 24)
EOF
    chmod 600 "$CREDENTIALS"
fi

# Generated values are restricted to URL-safe/base64 characters by construction.
# shellcheck disable=SC1090
source "$CREDENTIALS"

export CAROOT
if [[ ! -f "$GENERATED_DIR/tls.crt" || ! -f "$GENERATED_DIR/tls.key" ]]; then
    "$MKCERT" -cert-file "$GENERATED_DIR/tls.crt" -key-file "$GENERATED_DIR/tls.key" \
        "*.taxi.localhost" \
        dex.taxi.localhost auth.taxi.localhost airflow.taxi.localhost minio.taxi.localhost \
        mailpit.taxi.localhost alerts.taxi.localhost grafana.taxi.localhost \
        prometheus.taxi.localhost streamlit.taxi.localhost
fi
cp "$CAROOT/rootCA.pem" "$GENERATED_DIR/rootCA.pem"
chmod 600 "$GENERATED_DIR/tls.key" "$CAROOT/rootCA-key.pem"

SYSTEM_CA_BUNDLE=""
for candidate in /etc/ssl/certs/ca-certificates.crt /etc/ssl/cert.pem /etc/pki/tls/certs/ca-bundle.crt; do
    if [[ -f "$candidate" ]]; then
        SYSTEM_CA_BUNDLE="$candidate"
        break
    fi
done
if [[ -z "$SYSTEM_CA_BUNDLE" ]]; then
    printf 'System CA bundle not found; cannot build combined pod trust bundle\n' >&2
    exit 1
fi
cp "$SYSTEM_CA_BUNDLE" "$GENERATED_DIR/ca-bundle.pem"
printf '\n' >>"$GENERATED_DIR/ca-bundle.pem"
cat "$GENERATED_DIR/rootCA.pem" >>"$GENERATED_DIR/ca-bundle.pem"

bcrypt() {
    local password="$1" result
    result="$(docker run --rm --entrypoint htpasswd \
        httpd:2.4.62-alpine@sha256:88c55a4fcc1df6cf9e7b38360fb6a6feb4d5c5cf5a27a9ff38096ae585af707f \
        -bnBC 12 ignored "$password")"
    printf '%s' "${result#*:}"
}

DEX_CONFIG="$GENERATED_DIR/dex-config.yaml"
if [[ ! -f "$DEX_CONFIG" ]]; then
    ADMIN_HASH="$(bcrypt "$ADMIN_PASSWORD")"
    VIEWER_HASH="$(bcrypt "$VIEWER_PASSWORD")"
    cat >"$DEX_CONFIG" <<EOF
issuer: https://dex.taxi.localhost:8443
storage:
  type: sqlite3
  config:
    file: /var/dex/dex.db
web:
  http: 0.0.0.0:5556
frontend:
  issuer: NYC Taxi ETL
enablePasswordDB: true
oauth2:
  passwordConnector: local
  skipApprovalScreen: true
staticClients:
  - id: oauth2-proxy
    name: Protected platform UIs
    secretEnv: DEX_OAUTH2_PROXY_SECRET
    redirectURIs:
      - https://auth.taxi.localhost:8443/oauth2/callback
  - id: airflow
    name: Airflow
    secretEnv: DEX_AIRFLOW_SECRET
    redirectURIs:
      - https://airflow.taxi.localhost:8443/oauth-authorized/dex
  - id: minio
    name: MinIO
    secretEnv: DEX_MINIO_SECRET
    redirectURIs:
      - https://minio.taxi.localhost:8443/oauth_callback
  - id: phase8-cli
    name: Phase 8 CLI smoke test
    secretEnv: DEX_CLI_SECRET
staticPasswords:
  - email: admin@taxi.local
    hash: "$ADMIN_HASH"
    username: admin
    userID: 08a8684b-db88-4b73-90a9-3cd1661f5466
  - email: viewer@taxi.local
    hash: "$VIEWER_HASH"
    username: viewer
    userID: 18a8684b-db88-4b73-90a9-3cd1661f5466
EOF
    chmod 600 "$DEX_CONFIG"
fi

if [[ "$TRUST_HOST" == false && "$NON_INTERACTIVE" == false && -t 0 ]]; then
    printf 'Install the generated CA into the WSL/Linux host trust store? [y/N] '
    read -r answer
    [[ "$answer" =~ ^[Yy]$ ]] && TRUST_HOST=true
fi
if [[ "$TRUST_HOST" == true ]]; then
    "$MKCERT" -install
fi

printf 'Phase 8 security material ready: %s\n' "$GENERATED_DIR"
if grep -qi microsoft /proc/version 2>/dev/null; then
    WINDOWS_CA_PATH="$(wslpath -w "$GENERATED_DIR/rootCA.pem" 2>/dev/null || true)"
    printf 'WSL2 browser trust requires elevated Windows PowerShell:\n'
    printf '  certutil.exe -addstore -f ROOT "%s"\n' "$WINDOWS_CA_PATH"
fi
