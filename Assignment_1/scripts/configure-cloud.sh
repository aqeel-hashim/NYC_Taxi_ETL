#!/usr/bin/env bash
set -euo pipefail
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
AWS_DIR="$ROOT_DIR/infra/aws"
TOOLS_DIR="$ROOT_DIR/.tools"
GUM_VERSION="0.16.2"
NON_INTERACTIVE=false
WRITE_GITHUB=false
ASSUME_YES=false
OPEN_DOCS=false
ENVIRONMENT="${CLOUD_ENVIRONMENT:-}"
ACTIONS_REPOSITORY="${GITHUB_REPOSITORY:-}"

AWS_ACCOUNT_ID="${CLOUD_AWS_ACCOUNT_ID:-}"
OWNER="${CLOUD_OWNER:-}"
COST_CENTER="${CLOUD_COST_CENTER:-}"
EXPIRES_AT="${CLOUD_EXPIRES_AT:-}"
BUDGET_USD="${CLOUD_BUDGET_USD:-}"
BUDGET_ALERT_EMAILS="${CLOUD_BUDGET_ALERT_EMAILS:-}"
GITHUB_REPOSITORY="${CLOUD_GITHUB_REPOSITORY:-}"
DEPLOYMENT_ROLE_ARN="${CLOUD_DEPLOYMENT_ROLE_ARN:-}"
CLOUDFLARE_ACCOUNT_ID="${CLOUD_CLOUDFLARE_ACCOUNT_ID:-}"
CLOUDFLARE_ZONE_ID="${CLOUD_CLOUDFLARE_ZONE_ID:-}"
CLOUDFLARE_API_TOKEN="${CLOUD_CLOUDFLARE_API_TOKEN:-}"
APP_DOMAIN="${CLOUD_APP_DOMAIN:-}"
PRIMARY_ORIGIN="${CLOUD_PRIMARY_ORIGIN:-}"
DR_ORIGIN="${CLOUD_DR_ORIGIN:-}"
ENTERPRISE_OIDC_ISSUER="${CLOUD_ENTERPRISE_OIDC_ISSUER:-}"
ENTERPRISE_OIDC_CLIENT_ID="${CLOUD_ENTERPRISE_OIDC_CLIENT_ID:-}"
ENTERPRISE_OIDC_CLIENT_SECRET="${CLOUD_ENTERPRISE_OIDC_CLIENT_SECRET:-}"
SMTP_FROM_ADDRESS="${CLOUD_SMTP_FROM_ADDRESS:-}"
BACKEND_BUCKET="${CLOUD_BACKEND_BUCKET:-}"
BACKEND_KMS_KEY_ARN="${CLOUD_BACKEND_KMS_KEY_ARN:-}"
BUCKET_PREFIX="${CLOUD_BUCKET_PREFIX:-}"

usage() {
  cat <<'EOF'
Usage: ./scripts/configure-cloud.sh [options]
  --environment dev|prod
  --non-interactive       Read CLOUD_* variables only
  --write-github-secrets  Offer to write protected-environment secrets with gh
  --yes                   Confirm secret upload (never plan/apply)
  --open-docs             Open provider setup documentation
EOF
}

while (($#)); do
  case "$1" in
    --environment) ENVIRONMENT="${2:?missing environment}"; shift 2 ;;
    --non-interactive) NON_INTERACTIVE=true; shift ;;
    --write-github-secrets) WRITE_GITHUB=true; shift ;;
    --yes) ASSUME_YES=true; shift ;;
    --open-docs) OPEN_DOCS=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

for command in aws curl jq sha256sum tar; do
  command -v "$command" >/dev/null || { printf 'Missing required command: %s\n' "$command" >&2; exit 1; }
done

install_gum() {
  local arch archive checksum url tmp
  case "$(uname -m)" in
    x86_64) arch="x86_64"; checksum="b7a9db6cee95a3475f6f18fb860dc3d3f812bd0b9e12071e448a942eebb1457a" ;;
    aarch64|arm64) arch="arm64"; checksum="05870f6f7b86ce64d27ed79555dcb7ad50c17ef4fe29f396cd7a4c010cde5a4b" ;;
    *) printf 'Unsupported Gum architecture: %s\n' "$(uname -m)" >&2; exit 1 ;;
  esac
  mkdir -p "$TOOLS_DIR"
  [[ -x "$TOOLS_DIR/gum" ]] && return
  archive="gum_${GUM_VERSION}_Linux_${arch}.tar.gz"
  url="https://github.com/charmbracelet/gum/releases/download/v${GUM_VERSION}/${archive}"
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp:-}" "${CURL_CONFIG:-}"' EXIT
  curl --fail --silent --show-error --location --output "$tmp/$archive" "$url"
  printf '%s  %s\n' "$checksum" "$tmp/$archive" | sha256sum --check --status || {
    printf 'Gum checksum verification failed\n' >&2
    exit 1
  }
  tar -xzf "$tmp/$archive" -C "$tmp"
  install -m 0755 "$tmp/gum" "$TOOLS_DIR/gum"
}

