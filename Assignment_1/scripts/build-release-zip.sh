#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="$(git -C "${ROOT_DIR}" rev-parse --show-toplevel)"
VERSION="${1:-v0.1.0}"
if [[ "${VERSION}" == -h || "${VERSION}" == --help ]]; then
  printf 'Usage: ./scripts/build-release-zip.sh [vMAJOR.MINOR.PATCH] [--help]\n'
  exit 0
fi
[[ "${VERSION}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  printf 'Usage: ./scripts/build-release-zip.sh [vMAJOR.MINOR.PATCH]\n' >&2
  exit 2
}
[[ -z "$(git -C "${REPO_DIR}" status --porcelain)" ]] || {
  printf 'Release archive requires a clean committed worktree\n' >&2
  exit 1
}

mkdir -p "${ROOT_DIR}/dist"
archive="${ROOT_DIR}/dist/Assignment_1-${VERSION}.zip"
rm -f "${archive}" "${archive}.sha256"
git -C "${REPO_DIR}" archive --format=zip --prefix=Assignment_1/ \
  --output="${archive}" HEAD:Assignment_1

python_bin="${ROOT_DIR}/.venv/bin/python"
[[ -x "${python_bin}" ]] || python_bin=python3
"${python_bin}" - "${archive}" <<'PY'
import re
import sys
import zipfile

archive = sys.argv[1]
forbidden = re.compile(
    r"(^|/)(\.env$|\.venv/|\.tools/|\.local/|artifacts/|dist/|__pycache__/|\.terraform/)|"
    r"^Assignment_1/data/|"
    r"\.(pem|key|crt|pyc)$|credentials\.env$"
)
required = {
    "Assignment_1/README.md",
    "Assignment_1/setup.sh",
    "Assignment_1/uv.lock",
    "Assignment_1/sql/schema.sql",
    "Assignment_1/dashboard/app.py",
    "Assignment_1/dashboard/data/taxi_zones.geojson",
    "Assignment_1/docs/images/dashboard-desktop.png",
    "Assignment_1/docs/images/dashboard-mobile.png",
}
with zipfile.ZipFile(archive) as bundle:
    names = set(bundle.namelist())
bad = sorted(name for name in names if forbidden.search(name))
missing = sorted(required - names)
if bad or missing:
    raise SystemExit(f"invalid release archive: forbidden={bad}, missing={missing}")
print(f"Release ZIP verified: {len(names)} entries")
PY
(
  cd "${ROOT_DIR}/dist"
  sha256sum "${archive##*/}" >"${archive##*/}.sha256"
)
printf '%s\n%s\n' "${archive}" "${archive}.sha256"
