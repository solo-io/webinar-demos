#!/usr/bin/env bash
set -euo pipefail

#############################################################
# 04-register-agents.sh
# Registers skills in agentregistry via its REST API.
# No arctl CLI needed — just curl.
#############################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

source "${SCRIPT_DIR}/ensure-portforward.sh"

REGISTRY_URL="${REGISTRY_URL:-http://localhost:12121}"
GIT_REPO="${GIT_REPO:-https://github.com/solo-io/multi-agent-skills-demo}"

echo "=========================================="
echo " Registering Skills in AgentRegistry"
echo "=========================================="
echo ""
echo "  Registry: ${REGISTRY_URL}"
echo "  Git repo: ${GIT_REPO}"

# Verify connectivity
echo ""
echo "==> Checking agentregistry connectivity..."
if ! curl -sf "${REGISTRY_URL}/v0/skills" -o /dev/null --max-time 5 2>/dev/null; then
  echo "  WARNING: Cannot reach ${REGISTRY_URL}"
  echo "  Trying port-forward fallback..."
  kubectl port-forward svc/agentregistry -n agentregistry 12121:12121 &>/dev/null &
  sleep 2
  REGISTRY_URL="http://localhost:12121"
  if ! curl -sf "${REGISTRY_URL}/v0/skills" -o /dev/null --max-time 5 2>/dev/null; then
    echo "  ERROR: Cannot reach agentregistry. Check: kubectl get pods -n agentregistry"
    exit 1
  fi
fi
echo "  Connected."

echo ""
echo "==> Registering skills..."

# Register k8s-deploy skill
echo ""
echo "  Registering k8s-deploy..."
curl -s -X POST "${REGISTRY_URL}/v0/skills" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"k8s-deploy\",
    \"description\": \"Deploy Kubernetes manifests with dry-run validation, progressive rollout, and automatic rollback on failure.\",
    \"version\": \"1.0.0\",
    \"title\": \"Kubernetes Deployment Skill\",
    \"category\": \"kubernetes\",
    \"repository\": {
      \"url\": \"${GIT_REPO}/tree/main/skills/k8s-deploy\",
      \"source\": \"github\"
    }
  }" | python3 -m json.tool 2>/dev/null || echo "  (registered or error — check response above)"

# Register k8s-healthcheck skill
echo ""
echo "  Registering k8s-healthcheck..."
curl -s -X POST "${REGISTRY_URL}/v0/skills" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"k8s-healthcheck\",
    \"description\": \"Diagnose Kubernetes workload health with structured reports and actionable remediation steps.\",
    \"version\": \"1.0.0\",
    \"title\": \"Kubernetes Health Check Skill\",
    \"category\": \"kubernetes\",
    \"repository\": {
      \"url\": \"${GIT_REPO}/tree/main/skills/k8s-healthcheck\",
      \"source\": \"github\"
    }
  }" | python3 -m json.tool 2>/dev/null || echo "  (registered or error)"

# Register incident-response skill
echo ""
echo "  Registering incident-response..."
curl -s -X POST "${REGISTRY_URL}/v0/skills" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"incident-response\",
    \"description\": \"Multi-agent incident response coordination with root cause analysis and remediation.\",
    \"version\": \"1.0.0\",
    \"title\": \"Incident Response Skill\",
    \"category\": \"operations\",
    \"repository\": {
      \"url\": \"${GIT_REPO}/tree/main/skills/incident-response\",
      \"source\": \"github\"
    }
  }" | python3 -m json.tool 2>/dev/null || echo "  (registered or error)"

echo ""
echo "==> Registering agents..."

echo ""
echo "  Registering k8s-deploy-agent..."
curl -s -X POST "${REGISTRY_URL}/v0/agents" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"k8s-deploy-agent\",
    \"version\": \"1.0.0\",
    \"title\": \"Kubernetes Deploy Agent\",
    \"description\": \"Deploys Kubernetes manifests with dry-run validation, progressive rollout, and automatic rollback on failure.\",
    \"image\": \"ghcr.io/kagent-dev/kagent/controller:latest\",
    \"language\": \"go\",
    \"framework\": \"kagent\",
    \"modelProvider\": \"openai\",
    \"modelName\": \"gpt-4o\",
    \"repository\": {
      \"url\": \"${GIT_REPO}/tree/main/agents\",
      \"source\": \"github\"
    }
  }" | python3 -m json.tool 2>/dev/null || echo "  (registered or error)"