if ! $NON_INTERACTIVE; then
  install_gum
  GUM="$TOOLS_DIR/gum"
  [[ -n "$ENVIRONMENT" ]] || ENVIRONMENT="$($GUM choose dev prod --header 'AWS environment')"
fi

[[ "$ENVIRONMENT" == "dev" || "$ENVIRONMENT" == "prod" ]] || {
  printf 'CLOUD_ENVIRONMENT/--environment must be dev or prod\n' >&2
  exit 2
}

prompt() {
  local variable="$1" label="$2" default="${3:-}" value="${!1:-}"
  if [[ -z "$value" && "$NON_INTERACTIVE" == false ]]; then
    value="$($GUM input --header "$label" --value "$default")"
  fi
  [[ -n "$value" ]] || { printf 'Missing %s (CLOUD_%s)\n' "$label" "$variable" >&2; exit 1; }
  printf -v "$variable" '%s' "$value"
}

secret_prompt() {
  local variable="$1" label="$2" value="${!1:-}"
  if [[ -z "$value" && "$NON_INTERACTIVE" == false ]]; then
    value="$($GUM input --password --header "$label")"
  fi
  [[ -n "$value" ]] || { printf 'Missing %s (CLOUD_%s)\n' "$label" "$variable" >&2; exit 1; }
  printf -v "$variable" '%s' "$value"
  [[ -z "${GITHUB_ACTIONS:-}" ]] || printf '::add-mask::%s\n' "$value"
}

prompt AWS_ACCOUNT_ID "AWS account ID"
prompt OWNER "Owner tag"
prompt COST_CENTER "Cost center tag"
if [[ "$ENVIRONMENT" == "dev" ]]; then prompt EXPIRES_AT "Dev expiry (YYYY-MM-DD)"; else EXPIRES_AT="${EXPIRES_AT:-}"; fi
prompt BUDGET_USD "Monthly budget USD" "$([[ "$ENVIRONMENT" == dev ]] && printf 300 || printf 2500)"
prompt BUDGET_ALERT_EMAILS "Budget/alert emails (comma-separated)"
prompt GITHUB_REPOSITORY "GitHub owner/repository"
prompt DEPLOYMENT_ROLE_ARN "Bootstrap deployment role ARN"
prompt CLOUDFLARE_ACCOUNT_ID "Cloudflare account ID"
prompt CLOUDFLARE_ZONE_ID "Cloudflare zone ID"
secret_prompt CLOUDFLARE_API_TOKEN "Cloudflare scoped API token"
prompt APP_DOMAIN "Application DNS name"
prompt PRIMARY_ORIGIN "Primary ingress hostname"
if [[ "$ENVIRONMENT" == prod ]]; then prompt DR_ORIGIN "DR ingress hostname"; else DR_ORIGIN="${DR_ORIGIN:-}"; fi
prompt ENTERPRISE_OIDC_ISSUER "Enterprise OIDC issuer"
prompt ENTERPRISE_OIDC_CLIENT_ID "Enterprise OIDC client ID"
secret_prompt ENTERPRISE_OIDC_CLIENT_SECRET "Enterprise OIDC client secret"
prompt SMTP_FROM_ADDRESS "Verified SMTP/SES from address"
prompt BACKEND_BUCKET "Primary Terraform state bucket"
prompt BACKEND_KMS_KEY_ARN "Primary Terraform state KMS ARN"
BUCKET_PREFIX="${BUCKET_PREFIX:-nyc-taxi-${AWS_ACCOUNT_ID}-${ENVIRONMENT}}"

