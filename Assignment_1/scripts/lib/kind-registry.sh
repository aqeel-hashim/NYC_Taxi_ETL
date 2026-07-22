#!/usr/bin/env bash

KIND_REGISTRY_NAME="${KIND_REGISTRY_NAME:-kind-registry}"
KIND_REGISTRY_PORT="${KIND_REGISTRY_PORT:-5001}"
CRANE_IMAGE="gcr.io/go-containerregistry/crane@sha256:54b27703e6c602fbd6f95712910e9c8d45d4361a59274bde38aeec943734e424"

kind_registry_start() {
  if docker container inspect "${KIND_REGISTRY_NAME}" >/dev/null 2>&1; then
    docker start "${KIND_REGISTRY_NAME}" >/dev/null
  else
    docker run -d --restart=always -p "127.0.0.1:${KIND_REGISTRY_PORT}:5000" \
      --name "${KIND_REGISTRY_NAME}" registry:2 >/dev/null
  fi
}

kind_registry_connect() {
  if ! docker inspect -f '{{json .NetworkSettings.Networks.kind}}' \
    "${KIND_REGISTRY_NAME}" 2>/dev/null | grep -Fq '"NetworkID"'; then
    docker network connect kind "${KIND_REGISTRY_NAME}"
  fi
}

kind_registry_path() {
  local image="$1" path
  path="${image#docker.io/}"
  path="${path#quay.io/}"
  path="${path#ghcr.io/}"
  path="${path#registry.k8s.io/}"
  [[ "${path}" == */* ]] || path="library/${path}"
  printf '%s\n' "${path}"
}

kind_registry_mirror() {
  local image="$1" target
  target="localhost:${KIND_REGISTRY_PORT}/$(kind_registry_path "${image}")"
  docker run --rm --network host "${CRANE_IMAGE}" copy --platform linux/amd64 \
    "${image}" "${target}"
}

kind_registry_push() {
  local image="$1" target
  target="localhost:${KIND_REGISTRY_PORT}/$(kind_registry_path "${image}")"
  docker tag "${image}" "${target}"
  docker push "${target}"
}
