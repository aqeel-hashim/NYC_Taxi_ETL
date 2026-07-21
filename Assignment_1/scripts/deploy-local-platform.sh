#!/usr/bin/env bash
set -euo pipefail

# Deploy local Kubernetes platform for Assignment 1
# Prerequisites: Docker, kind, kubectl, helm

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
INFRA_DIR="$ROOT_DIR/infra/local"
CLUSTER_NAME="nyc-taxi-etl"

echo "=== Checking prerequisites ==="
for cmd in docker kind kubectl helm; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "Missing: $cmd"; exit 1; }
done

echo "=== Creating kind cluster ==="
kind create cluster --name "$CLUSTER_NAME" --config "$INFRA_DIR/kind.yaml" --wait 120s

echo "=== Installing Calico ==="
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
kubectl wait --namespace calico-system --for=condition=available --timeout=180s --all deployments

echo "=== Creating namespaces ==="
for ns in ingress identity monitoring data-platform taxi-app; do
    kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
done

echo "=== Installing local-path provisioner ==="
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.30/deploy/local-path-storage.yaml
kubectl wait --namespace local-path-storage --for=condition=available --timeout=60s --all deployments

echo "=== Installing CloudNativePG operator ==="
helm upgrade --install cnpg \
    --namespace data-platform \
    --create-namespace \
    --repo https://cloudnative-pg.github.io/charts \
    cloudnative-pg \
    --version 0.23.2 \
    --wait \
    --timeout 5m

echo "=== Creating CNPG cluster ==="
kubectl apply -f "$INFRA_DIR/values/cnpg-cluster.yaml"
kubectl wait --namespace data-platform --for=condition=ready --timeout=180s pod/taxi-warehouse-1

echo "=== Installing MinIO ==="
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
kind load docker-image taxi-airflow:latest --name "$CLUSTER_NAME"

echo "=== Installing Airflow ==="
helm upgrade --install airflow \
    --namespace data-platform \
    --repo https://airflow.apache.org \
    airflow \
    --version 1.15.0 \
    --values "$INFRA_DIR/values/airflow.yaml" \
    --wait \
    --timeout 10m

echo "=== Setup complete ==="
kubectl get pods --all-namespaces
echo ""
echo "Access: kubectl port-forward -n data-platform svc/airflow-webserver 8080:8080"