[[ "$BUDGET_USD" =~ ^[0-9]+$ ]] || { printf 'Budget must be a whole USD amount\n' >&2; exit 1; }
[[ "$ENVIRONMENT" != dev || "$BUDGET_USD" -le 300 ]] || { printf 'Dev budget exceeds USD 300\n' >&2; exit 1; }
[[ "$APP_DOMAIN" == *.* && "$APP_DOMAIN" != *"://"* && "$PRIMARY_ORIGIN" == *.* && "$PRIMARY_ORIGIN" != *"://"* ]] || {
  printf 'DNS names must be hostnames without schemes\n' >&2
  exit 1
}
[[ "$SMTP_FROM_ADDRESS" =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]] || { printf 'Invalid SMTP/SES from address\n' >&2; exit 1; }
if [[ "$ENVIRONMENT" == dev ]]; then date -d "$EXPIRES_AT" +%F >/dev/null 2>&1 || { printf 'Invalid dev expiry date\n' >&2; exit 1; }; fi

actual_account="$(aws sts get-caller-identity --query Account --output text)"
[[ "$actual_account" == "$AWS_ACCOUNT_ID" ]] || {
  printf 'AWS identity mismatch: expected %s, got %s\n' "$AWS_ACCOUNT_ID" "$actual_account" >&2
  exit 1
}

aws configure get region >/dev/null 2>&1 || true
aws ec2 describe-regions --region-names us-east-1 us-west-2 --query 'Regions[].RegionName' --output text >/dev/null
aws s3api head-bucket --bucket "$BACKEND_BUCKET"
[[ "$(aws kms describe-key --key-id "$BACKEND_KMS_KEY_ARN" --query 'KeyMetadata.Enabled' --output text)" == True ]] || {
  printf 'Terraform backend KMS key is not enabled\n' >&2
  exit 1
}

if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
  [[ "$GITHUB_REPOSITORY" == "$ACTIONS_REPOSITORY" ]] || {
    printf 'GitHub repository mismatch: expected %s, got %s\n' "$GITHUB_REPOSITORY" "$ACTIONS_REPOSITORY" >&2
    exit 1
  }
else
  command -v gh >/dev/null || { printf 'Missing required command: gh\n' >&2; exit 1; }
  for stage in plan apply destroy destroy-apply; do
    environment_json="$(gh api "repos/$GITHUB_REPOSITORY/environments/assignment-1-$ENVIRONMENT-$stage")" || {
      printf 'Missing/inaccessible GitHub environment: assignment-1-%s-%s\n' "$ENVIRONMENT" "$stage" >&2
      exit 1
    }
    if [[ "$stage" != plan ]]; then
      jq -e '.protection_rules | length > 0' >/dev/null <<<"$environment_json" || {
        printf 'GitHub environment lacks protection rules: assignment-1-%s-%s\n' "$ENVIRONMENT" "$stage" >&2
        exit 1
      }
    fi
  done
fi

CURL_CONFIG="$(mktemp)"
chmod 600 "$CURL_CONFIG"
printf 'header = "Authorization: Bearer %s"\n' "$CLOUDFLARE_API_TOKEN" >"$CURL_CONFIG"
zone_result="$(curl --fail --silent --show-error --config "$CURL_CONFIG" "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID")"
jq -e --arg account "$CLOUDFLARE_ACCOUNT_ID" '.success == true and .result.account.id == $account' >/dev/null <<<"$zone_result" || {
  printf 'Cloudflare token cannot read the requested zone/account\n' >&2
  exit 1
}
curl --fail --silent --show-error --config "$CURL_CONFIG" "https://api.cloudflare.com/client/v4/user/tokens/verify" | jq -e '.success == true and .result.status == "active"' >/dev/null || {
  printf 'Cloudflare token is not active\n' >&2
  exit 1
}
rm -f "$CURL_CONFIG"
CURL_CONFIG=""

if [[ "$NON_INTERACTIVE" == true ]]; then
  [[ "${CLOUD_COST_APPROVED:-false}" == true ]] || { printf 'Set CLOUD_COST_APPROVED=true after cost review\n' >&2; exit 1; }
  [[ "${CLOUD_PROTECTED_ENVIRONMENTS_CONFIRMED:-false}" == true ]] || { printf 'Set CLOUD_PROTECTED_ENVIRONMENTS_CONFIRMED=true after GitHub environment protection is configured\n' >&2; exit 1; }
else
  $GUM confirm "Budget is approved and GitHub plan/apply/destroy environments require reviewers?" || exit 1
fi

