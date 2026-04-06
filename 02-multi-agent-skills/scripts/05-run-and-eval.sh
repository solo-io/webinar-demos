#!/usr/bin/env bash
set -euo pipefail

#############################################################
# 05-run-and-eval.sh
# Runs the agents against a test workload via the kagent
# REST API (A2A protocol). No local CLIs needed.
# Traces flow automatically via OTLP to agentevals.
#############################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

source "${SCRIPT_DIR}/ensure-portforward.sh"

mkdir -p "${PROJECT_DIR}/traces"

KAGENT_API="http://localhost:8083"

# Helper: invoke an agent via the A2A protocol
invoke_agent() {
  local agent_name="$1"
  local prompt="$2"
  local output_file="$3"

  echo "  Agent: ${agent_name}"
  echo "  Prompt: ${prompt}"
  echo ""

  curl -s -L -X POST "${KAGENT_API}/api/a2a/kagent/${agent_name}" \
    -H "Content-Type: application/json" \
    -d "$(cat <<BODY
{
  "jsonrpc": "2.0",
  "id": "$(date +%s)",
  "method": "message/send",
  "params": {
    "message": {
      "kind": "message",
      "role": "user",
      "parts": [{"kind": "text", "text": "${prompt}"}]
    }
  }
}
BODY
)" | tee "${output_file}" | python3 -m json.tool 2>/dev/null || cat "${output_file}"

  echo ""
}

echo "=========================================="
echo " Run Agents & Evaluate"
echo "=========================================="

echo ""
echo "==> Step 1: Deploy a test workload"
echo ""

cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-demo
  namespace: default
spec:
  replicas: 3
  selector:
    matchLabels:
      app: nginx-demo
  template:
    metadata:
      labels:
        app: nginx-demo
    spec:
      containers:
      - name: nginx
        image: nginx:1.25
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 100m
            memory: 128Mi
        readinessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 10
---
apiVersion: v1
kind: Service
metadata:
  name: nginx-demo
  namespace: default
spec:
  selector:
    app: nginx-demo
  ports:
  - port: 80
    targetPort: 80
EOF

echo "  Waiting for nginx-demo to be ready..."
kubectl rollout status deployment/nginx-demo --timeout=60s

echo ""
echo "==> Step 2: Invoke the deploy agent"
echo ""
invoke_agent "k8s-deploy-agent" \
  "Check the rollout status and health of the nginx-demo deployment in default namespace. Verify all pods are ready." \
  "${PROJECT_DIR}/traces/deploy-agent-output.json"

echo ""
echo "==> Step 3: Invoke the healthcheck agent"
echo ""
invoke_agent "k8s-healthcheck-agent" \
  "Perform a full health check on the nginx-demo deployment in default namespace. Report status, pod health, and any issues." \
  "${PROJECT_DIR}/traces/healthcheck-agent-output.json"

echo ""
echo "==> Step 4: Invoke the incident response agent (multi-agent)"
echo ""
invoke_agent "incident-response-agent" \
  "We are seeing intermittent 503 errors from the nginx-demo service in default namespace. Investigate: check health, check recent deployments, and produce an incident summary." \
  "${PROJECT_DIR}/traces/incident-agent-output.json"

echo ""
echo "=========================================="
echo " Evaluate"
echo "=========================================="
echo ""
echo "  Traces have been collected automatically via OTLP."
echo ""
echo "  Open the agentevals UI to view traces and run evaluations:"
echo "    http://localhost:8001"
echo ""
echo "  You can also use the kagent UI to chat with agents interactively:"
echo "    http://localhost:8082"
echo ""
echo "  Agent API responses saved to: traces/*.json"
echo ""
echo "=========================================="
echo " All Access Points"
echo "=========================================="
echo ""
echo "  kagent UI:       http://localhost:8082  (chat with agents)"
echo "  kagent API:      http://localhost:8083  (REST + A2A)"
echo "  agentregistry:   http://localhost:12121 (skill catalog)"
echo "  agentevals:      http://localhost:8001  (traces + evals)"
echo ""
echo "==> Done!"
