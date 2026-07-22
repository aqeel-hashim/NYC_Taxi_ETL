#!/usr/bin/env bash
set -euo pipefail

# Deploy local Kubernetes platform for Assignment 1
# Prerequisites: Docker, kind, kubectl, helm

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
INFRA_DIR="$ROOT_DIR/infra/local"
CLUSTER_NAME="nyc-taxi-etl"
source "$SCRIPT_DIR/lib/kind-registry.sh"

echo "=== Checking prerequisites ==="
for cmd in docker kind kubectl helm; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "Missing: $cmd"; exit 1; }
done

echo "=== Creating kind cluster ==="
kind_registry_start
kind create cluster --name "$CLUSTER_NAME" --config "$INFRA_DIR/kind.yaml" --wait 120s
kind_registry_connect

echo "=== Installing Calico ==="
for image in \
    quay.io/tigera/operator:v1.36.2 \
    docker.io/calico/kube-controllers:v3.29.1 \
    docker.io/calico/pod2daemon-flexvol:v3.29.1 \
    docker.io/calico/cni:v3.29.1 \
    docker.io/calico/node:v3.29.1 \
    docker.io/calico/typha:v3.29.1 \
    docker.io/calico/csi:v3.29.1 \
    docker.io/calico/node-driver-registrar:v3.29.1; do
    kind_registry_mirror "$image"
done
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.29.1/manifests/tigera-operator.yaml
kubectl wait --namespace tigera-operator --for=condition=available --timeout=120s deployment/tigera-operator
cat <<EOF | kubectl apply -f -
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  calicoNetwork:
    ipPools:
    - blockSize: 26
      cidr: 10.244.0.0/16
      encapsulation: VXLANCrossSubnet
      natOutgoing: Enabled
      nodeSelector: all()
EOF
echo "   Waiting for calico-system namespace..." && \
for i in $(seq 1 30); do kubectl get ns calico-system >/dev/null 2>&1 && break; sleep 2; done
kubectl wait --namespace calico-system --for=condition=available --timeout=180s --all deployments
kubectl wait --namespace tigera-operator --for=condition=available --timeout=60s deployment/tigera-operator

echo "=== Creating namespaces ==="
for ns in ingress identity monitoring data-platform taxi-app; do
    kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
done

echo "=== Generating Phase 8 security material and Secrets ==="
"$SCRIPT_DIR/deploy-phase8.sh" --secrets-only

echo "=== Installing local-path provisioner ==="
kind_registry_mirror docker.io/rancher/local-path-provisioner:v0.0.30
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.30/deploy/local-path-storage.yaml
kubectl wait --namespace local-path-storage --for=condition=available --timeout=60s --all deployments

echo "=== Installing Phase 8 ingress and identity ==="
"$SCRIPT_DIR/deploy-phase8.sh" --identity-only

echo "=== Installing CloudNativePG operator ==="
kind_registry_mirror ghcr.io/cloudnative-pg/cloudnative-pg:1.25.1
helm upgrade --install cnpg \
    --namespace data-platform \
    --create-namespace \
    --repo https://cloudnative-pg.github.io/charts \
    cloudnative-pg \
    --version 0.23.2 \
    --wait \
    --timeout 5m

echo "=== Creating CNPG cluster ==="
kind_registry_mirror ghcr.io/cloudnative-pg/postgresql:17.4
kubectl apply -f "$INFRA_DIR/values/cnpg-cluster.yaml"
echo "   Waiting for CNPG instance... (may take 2-3 minutes pulling PG image)"
kubectl wait --namespace data-platform --for=condition=ready --timeout=300s pod -l cnpg.io/cluster=taxi-warehouse,cnpg.io/podRole=instance

echo "=== Installing MinIO ==="
kind_registry_mirror quay.io/minio/minio:RELEASE.2024-12-18T13-15-44Z
kind_registry_mirror quay.io/minio/mc:RELEASE.2024-11-21T17-21-54Z
helm upgrade --install minio \
    --namespace data-platform \
    --repo https://charts.min.io/ \
    minio \
    --version 5.4.0 \
    --values "$INFRA_DIR/values/minio.yaml" \
    --wait \
    --timeout 5m

echo "=== Building Airflow image ==="
docker build -t taxi-airflow:latest \
    -f "$ROOT_DIR/docker/airflow.Dockerfile" \
    "$ROOT_DIR"
kind_registry_push taxi-airflow:latest
kind_registry_mirror quay.io/prometheus/statsd-exporter:v0.26.1

echo "=== Installing Airflow ==="
helm upgrade --install airflow \
    --namespace data-platform \
    --repo https://airflow.apache.org \
    airflow \
    --version 1.15.0 \
    --values "$INFRA_DIR/values/airflow.yaml" \
    --wait \
    --timeout 10m

echo "=== Installing Phase 8 ingress, identity, alerts, and policies ==="
"$SCRIPT_DIR/deploy-phase8.sh" --finish

echo "=== Setup complete ==="
kubectl get pods --all-namespaces
echo ""
echo "Access Airflow: https://airflow.taxi.localhost:8443"
echo "Access MinIO:   https://minio.taxi.localhost:8443"
echo "Access Mailpit: https://mailpit.taxi.localhost:8443"
