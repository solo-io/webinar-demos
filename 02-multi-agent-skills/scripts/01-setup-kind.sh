#!/usr/bin/env bash
set -euo pipefail

#############################################################
# 01-setup-kind.sh
# Creates a kind cluster for the demo.
#
# Port access strategy:
#   - agentregistry: NodePort 30121 → host 12121
#   - kagent, agentevals: kubectl port-forward (set up in 02-install-stack.sh)
#
# NOTE: Ensure Docker Desktop has at least 8GB RAM allocated.
#############################################################

CLUSTER_NAME="${CLUSTER_NAME:-multi-agent-demo}"

echo "==> Checking prerequisites..."
for cmd in kind kubectl helm docker; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "ERROR: $cmd is required but not installed."
    exit 1
  fi
done

# Delete existing cluster if present
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
  echo "==> Deleting existing kind cluster '${CLUSTER_NAME}'..."
  kind delete cluster --name "${CLUSTER_NAME}"
fi

echo "==> Creating kind cluster '${CLUSTER_NAME}'..."
cat <<EOF | kind create cluster --name "${CLUSTER_NAME}" --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    extraPortMappings:
      # agentregistry NodePort
      - containerPort: 30121
        hostPort: 12121
        listenAddress: "127.0.0.1"
        protocol: TCP
EOF

echo "==> Cluster ready:"
kubectl cluster-info --context "kind-${CLUSTER_NAME}"
kubectl get nodes

echo ""
echo "==> Done! Next: run 02-install-stack.sh"
