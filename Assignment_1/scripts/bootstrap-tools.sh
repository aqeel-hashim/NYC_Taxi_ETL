#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ASSIGNMENT_DIR="${REPO_ROOT}/Assignment_1"
TOOLS_DIR="${ASSIGNMENT_DIR}/.tools"
SCRIPT_DIR="${ASSIGNMENT_DIR}/scripts"
LIB_DIR="${SCRIPT_DIR}/lib"

mkdir -p "${TOOLS_DIR}" "${LIB_DIR}"

source "${LIB_DIR}/logging.sh"

bootstrap_tool() {
    local name="$1"
    local version="$2"
    local url="$3"
    local binary="$4"

    if command -v "${name}" &>/dev/null && [[ "$("${name}" --version 2>/dev/null | head -1)" == *"${version}"* ]]; then
        log_info "${name} ${version} already available"
        return 0
    fi

    log_info "Downloading ${name} ${version}..."
    # ponytail: single-arch download, add arch detection when needed
    curl -fsSL "${url}" -o "${TOOLS_DIR}/${binary}"
    chmod +x "${TOOLS_DIR}/${binary}"
    log_info "Installed ${name} ${version} to ${TOOLS_DIR}/${binary}"
}

log_info "Bootstrapping tools..."
log_info "Target directory: ${TOOLS_DIR}"

# uv is expected system-installed; check it exists
# uv for python and python tooling locking
if ! command -v uv &>/dev/null; then
    log_error "uv not found. Install: curl -LsSf https://astral.sh/uv/install.sh | sh"
    exit 1
fi
log_info "uv $(uv --version)"

# kind
# Decided on kind of k3s. Kins better for local docker first testing purposes
bootstrap_tool "kind" "0.27" \
    "https://kind.sigs.k8s.io/dl/v0.27.0/kind-linux-amd64" \
    "kind"

# kubectl
bootstrap_kubectl() {
    local version="v1.32.3"
    if command -v kubectl &>/dev/null && kubectl version --client --short 2>/dev/null | grep -q "${version}"; then
        log_info "kubectl ${version} already available"
        return 0
    fi
    curl -fsSL "https://dl.k8s.io/release/${version}/bin/linux/amd64/kubectl" -o "${TOOLS_DIR}/kubectl"
    chmod +x "${TOOLS_DIR}/kubectl"
    log_info "kubectl ${version} installed"
}
bootstrap_kubectl

# helm
# Helm for image and helm chart locking
bootstrap_helm() {
    local version="v3.17.1"
    if command -v helm &>/dev/null && helm version --short 2>/dev/null | grep -q "${version}"; then
        log_info "helm ${version} already available"
        return 0
    fi
    local archive="helm-${version}-linux-amd64.tar.gz"
    curl -fsSL "https://get.helm.sh/${archive}" -o "/tmp/${archive}"
    tar -xzf "/tmp/${archive}" -C "${TOOLS_DIR}" linux-amd64/helm --strip-components=1
    rm -f "/tmp/${archive}"
    log_info "helm ${version} installed"
}
bootstrap_helm

# gum
# Gum tool for pretty CLI shit
bootstrap_tool "gum" "0.18" \
    "https://github.com/charmbracelet/gum/releases/download/v0.18.0/gum_0.18.0_linux_amd64.tar.gz" \
    "gum.tar.gz"
if [[ -x "${TOOLS_DIR}/gum" ]]; then
    :
elif [[ -f "${TOOLS_DIR}/gum.tar.gz" ]]; then
    tar -xzf "${TOOLS_DIR}/gum.tar.gz" -C "${TOOLS_DIR}" gum 2>/dev/null || true
    rm -f "${TOOLS_DIR}/gum.tar.gz"
fi

# mkcert
# for TLS Certificates to get browsers to shut up over https pages, and to implement proper tls support
# via kubectl
bootstrap_tool "mkcert" "1.4" \
    "https://github.com/FiloSottile/mkcert/releases/download/v1.4.4/mkcert-v1.4.4-linux-amd64" \
    "mkcert"

export PATH="${TOOLS_DIR}:${PATH}"

log_info "Tool bootstrap complete."
log_info "Add to PATH: export PATH=\"${TOOLS_DIR}:\$PATH\""
