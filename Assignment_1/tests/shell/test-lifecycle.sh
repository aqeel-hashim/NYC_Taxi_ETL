#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_help() {
  local script="$1"
  local output
  output="$(${ROOT_DIR}/${script} --help)"
  grep -q -- '--help' <<<"${output}" || fail "${script} help omits --help"
}

assert_help setup.sh
assert_help teardown.sh
assert_help scripts/bootstrap-tools.sh
assert_help scripts/build-images.sh
assert_help scripts/demo.sh
assert_help scripts/local-demo.sh
assert_help scripts/build-release-zip.sh
assert_help scripts/measure-resources.sh

setup_help="$(${ROOT_DIR}/setup.sh --help)"
for flag in --profile --tools --from --only --offline --allow-synthetic-fallback --non-interactive --local-demo; do
  grep -q -- "${flag}" <<<"${setup_help}" || fail "setup help omits ${flag}"
done

if "${ROOT_DIR}/setup.sh" --profile impossible --only preflight >/dev/null 2>&1; then
  fail "setup accepted invalid profile"
fi

if "${ROOT_DIR}/setup.sh" --only impossible >/dev/null 2>&1; then
  fail "setup accepted invalid stage"
fi

if "${ROOT_DIR}/teardown.sh" --purge-all --non-interactive >/dev/null 2>&1; then
  fail "non-interactive purge succeeded without --yes"
fi

printf 'lifecycle shell tests passed\n'
