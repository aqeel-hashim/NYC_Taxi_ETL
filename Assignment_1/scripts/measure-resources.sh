#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE=auto
HOST_LABEL="${MACHINE_PROFILE:-unclassified}"
OUTPUT=""
SAMPLES=6
INTERVAL=10

usage() {
  cat <<'EOF'
Usage: ./scripts/measure-resources.sh [--profile staged|concurrent|auto]
                                      [--host-label smallpc|bigpc|unclassified]
                                      [--output FILE] [--samples N]
                                      [--interval SECONDS] [--help]

Records live Docker limits, container usage, Kubernetes requests/limits, and
pod usage. Default output: docs/evidence/resources-PROFILE-TIMESTAMP.txt.
EOF
}

while (($#)); do
  case "$1" in
    --profile) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; PROFILE="$2"; shift 2 ;;
    --host-label) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; HOST_LABEL="$2"; shift 2 ;;
    --output) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; OUTPUT="$2"; shift 2 ;;
    --samples) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; SAMPLES="$2"; shift 2 ;;
    --interval) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; INTERVAL="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done
[[ "${PROFILE}" == auto || "${PROFILE}" == staged || "${PROFILE}" == concurrent ]] || { usage >&2; exit 2; }
[[ "${HOST_LABEL}" == smallpc || "${HOST_LABEL}" == bigpc || "${HOST_LABEL}" == unclassified ]] || { usage >&2; exit 2; }
[[ "${SAMPLES}" =~ ^[1-9][0-9]*$ && "${INTERVAL}" =~ ^[0-9]+$ ]] || { usage >&2; exit 2; }
command -v docker >/dev/null 2>&1 || { printf 'Docker is required\n' >&2; exit 1; }
docker info >/dev/null 2>&1 || { printf 'Docker daemon is not reachable\n' >&2; exit 1; }
docker_memory_bytes="$(docker info --format '{{.MemTotal}}')"

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
if [[ -z "${OUTPUT}" ]]; then
  OUTPUT="${ROOT_DIR}/docs/evidence/resources-${HOST_LABEL}-${PROFILE}-${timestamp}.txt"
elif [[ "${OUTPUT}" != /* ]]; then
  OUTPUT="${ROOT_DIR}/${OUTPUT}"
fi
mkdir -p "$(dirname "${OUTPUT}")"

{
  printf 'captured_at=%s\n' "$(date -Iseconds)"
  printf 'profile=%s\n' "${PROFILE}"
  printf 'host_label=%s\n' "${HOST_LABEL}"
  printf 'host_kernel=%s\n' "$(uname -srmo)"
  printf 'docker_cpus=%s\n' "$(docker info --format '{{.NCPU}}')"
  printf 'docker_memory_bytes=%s\n' "${docker_memory_bytes}"
  printf 'docker_storage_driver=%s\n' "$(docker info --format '{{.Driver}}')"
  printf '\n[container_usage]\n'
  docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}'
  container_memory_bytes="$(docker stats --no-stream --format '{{.MemUsage}}' | awk '
    function bytes(v) {
      if (v ~ /KiB$/) { sub(/KiB$/, "", v); return v * 1024 }
      if (v ~ /MiB$/) { sub(/MiB$/, "", v); return v * 1048576 }
      if (v ~ /GiB$/) { sub(/GiB$/, "", v); return v * 1073741824 }
      if (v ~ /kB$/) { sub(/kB$/, "", v); return v * 1000 }
      if (v ~ /MB$/) { sub(/MB$/, "", v); return v * 1000000 }
      if (v ~ /GB$/) { sub(/GB$/, "", v); return v * 1000000000 }
      return v + 0
    }
    { total += bytes($1) }
    END { printf "%.0f\n", total }
  ')"
  printf 'container_usage_memory_bytes=%s\n' "${container_memory_bytes}"
  awk -v total="${docker_memory_bytes}" -v used="${container_memory_bytes}" \
    'BEGIN { printf "docker_memory_headroom_percent=%.2f\n", (total - used) * 100 / total }'

  if command -v kubectl >/dev/null 2>&1 && kubectl cluster-info >/dev/null 2>&1; then
    printf '\n[pod_requests_limits]\n'
    kubectl get pods --all-namespaces -o custom-columns='NAMESPACE:.metadata.namespace,POD:.metadata.name,CONTAINER:.spec.containers[*].name,CPU_REQUEST:.spec.containers[*].resources.requests.cpu,MEMORY_REQUEST:.spec.containers[*].resources.requests.memory,CPU_LIMIT:.spec.containers[*].resources.limits.cpu,MEMORY_LIMIT:.spec.containers[*].resources.limits.memory'
    printf '\n[pod_usage_samples]\n'
    peak_cpu=0
    peak_memory=0
    collected_samples=0
    metrics_available=false
    for ((sample = 1; sample <= SAMPLES; sample++)); do
      pod_usage="$(kubectl top pods --all-namespaces --containers --no-headers 2>/dev/null || true)"
      if [[ -n "${pod_usage}" ]]; then
        metrics_available=true
        collected_samples=$((collected_samples + 1))
        printf 'sample=%d captured_at=%s\n%s\n' "${sample}" "$(date -Iseconds)" "${pod_usage}"
        read -r sample_cpu sample_memory < <(awk '
        function cpu_millicores(v) {
          if (v ~ /m$/) { sub(/m$/, "", v); return v + 0 }
          return (v + 0) * 1000
        }
        function memory_bytes(v) {
          if (v ~ /Ki$/) { sub(/Ki$/, "", v); return v * 1024 }
          if (v ~ /Mi$/) { sub(/Mi$/, "", v); return v * 1048576 }
          if (v ~ /Gi$/) { sub(/Gi$/, "", v); return v * 1073741824 }
          return v + 0
        }
        { cpu += cpu_millicores($4); memory += memory_bytes($5) }
        END { printf "%.0f %.0f\n", cpu, memory }
        ' <<<"${pod_usage}")
        ((sample_cpu > peak_cpu)) && peak_cpu="${sample_cpu}"
        ((sample_memory > peak_memory)) && peak_memory="${sample_memory}"
      else
        break
      fi
      ((sample == SAMPLES)) || sleep "${INTERVAL}"
    done
    if [[ "${metrics_available}" == true ]]; then
      printf '\n[pod_usage_peak_totals]\n'
      printf 'samples=%s\n' "${collected_samples}"
      printf 'interval_seconds=%s\n' "${INTERVAL}"
      printf 'peak_cpu_millicores=%s\n' "${peak_cpu}"
      printf 'peak_memory_bytes=%s\n' "${peak_memory}"
      awk -v total="${docker_memory_bytes}" -v used="${peak_memory}" \
        'BEGIN { printf "pod_memory_headroom_percent=%.2f\n", (total - used) * 100 / total }'
    else
      printf 'metrics API unavailable\n'
    fi
  else
    printf '\n[kubernetes]\ncluster unavailable\n'
  fi
} >"${OUTPUT}"

printf '%s\n' "${OUTPUT}"
if ! awk -v total="${docker_memory_bytes}" -v used="${container_memory_bytes}" \
  'BEGIN { exit !((total - used) / total >= 0.20) }'; then
  printf 'Docker memory headroom below 20%%; concurrent/staged claim blocked. Use stage-by-stage evidence.\n' >&2
  exit 3
fi
