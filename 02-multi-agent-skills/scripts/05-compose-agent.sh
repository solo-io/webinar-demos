#!/usr/bin/env bash
set -euo pipefail

#############################################################
# 05-compose-agent.sh
# Team B (Platform): Discovers skills in agentregistry,
# composes the incident-response agent that orchestrates
# Team A's specialist agents, then registers their work
# back in the catalog.
#############################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

source "${SCRIPT_DIR}/ensure-portforward.sh"

REGISTRY_URL="${REGISTRY_URL:-http://localhost:12121}"
GIT_REPO="${GIT_REPO:-https://github.com/solo-io/multi-agent-skills-demo}"

echo "=========================================="
echo " Team B: Discover, Compose & Register"
echo "=========================================="

echo ""
echo "==> Step 1: Search the registry for kubernetes skills..."
echo ""
echo "  Query: 'kubernetes'"
echo ""
curl -s "${REGISTRY_URL}/v0/skills?search=kubernetes" | python3 -m json.tool 2>/dev/null | head -30 || \
  echo "  (registry not reachable)"

echo ""
echo "==> Step 2: Check what agents are available..."
echo ""
curl -s "${REGISTRY_URL}/v0/agents" | python3 -m json.tool 2>/dev/null | head -40 || \
  echo "  (registry not reachable)"

echo ""
echo "==> Step 3: Found 2 specialist agents!"
echo ""
echo "  k8s-deploy-agent       — Can deploy and rollback (6 tools)"
echo "  k8s-healthcheck-agent  — Can diagnose health issues (5 tools, read-only)"
echo ""
echo "  These were built by Team A (SRE). Team B doesn't need to"
echo "  understand kubectl — they just compose these agents into"
echo "  a higher-level orchestrator."

echo ""
echo "==> Step 4: Deploy the incident-response agent (uses Team A's agents as tools)..."
echo ""
echo "  The incident agent's tools are:"
echo "    - type: Agent"
echo "      agent:"
echo "        name: k8s-deploy-agent"
echo "    - type: Agent"
echo "      agent:"
echo "        name: k8s-healthcheck-agent"
echo ""

kubectl apply -f "${PROJECT_DIR}/agents/03-incident-agent.yaml"

echo ""
echo "==> Waiting for agent to be ready..."
sleep 3
kubectl get agents incident-response-agent -n kagent

echo ""
echo "==> Step 5: Register Team B's work in the catalog..."
echo ""

echo "  Registering incident-response skill..."
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
    \"modelName\": \"gpt-5.4-mini-2026-03-17\",
    \"repository\": {
      \"url\": \"${GIT_REPO}/tree/main/agents\",
      \"source\": \"github\"
    }
  }" | python3 -m json.tool 2>/dev/null || echo "  (registered or error)"

echo ""
echo "==> Step 6: Verify all agents via API..."
echo ""
curl -s http://localhost:8083/api/agents | python3 -m json.tool 2>/dev/null | head -30 || \
  echo "  (API not reachable)"

echo ""
echo "=========================================="
echo " Composition Complete"
echo "=========================================="
echo ""
echo "  Team A registered:  2 skills, 2 agents, 3 servers"
echo "  Team B registered:  1 skill, 1 agent (orchestrates Team A's)"
echo ""
echo "  Registry now has:   3 skills, 3 agents, 3 servers"
echo ""
echo "  Team B didn't write a single kubectl command in their agent."
echo "  They discovered Team A's work in the registry and composed it."
echo ""
echo "  Test it:"
echo "    http://localhost:8082  (kagent UI → incident-response-agent)"
echo ""
echo "==> Next: run 06-run-and-eval.sh"