echo ""
echo "  Registering k8s-healthcheck-agent..."
curl -s -X POST "${REGISTRY_URL}/v0/agents" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"k8s-healthcheck-agent\",
    \"version\": \"1.0.0\",
    \"title\": \"Kubernetes Health Check Agent\",
    \"description\": \"Diagnoses Kubernetes workload health with structured reports and actionable remediation steps.\",
    \"image\": \"ghcr.io/kagent-dev/kagent/controller:latest\",
    \"language\": \"go\",
    \"framework\": \"kagent\",
    \"modelProvider\": \"openai\",
    \"modelName\": \"gpt-4o\",
    \"repository\": {
      \"url\": \"${GIT_REPO}/tree/main/agents\",
      \"source\": \"github\"
    }
  }" | python3 -m json.tool 2>/dev/null || echo "  (registered or error)"

echo ""
echo "  Registering incident-response-agent..."
curl -s -X POST "${REGISTRY_URL}/v0/agents" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"incident-response-agent\",
    \"version\": \"1.0.0\",
    \"title\": \"Incident Response Agent\",
    \"description\": \"Multi-agent orchestrator that coordinates deploy and healthcheck agents for incident response with root cause analysis.\",
    \"image\": \"ghcr.io/kagent-dev/kagent/controller:latest\",
    \"language\": \"go\",
    \"framework\": \"kagent\",
    \"modelProvider\": \"openai\",
    \"modelName\": \"gpt-4o\",
    \"repository\": {
      \"url\": \"${GIT_REPO}/tree/main/agents\",
      \"source\": \"github\"
    }
  }" | python3 -m json.tool 2>/dev/null || echo "  (registered or error)"

echo ""
echo "==> Registering MCP servers..."

echo ""
echo "  Registering kagent-tool-server..."
curl -s -X POST "${REGISTRY_URL}/v0/servers" \
  -H "Content-Type: application/json" \
  -d '{
    "$schema": "https://static.modelcontextprotocol.io/schemas/2025-10-17/server.schema.json",
    "name": "kagent-dev/kagent-tool-server",
    "version": "1.0.0",
    "title": "kagent Tool Server",
    "description": "MCP tool server providing Kubernetes operations: apply, get, describe, logs, events, delete."
  }' | python3 -m json.tool 2>/dev/null || echo "  (registered or error)"

echo ""
echo "  Registering kagent-grafana-mcp..."
curl -s -X POST "${REGISTRY_URL}/v0/servers" \
  -H "Content-Type: application/json" \
  -d '{
    "$schema": "https://static.modelcontextprotocol.io/schemas/2025-10-17/server.schema.json",
    "name": "kagent-dev/kagent-grafana-mcp",
    "version": "1.0.0",
    "title": "kagent Grafana MCP",
    "description": "MCP server for Grafana dashboard queries and observability data."
  }' | python3 -m json.tool 2>/dev/null || echo "  (registered or error)"

echo ""
echo "==> Verifying registration..."
echo ""
echo "  Skills:"
curl -s "${REGISTRY_URL}/v0/skills?version=latest" | python3 -m json.tool 2>/dev/null | head -20 || \
  echo "  (check: curl ${REGISTRY_URL}/v0/skills)"
echo ""
echo "  Agents:"
curl -s "${REGISTRY_URL}/v0/agents?version=latest" | python3 -m json.tool 2>/dev/null | head -20 || \
  echo "  (check: curl ${REGISTRY_URL}/v0/agents)"

echo ""
echo "==> All registered!"
echo ""
echo "  Web UI:         ${REGISTRY_URL}"
echo "  List skills:    curl -s ${REGISTRY_URL}/v0/skills | python3 -m json.tool"
echo "  List agents:    curl -s ${REGISTRY_URL}/v0/agents | python3 -m json.tool"
echo "  List servers:   curl -s ${REGISTRY_URL}/v0/servers | python3 -m json.tool"
echo "  Search:         curl -s '${REGISTRY_URL}/v0/skills?search=kubernetes'"
echo ""
echo "==> Next: run 05-run-and-eval.sh"
