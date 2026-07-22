#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
GENERATED_DIR="$ROOT_DIR/infra/local/generated"

if [[ ! -f "$GENERATED_DIR/credentials.env" || ! -f "$GENERATED_DIR/rootCA.pem" ]]; then
    printf 'Missing generated Phase 8 security material; run ./scripts/deploy-phase8.sh first\n' >&2
    exit 1
fi
# shellcheck disable=SC1091
source "$GENERATED_DIR/credentials.env"

resolve=(--resolve dex.taxi.localhost:8443:127.0.0.1 --cacert "$GENERATED_DIR/rootCA.pem")
discovery="$(curl --fail --silent --show-error "${resolve[@]}" \
    https://dex.taxi.localhost:8443/.well-known/openid-configuration)"
python -c 'import json,sys; assert json.load(sys.stdin)["issuer"] == "https://dex.taxi.localhost:8443"' <<<"$discovery"

check_login() {
    local username="$1" password="$2" response
    response="$(curl --fail --silent --show-error "${resolve[@]}" \
        --user "phase8-cli:$DEX_CLI_SECRET" \
        --header 'Content-Type: application/x-www-form-urlencoded' \
        --data-urlencode grant_type=password \
        --data-urlencode scope='openid email profile groups' \
        --data-urlencode "username=$username@taxi.local" \
        --data-urlencode "password=$password" \
        https://dex.taxi.localhost:8443/token)"
    python -c 'import base64,json,sys; token=json.load(sys.stdin)["id_token"].split(".")[1]; token += "=" * (-len(token) % 4); assert json.loads(base64.urlsafe_b64decode(token))["preferred_username"] == sys.argv[1]' "$username" <<<"$response"
}
check_login admin "$ADMIN_PASSWORD"
check_login viewer "$VIEWER_PASSWORD"

for host in mailpit alerts; do
    status="$(curl --silent --output /dev/null --write-out '%{http_code}' \
        --resolve "$host.taxi.localhost:8443:127.0.0.1" --cacert "$GENERATED_DIR/rootCA.pem" \
        --header 'X-Auth-Request-User: admin' "https://$host.taxi.localhost:8443/")"
    [[ "$status" == 302 ]] || { printf 'Expected auth redirect for %s, got %s\n' "$host" "$status" >&2; exit 1; }
done

TRAEFIK_IP="$(kubectl get service traefik --namespace ingress -o jsonpath='{.spec.clusterIP}')"
kubectl run phase8-dns --namespace identity --restart Never --rm --attach \
    --image=busybox:1.36.1 --command -- sh -c \
    "nslookup dex.taxi.localhost | grep -F '$TRAEFIK_IP'"

kubectl exec --namespace data-platform deployment/airflow-scheduler -- python -c \
    'import os,requests; r=requests.post(os.environ["ALERT_WEBHOOK_URL"], json={"event":"phase8_smoke","secret":"must-not-persist"}, headers={"X-Webhook-Token":os.environ["ALERT_WEBHOOK_TOKEN"]}, timeout=10); r.raise_for_status()'
kubectl exec --namespace data-platform deployment/airflow-scheduler -- python -c \
    'import os,smtplib; from email.message import EmailMessage; m=EmailMessage(); m["Subject"]="Phase 8 smoke"; m["From"]=os.environ["SMTP_FROM"]; m["To"]=os.environ["ALERT_EMAIL_TO"]; m.set_content("sanitized smoke"); s=smtplib.SMTP(os.environ["SMTP_HOST"], int(os.environ["SMTP_PORT"]), timeout=10); s.send_message(m); s.quit()'
kubectl exec --namespace taxi-app deployment/alert-receiver -- python -c \
    'import json,pathlib,urllib.request; records=list(pathlib.Path("/var/lib/taxi-alerts").glob("*.json")); assert records; assert "must-not-persist" not in records[-1].read_text(); assert json.load(urllib.request.urlopen("http://mailpit:8025/api/v1/messages", timeout=10))["total"] > 0'

if kubectl run phase8-denied --namespace identity --restart Never --rm --attach \
    --image=curlimages/curl:8.11.1 --command -- curl --fail --max-time 5 \
    http://alert-receiver.taxi-app.svc.cluster.local:8000/health; then
    printf 'Default-deny failed: identity pod reached alert receiver directly\n' >&2
    exit 1
fi

printf 'Phase 8 live smoke passed\n'
