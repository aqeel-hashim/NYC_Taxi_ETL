#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/lib/logging.sh"

PROFILE=core
OFFLINE=false

usage() {
  cat <<'EOF'
Usage: ./scripts/bootstrap-tools.sh [--profile uv|core|all] [--offline] [--help]
EOF
}

while (($#)); do
  case "$1" in
    --profile) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; PROFILE="$2"; shift 2 ;;
    --offline) OFFLINE=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done
[[ "${PROFILE}" == uv || "${PROFILE}" == core || "${PROFILE}" == all ]] || { usage >&2; exit 2; }

case "$(uname -m)" in
  x86_64) ARCH=amd64; GO_ARCH=amd64; RUST_ARCH=x86_64 ;;
  aarch64|arm64) ARCH=arm64; GO_ARCH=arm64; RUST_ARCH=aarch64 ;;
  *) log_error "Unsupported architecture: $(uname -m)"; exit 1 ;;
esac
[[ "$(uname -s)" == Linux ]] || { log_error "Only Linux and WSL2 are supported"; exit 1; }

BIN_DIR="${ROOT_DIR}/.tools/bin"
CACHE_DIR="${ROOT_DIR}/.tools/cache/downloads"
export UV_CACHE_DIR="${ROOT_DIR}/.tools/cache/uv"
export UV_TOOL_DIR="${ROOT_DIR}/.tools/uv-tools"
export UV_PYTHON_INSTALL_DIR="${ROOT_DIR}/.tools/python"
export PUPPETEER_CACHE_DIR="${ROOT_DIR}/.tools/cache/puppeteer"
mkdir -p "${BIN_DIR}" "${CACHE_DIR}"

download() {
  local url="$1" destination="$2"
  [[ -s "${destination}" ]] && return 0
  [[ "${OFFLINE}" == false ]] || { log_error "Offline tool cache miss: ${destination}"; return 1; }
  curl --fail --location --retry 5 --retry-all-errors \
    --connect-timeout 15 --speed-limit 1024 --speed-time 30 --continue-at - \
    "${url}" --output "${destination}.part"
  mv "${destination}.part" "${destination}"
}

verified_download() {
  local url="$1" checksum_url="$2"
  local asset="${CACHE_DIR}/${url##*/}"
  local checksums="${asset}.checksums"
  download "${url}" "${asset}"

  local expected actual filename
  filename="${asset##*/}"
  if [[ "${checksum_url}" == sha256:* ]]; then
    expected="${checksum_url#sha256:}"
  else
    download "${checksum_url}" "${checksums}"
    expected="$(awk -v filename="${filename}" '
      NF == 1 && $1 ~ /^[0-9a-fA-F]{64}$/ { print $1; exit }
      { name=$2; sub(/^\*/, "", name); if (name == filename) { print $1; exit } }
    ' "${checksums}")"
  fi
  [[ "${expected}" =~ ^[0-9a-fA-F]{64}$ ]] || { log_error "No published checksum for ${filename}"; return 1; }
  actual="$(sha256sum "${asset}" | awk '{print $1}')"
  if [[ "${actual,,}" != "${expected,,}" ]]; then
    rm -f "${asset}"
    log_error "Checksum mismatch: ${filename}"
    return 1
  fi
  printf '%s\n' "${asset}"
}

install_release() {
  local name="$1" url="$2" checksum_url="$3"
  local asset temporary candidate
  asset="$(verified_download "${url}" "${checksum_url}")"
  temporary="${CACHE_DIR}/extract-${name}"
  rm -rf "${temporary}"
  mkdir -p "${temporary}"
  case "${asset}" in
    *.tar.gz|*.tgz) tar -xzf "${asset}" -C "${temporary}" ;;
    *.zip)
      command -v unzip >/dev/null 2>&1 || { log_error "unzip is required for ${name}"; return 1; }
      unzip -q "${asset}" -d "${temporary}"
      ;;
    *) cp "${asset}" "${temporary}/${name}" ;;
  esac
  candidate="$(find "${temporary}" -type f \( -name "${name}" -o -name "${name}-linux-${ARCH}" \) -print -quit)"
  [[ -n "${candidate}" ]] || { log_error "Binary ${name} missing from ${asset##*/}"; return 1; }
  install -m 0755 "${candidate}" "${BIN_DIR}/${name}"
  rm -rf "${temporary}"
  log_success "Installed ${name}"
}

install_uv() {
  local version=0.8.3 target="${RUST_ARCH}-unknown-linux-gnu"
  if [[ -x "${BIN_DIR}/uv" ]] && "${BIN_DIR}/uv" --version 2>/dev/null | grep -Fxq "uv ${version}"; then
    log_success "uv ${version} already installed"
    return
  fi
  install_release uv \
    "https://github.com/astral-sh/uv/releases/download/${version}/uv-${target}.tar.gz" \
    "https://github.com/astral-sh/uv/releases/download/${version}/uv-${target}.tar.gz.sha256"
}

install_node() {
  local node_arch=x64
  [[ "${ARCH}" == arm64 ]] && node_arch=arm64
  local version=22.14.0
  local archive="node-v${version}-linux-${node_arch}.tar.gz"
  local asset
  asset="$(verified_download \
    "https://nodejs.org/dist/v${version}/${archive}" \
    "https://nodejs.org/dist/v${version}/SHASUMS256.txt")"
  rm -rf "${ROOT_DIR}/.tools/node"
  mkdir -p "${ROOT_DIR}/.tools/node"
  tar -xzf "${asset}" --strip-components=1 -C "${ROOT_DIR}/.tools/node"
}

