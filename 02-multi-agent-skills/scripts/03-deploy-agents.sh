#!/usr/bin/env bash
set -euo pipefail

#############################################################
# 03-deploy-agents.sh
# Deploys the 3 agents to kagent via kubectl.
#############################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

source "${SCRIPT_DIR}/ensure-portforward.sh"

echo "=========================================="
echo " Deploying Agents to kagent"
echo "=========================================="

echo ""
echo "==> Step 1: Pre-flight checks..."

echo "  Checking ModelConfig..."
kubectl get modelconfig default-model-config -n kagent || {
  echo "ERROR: ModelConfig 'default-model-config' not found. Run 02-install-stack.sh first."
  exit 1
}

echo "  Checking RemoteMCPServer..."
kubectl get remotemcpserver kagent-tool-server -n kagent || {
  echo "ERROR: RemoteMCPServer 'kagent-tool-server' not found."
  exit 1
}

echo ""
echo "==> Step 2: Apply agent definitions..."

echo "  Deploying k8s-deploy-agent..."
kubectl apply -f "${PROJECT_DIR}/agents/01-deploy-agent.yaml"

echo "  Deploying k8s-healthcheck-agent..."
kubectl apply -f "${PROJECT_DIR}/agents/02-healthcheck-agent.yaml"

echo "  Deploying incident-response-agent..."
kubectl apply -f "${PROJECT_DIR}/agents/03-incident-agent.yaml"

echo ""
echo "==> Step 3: Verify agents..."
sleep 3
kubectl get agents -n kagent

echo ""
echo "==> Step 4: Verify via API..."
echo ""
curl -s http://localhost:8083/api/agents | python3 -m json.tool 2>/dev/null | head -30 || \
  echo "  (API not reachable — check port-forward)"

echo ""
echo "==> All 3 agents deployed!"
echo ""
echo "  1. k8s-deploy-agent       — Deploys workloads with dry-run validation"
echo "  2. k8s-healthcheck-agent  — Diagnoses workload health"
echo "  3. incident-response-agent — Orchestrates the other two (multi-agent)"
echo ""
echo "  Chat with an agent in the UI: http://localhost:8082"
echo ""
echo "  Or invoke via curl:"
echo '  curl -s -L -X POST http://localhost:8083/api/a2a/kagent/k8s-healthcheck-agent \'
echo '    -H "Content-Type: application/json" \'
echo '    -d '"'"'{"jsonrpc":"2.0","id":"1","method":"message/send","params":{"message":{"kind":"message","role":"user","parts":[{"kind":"text","text":"Check health of all pods in default namespace"}]}}}'"'"
echo ""
echo "==> Next: run 04-register-agents.sh"
