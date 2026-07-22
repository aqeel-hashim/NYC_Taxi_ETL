#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PROFILE=auto
TOOLS=core
OFFLINE=false
NON_INTERACTIVE=false

usage() {
  cat <<'EOF'
Usage: ./scripts/demo.sh [--profile auto|staged|concurrent] [--tools core|all]
                         [--offline] [--non-interactive] [--help]

Resumes lifecycle at calibration, runs both monthly ETLs, starts presentation,
runs acceptance, and records resource evidence.
EOF
}

while (($#)); do
  case "$1" in
    --profile) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; PROFILE="$2"; shift 2 ;;
    --tools) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; TOOLS="$2"; shift 2 ;;
    --offline) OFFLINE=true; shift ;;
    --non-interactive) NON_INTERACTIVE=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

args=(--from calibration --profile "${PROFILE}" --tools "${TOOLS}")
[[ "${OFFLINE}" == false ]] || args+=(--offline)
[[ "${NON_INTERACTIVE}" == false ]] || args+=(--non-interactive)
exec "${ROOT_DIR}/setup.sh" "${args[@]}"