install_core() {
  install_uv
  install_release kind \
    "https://kind.sigs.k8s.io/dl/v0.27.0/kind-linux-${GO_ARCH}" \
    "https://kind.sigs.k8s.io/dl/v0.27.0/kind-linux-${GO_ARCH}.sha256sum"
  install_release kubectl \
    "https://dl.k8s.io/release/v1.32.1/bin/linux/${GO_ARCH}/kubectl" \
    "https://dl.k8s.io/release/v1.32.1/bin/linux/${GO_ARCH}/kubectl.sha256"
  install_release helm \
    "https://get.helm.sh/helm-v3.17.0-linux-${GO_ARCH}.tar.gz" \
    "https://get.helm.sh/helm-v3.17.0-linux-${GO_ARCH}.tar.gz.sha256sum"
  install_release helmfile \
    "https://github.com/helmfile/helmfile/releases/download/v0.171.0/helmfile_0.171.0_linux_${GO_ARCH}.tar.gz" \
    "https://github.com/helmfile/helmfile/releases/download/v0.171.0/helmfile_0.171.0_checksums.txt"

  local charm_arch="${ARCH}"
  [[ "${ARCH}" == amd64 ]] && charm_arch=x86_64
  install_release gum \
    "https://github.com/charmbracelet/gum/releases/download/v0.14.5/gum_0.14.5_Linux_${charm_arch}.tar.gz" \
    "https://github.com/charmbracelet/gum/releases/download/v0.14.5/checksums.txt"
  local mkcert_checksum=sha256:b98f2cc69fd9147fe4d405d859c57504571adec0d3611c3eefd04107c7ac00d0
  [[ "${ARCH}" == amd64 ]] && mkcert_checksum=sha256:6d31c65b03972c6dc4a14ab429f2928300518b26503f58723e532d1b0a3bbb52
  install_release mkcert \
    "https://github.com/FiloSottile/mkcert/releases/download/v1.4.4/mkcert-v1.4.4-linux-${ARCH}" \
    "${mkcert_checksum}"
}

install_all() {
  local trivy_arch=64bit
  [[ "${ARCH}" == arm64 ]] && trivy_arch=ARM64
  local cloudflared_checksum=sha256:405df476437e027fc6d18729a5a77155c0a33a6082aeee60a799a688f3052e66
  [[ "${ARCH}" == amd64 ]] && cloudflared_checksum=sha256:ec905ea7b7e327ff8abdde8cb64697a2152de74dbcdbf6aec9db8364eb3886cd
  install_release terraform \
    "https://releases.hashicorp.com/terraform/1.10.5/terraform_1.10.5_linux_${ARCH}.zip" \
    "https://releases.hashicorp.com/terraform/1.10.5/terraform_1.10.5_SHA256SUMS"
  install_release tflint \
    "https://github.com/terraform-linters/tflint/releases/download/v0.55.1/tflint_linux_${ARCH}.zip" \
    "https://github.com/terraform-linters/tflint/releases/download/v0.55.1/checksums.txt"
  install_release infracost \
    "https://github.com/infracost/infracost/releases/download/v0.10.40/infracost-linux-${ARCH}.tar.gz" \
    "https://github.com/infracost/infracost/releases/download/v0.10.40/infracost-linux-${ARCH}.tar.gz.sha256"
  install_release cloudflared \
    "https://github.com/cloudflare/cloudflared/releases/download/2026.7.2/cloudflared-linux-${ARCH}" \
    "${cloudflared_checksum}"
  install_release trivy \
    "https://github.com/aquasecurity/trivy/releases/download/v0.72.0/trivy_0.72.0_Linux-${trivy_arch}.tar.gz" \
    "https://github.com/aquasecurity/trivy/releases/download/v0.72.0/trivy_0.72.0_checksums.txt"
  install_release syft \
    "https://github.com/anchore/syft/releases/download/v1.20.0/syft_1.20.0_linux_${ARCH}.tar.gz" \
    "https://github.com/anchore/syft/releases/download/v1.20.0/syft_1.20.0_checksums.txt"
  install_release cosign \
    "https://github.com/sigstore/cosign/releases/download/v2.4.1/cosign-linux-${ARCH}" \
    "https://github.com/sigstore/cosign/releases/download/v2.4.1/cosign_checksums.txt"

  local gh_arch="${ARCH}"
  [[ "${ARCH}" == amd64 ]] && gh_arch=amd64
  install_release gh \
    "https://github.com/cli/cli/releases/download/v2.65.0/gh_2.65.0_linux_${gh_arch}.tar.gz" \
    "https://github.com/cli/cli/releases/download/v2.65.0/gh_2.65.0_checksums.txt"

  local uv_args=(tool install --python 3.12)
  [[ "${OFFLINE}" == true ]] && uv_args+=(--offline)
  UV_TOOL_BIN_DIR="${BIN_DIR}" "${BIN_DIR}/uv" "${uv_args[@]}" checkov==3.3.8
  UV_TOOL_BIN_DIR="${BIN_DIR}" "${BIN_DIR}/uv" "${uv_args[@]}" awscli==1.45.52

  install_node
  local npm_args=(install --cache "${ROOT_DIR}/.tools/cache/npm" --prefix "${ROOT_DIR}/.tools/mermaid" @mermaid-js/mermaid-cli@11.4.2)
  [[ "${OFFLINE}" == true ]] && npm_args+=(--offline)
  "${ROOT_DIR}/.tools/node/bin/npm" "${npm_args[@]}"
  ln -sfn "${ROOT_DIR}/.tools/mermaid/node_modules/.bin/mmdc" "${BIN_DIR}/mmdc"
}

if [[ "${PROFILE}" == uv ]]; then
  install_uv
else
  install_core
  [[ "${PROFILE}" == core ]] || install_all
fi
log_success "${PROFILE} tool profile ready under ${ROOT_DIR}/.tools"
