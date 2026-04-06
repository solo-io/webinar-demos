#!/usr/bin/env bash
set -euo pipefail

#############################################################
# 02-install-stack.sh
# Installs agentevals, kagent, and agentregistry into the
# kind cluster. Requires OPENAI_API_KEY env var.
#
# Prerequisites: docker, kind, kubectl, helm
# No other local CLI installs needed — everything runs
# in-cluster with web UIs and REST APIs.
#############################################################

if [ -z "${OPENAI_API_KEY:-}" ]; then
  echo "ERROR: OPENAI_API_KEY environment variable is required."
  echo "  export OPENAI_API_KEY='sk-...'"
  exit 1
fi

CLUSTER_NAME="${CLUSTER_NAME:-multi-agent-demo}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TEMP_DIR="${PROJECT_DIR}/.tmp"

kubectl config use-context "kind-${CLUSTER_NAME}" 2>/dev/null || true

###########################################################
# Step 1: Install agentevals (kagent needs its OTLP endpoint)
###########################################################
echo ""
echo "=========================================="
echo " Step 1: Install agentevals"
echo "=========================================="

# Clone repo for the Helm chart (not published to a registry)
echo "==> Cloning agentevals repo for Helm chart..."
mkdir -p "${TEMP_DIR}"
if [ -d "${TEMP_DIR}/agentevals" ]; then
  git -C "${TEMP_DIR}/agentevals" pull --ff-only 2>/dev/null || true
else
  git clone --depth 1 https://github.com/agentevals-dev/agentevals.git "${TEMP_DIR}/agentevals"
fi

if [ ! -f "${TEMP_DIR}/agentevals/charts/agentevals/Chart.yaml" ]; then
  echo "ERROR: Helm chart not found at .tmp/agentevals/charts/agentevals/"
  exit 1
fi

echo "==> Installing agentevals into cluster..."
helm upgrade --install agentevals \
  "${TEMP_DIR}/agentevals/charts/agentevals" \
  --namespace default \
  --set tag=0.6.3 \
  --wait --timeout 300s

echo "==> agentevals installed."

###########################################################
# Step 2: Install kagent with OTel tracing → agentevals
###########################################################
echo ""
echo "=========================================="
echo " Step 2: Install kagent"
echo "=========================================="

echo "==> Installing kagent CRDs..."
helm install kagent-crds oci://ghcr.io/kagent-dev/kagent/helm/kagent-crds \
  --namespace kagent --create-namespace \
  2>/dev/null || echo "  (CRDs may already exist — continuing)"

echo "==> Installing kagent..."
helm upgrade --install kagent oci://ghcr.io/kagent-dev/kagent/helm/kagent \
  --namespace kagent \
  --set providers.default=openAI \
  --set providers.openAI.apiKey="${OPENAI_API_KEY}" \
  --set providers.openAI.model=gpt-4o \
  --set otel.tracing.enabled=true \
  --set otel.tracing.exporter.otlp.endpoint="agentevals.default.svc.cluster.local:4317" \
  --set otel.tracing.exporter.otlp.insecure=true \
  --set agents.istio-agent.enabled=false \
  --set agents.kgateway-agent.enabled=false \
  --set agents.promql-agent.enabled=false \
  --set agents.observability-agent.enabled=false \
  --set agents.argo-rollouts-agent.enabled=false \
  --set agents.cilium-policy-agent.enabled=false \
  --set agents.cilium-manager-agent.enabled=false \
  --set agents.cilium-debug-agent.enabled=false \
  --wait --timeout 180s

echo "==> Waiting for kagent pods..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=kagent \
  --namespace kagent --timeout=120s 2>/dev/null || \
  echo "  (some pods may still be starting)"

echo "==> Verifying kagent resources..."
kubectl get modelconfig -n kagent
kubectl get remotemcpserver -n kagent

###########################################################
# Step 3: Install agentregistry
###########################################################
echo ""
echo "=========================================="
echo " Step 3: Install agentregistry"
echo "=========================================="

echo "==> Installing agentregistry into cluster..."
JWT_KEY=$(openssl rand -hex 32)

# NOTE: The bundled PostgreSQL needs the pgvector image (not plain postgres).
# The migration SQL creates the vector extension, which fails with plain postgres:18.
helm upgrade --install agentregistry \
  oci://ghcr.io/agentregistry-dev/agentregistry/charts/agentregistry \
  --namespace agentregistry \
  --create-namespace \
  --set config.jwtPrivateKey="${JWT_KEY}" \
  --set config.enableAnonymousAuth="true" \
  --set service.type=NodePort \
  --set service.nodePorts.http=30121 \
  --set database.postgres.vectorEnabled=true \
  --set database.postgres.bundled.image.repository=pgvector \
  --set database.postgres.bundled.image.name=pgvector \
  --set database.postgres.bundled.image.tag=pg16 \
  --set image.tag=v0.3.3 \
  --wait --timeout 300s

echo "==> agentregistry installed."

###########################################################
# Step 4: Set up port-forwarding
###########################################################
echo ""
echo "=========================================="
echo " Step 4: Set up access"
echo "=========================================="

pkill -f "port-forward.*agentevals" 2>/dev/null || true
pkill -f "port-forward.*kagent" 2>/dev/null || true

echo "==> Starting port-forwards..."
kubectl port-forward svc/agentevals -n default 8001:8001 &>/dev/null &
kubectl port-forward svc/agentevals -n default 4318:4318 &>/dev/null &
kubectl port-forward svc/kagent-controller -n kagent 8083:8083 &>/dev/null &
kubectl port-forward svc/kagent-ui -n kagent 8082:8080 &>/dev/null &

sleep 2

echo ""
echo "  agentevals UI:    http://localhost:8001"
echo "  kagent UI:        http://localhost:8082"
echo "  kagent API:       http://localhost:8083"
echo "  agentregistry UI: http://localhost:12121  (NodePort)"

###########################################################
# Step 5: Verify the stack
###########################################################
echo ""
echo "=========================================="
echo " Stack Status"
echo "=========================================="
echo ""
echo "--- kagent ---"
kubectl get pods -n kagent
echo ""
echo "--- agentregistry ---"
kubectl get pods -n agentregistry
echo ""
echo "--- agentevals ---"
kubectl get pods -n default -l app.kubernetes.io/name=agentevals

echo ""
echo "=========================================="
echo " Quick Test"
echo "=========================================="
echo ""
echo "  List agents:"
echo "    curl -s http://localhost:8083/api/agents | python3 -m json.tool"
echo ""
echo "  If port-forwards die, re-run:"
echo "    source ./scripts/ensure-portforward.sh"
echo ""
echo "==> Done! Next: run 03-deploy-agents.sh"