alert_emails_json="$(jq -Rn --arg value "$BUDGET_ALERT_EMAILS" '$value | split(",") | map(gsub("^\\s+|\\s+$"; ""))')"
jq -n \
  --arg owner "$OWNER" --arg cost_center "$COST_CENTER" --arg expires_at "$EXPIRES_AT" \
  --argjson budget_usd "$BUDGET_USD" --argjson budget_alert_emails "$alert_emails_json" \
  --arg aws_account_id "$AWS_ACCOUNT_ID" --arg bucket_prefix "$BUCKET_PREFIX" \
  --arg deployment_role_arn "$DEPLOYMENT_ROLE_ARN" \
  --arg cloudflare_api_token "$CLOUDFLARE_API_TOKEN" \
  --arg cloudflare_account_id "$CLOUDFLARE_ACCOUNT_ID" --arg cloudflare_zone_id "$CLOUDFLARE_ZONE_ID" \
  --arg app_domain "$APP_DOMAIN" --arg primary_origin "$PRIMARY_ORIGIN" --arg dr_origin "$DR_ORIGIN" \
  --arg issuer "$ENTERPRISE_OIDC_ISSUER" --arg client_id "$ENTERPRISE_OIDC_CLIENT_ID" --arg client_secret "$ENTERPRISE_OIDC_CLIENT_SECRET" \
  --arg smtp_from_address "$SMTP_FROM_ADDRESS" \
  '{aws_account_id:$aws_account_id,owner:$owner,cost_center:$cost_center,budget_usd:$budget_usd,budget_alert_emails:$budget_alert_emails,bucket_prefix:$bucket_prefix,deployment_role_arn:$deployment_role_arn,cloudflare_api_token:$cloudflare_api_token,cloudflare_account_id:$cloudflare_account_id,cloudflare_zone_id:$cloudflare_zone_id,app_domain:$app_domain,primary_origin:$primary_origin,enterprise_oidc:{issuer:$issuer,client_id:$client_id,client_secret:$client_secret,scopes:["openid","email","profile"]},cognito_callback_urls:[("https://"+$app_domain+"/oauth2/callback")],cognito_logout_urls:[("https://"+$app_domain+"/")],smtp_from_address:$smtp_from_address} + (if $expires_at != "" then {expires_at:$expires_at} else {} end) + (if $dr_origin != "" then {dr_origin:$dr_origin} else {} end)' \
  >"$AWS_DIR/cloud.auto.tfvars.json"
chmod 600 "$AWS_DIR/cloud.auto.tfvars.json"

cat >"$AWS_DIR/backend.hcl" <<EOF
bucket       = "$BACKEND_BUCKET"
key          = "assignment-1/$ENVIRONMENT/terraform.tfstate"
region       = "us-east-1"
use_lockfile = true
encrypt      = true
kms_key_id   = "$BACKEND_KMS_KEY_ARN"
EOF
chmod 600 "$AWS_DIR/backend.hcl"

printf 'GitHub secret commands (values are read from stdin):\n'
for stage in plan destroy; do
  printf '  gh secret set A1_CLOUDFLARE_API_TOKEN --env assignment-1-%s-%s\n' "$ENVIRONMENT" "$stage"
  printf '  gh secret set A1_ENTERPRISE_OIDC_CLIENT_SECRET --env assignment-1-%s-%s\n' "$ENVIRONMENT" "$stage"
done
if [[ "$WRITE_GITHUB" == true ]]; then
  command -v gh >/dev/null || { printf 'gh is required to write secrets\n' >&2; exit 1; }
  if [[ "$ASSUME_YES" == true ]] || [[ "$NON_INTERACTIVE" == false && "$($GUM confirm 'Write secrets to GitHub protected environment?' && printf yes || printf no)" == yes ]]; then
    for stage in plan destroy; do
      github_environment="assignment-1-${ENVIRONMENT}-${stage}"
      printf '%s' "$CLOUDFLARE_API_TOKEN" | gh secret set A1_CLOUDFLARE_API_TOKEN --env "$github_environment"
      printf '%s' "$ENTERPRISE_OIDC_CLIENT_SECRET" | gh secret set A1_ENTERPRISE_OIDC_CLIENT_SECRET --env "$github_environment"
    done
  fi
fi

printf 'Wrote %s and %s (mode 0600). No plan/apply executed.\n' "$AWS_DIR/cloud.auto.tfvars.json" "$AWS_DIR/backend.hcl"
printf 'Manual setup: https://docs.github.com/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services\n'
printf 'Cloudflare token: https://developers.cloudflare.com/fundamentals/api/get-started/create-token/\n'
printf 'IAM Identity Center: https://docs.aws.amazon.com/singlesignon/latest/userguide/getting-started.html\n'
if [[ "$OPEN_DOCS" == true ]] && command -v xdg-open >/dev/null; then
  xdg-open "https://docs.github.com/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services" >/dev/null 2>&1 || true
  xdg-open "https://developers.cloudflare.com/fundamentals/api/get-started/create-token/" >/dev/null 2>&1 || true
fi
