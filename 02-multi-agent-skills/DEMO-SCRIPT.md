# Multi-Agent Skills Demo Script

> **Duration:** ~30 minutes
> **Pre-req:** Docker Desktop (8GB+ RAM), kind, kubectl, helm, `OPENAI_API_KEY`
> **No local CLIs** — everything runs in-cluster with web UIs and REST APIs

---

## Pre-Demo Setup

```bash
export OPENAI_API_KEY='sk-...'
./scripts/01-setup-kind.sh
./scripts/02-install-stack.sh
```

Verify:
```bash
kubectl get pods -n kagent
kubectl get pods -n agentregistry
kubectl get pods -n default -l app.kubernetes.io/name=agentevals
```

If you restarted your terminal:
```bash
source ./scripts/ensure-portforward.sh
```

---

## ACT 1: Build Skills + Agents (~10 min)

**[TALKING POINT]** "Three AI agents on Kubernetes. No local installs needed — just kubectl and helm."

#### Show a Skill

```bash
cat skills/k8s-deploy/SKILL.md
```

**[TALKING POINT]** "Structured markdown with YAML frontmatter. Triggers, instructions with real tool names like `k8s_apply_manifest`, error handling, validation criteria."

#### Show an Agent CRD

```bash
cat agents/01-deploy-agent.yaml
```

**[TALKING POINT]** "A `kagent.dev/v1alpha2` custom resource. The `modelConfig` points to `default-model-config` — gpt-4o, auto-created by the Helm chart. Six tools from the MCP tool server. The skill instructions are right in the `systemMessage`."

#### Deploy All 3 Agents

```bash
./scripts/03-deploy-agents.sh
```

**[TALKING POINT]** "Three agents:
1. **Deploy agent** — 6 tools, validates before applying
2. **Healthcheck agent** — 5 read-only diagnostic tools
3. **Incident agent** — its tools ARE the other agents. `type: Agent`. That's multi-agent."

#### Test via the kagent UI

**[OPEN BROWSER: http://localhost:8082]**

- Click on `k8s-healthcheck-agent`
- Chat: "Check the health of all pods in the kagent namespace"
- Watch the agent use tools in real-time

**[TALKING POINT]** "No CLI install. The kagent UI lets you chat with any agent. And we can do the same thing with curl using the A2A protocol."

#### Test via curl

```bash
curl -s -L -X POST http://localhost:8083/api/a2a/kagent/k8s-healthcheck-agent \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": "1",
    "method": "message/send",
    "params": {
      "message": {
        "kind": "message",
        "role": "user",
        "parts": [{"kind": "text", "text": "Check health of all pods in kagent namespace"}]
      }
    }
  }' | python3 -m json.tool
```

---

## ACT 2: Register in AgentRegistry (~8 min)

**[TALKING POINT]** "Working skills. Let's make them discoverable — without installing another CLI."

#### Register Skills via API

```bash
./scripts/04-register-agents.sh
```

**[TALKING POINT]** "Just curl calls to the agentregistry REST API. `POST /v0/skills` with name, description, version, and a Git repo link."

#### Show the Registry UI

**[OPEN BROWSER: http://localhost:12121]**

- Browse skill catalog
- Click into a skill to see details
- Show the list of registered skills

#### API Discovery

```bash
# List all skills
curl -s http://localhost:12121/v0/skills | python3 -m json.tool

# Search
curl -s "http://localhost:12121/v0/skills?search=kubernetes" | python3 -m json.tool

# Get specific skill
curl -s http://localhost:12121/v0/skills/k8s-deploy/versions/1.0.0 | python3 -m json.tool
```

**[TALKING POINT]** "Any team can register, any agent can discover. Full REST API — works from CI/CD, from scripts, from anywhere."

---

## ACT 3: Evaluate with AgentEvals (~12 min)

**[TALKING POINT]** "OTel traces have been flowing from kagent the entire time. Let's see them."

#### Deploy Test Workload + Run Agent

```bash
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-demo
spec:
  replicas: 3
  selector:
    matchLabels: { app: nginx-demo }
  template:
    metadata:
      labels: { app: nginx-demo }
    spec:
      containers:
      - name: nginx
        image: nginx:1.25
        ports: [{ containerPort: 80 }]
        resources:
          requests: { cpu: 50m, memory: 64Mi }
          limits: { cpu: 100m, memory: 128Mi }
        readinessProbe:
          httpGet: { path: /, port: 80 }
EOF

kubectl rollout status deployment/nginx-demo
```

**[Chat in kagent UI or invoke via curl]**

```bash
curl -s -L -X POST http://localhost:8083/api/a2a/kagent/k8s-deploy-agent \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0", "id": "1", "method": "message/send",
    "params": {"message": {"kind": "message", "role": "user",
      "parts": [{"kind": "text", "text": "Verify nginx-demo in default namespace is healthy"}]
    }}
  }' | python3 -m json.tool
```

#### Show AgentEvals UI

**[OPEN BROWSER: http://localhost:8001]**

- Trace visualization — every tool call as a span
- Run evaluations interactively against eval sets in `evals/`
- Score breakdown per step

**[TALKING POINT]** "No Python install. No CLI. agentevals runs in the cluster, collects traces via OTLP, and gives you a web UI to evaluate. For CI/CD, there's a REST API at `/docs`."

---

## Closing (~2 min)

**[TALKING POINT]** "Full lifecycle:

1. **Build** — SKILL.md with frontmatter, Agent CRDs with `kubectl apply`
2. **Deploy** — Kubernetes-native via kagent Helm chart, gpt-4o, MCP tools
3. **Orchestrate** — Multi-agent: `type: Agent` makes agents into tools
4. **Register** — REST API to agentregistry, browsable catalog
5. **Evaluate** — OTel traces flow to agentevals automatically

**Zero local CLIs beyond kubectl and helm.** Everything runs in the cluster. All open source. All on a kind cluster on my laptop."

---

## Troubleshooting

| Issue | Fix |
|-------|-----|
| curl to :8083 fails | `source ./scripts/ensure-portforward.sh` |
| No traces in agentevals | Check kagent OTel config in Helm values |
| Registry :12121 down | Check: `kubectl get pods -n agentregistry` |
| kind OOM | Docker Desktop → 8GB+ RAM |

## File Structure

```
scripts/
  01-setup-kind.sh          # Kind cluster
  02-install-stack.sh       # Helm install everything
  03-deploy-agents.sh       # kubectl apply agents
  04-register-agents.sh     # curl to registry API
  05-run-and-eval.sh        # curl to kagent A2A API
  ensure-portforward.sh     # Restart dead port-forwards
agents/
  01-deploy-agent.yaml      # 6 MCP tools
  02-healthcheck-agent.yaml # 5 read-only MCP tools
  03-incident-agent.yaml    # 2 agent-as-tool
skills/
  k8s-deploy/SKILL.md       # With YAML frontmatter
  k8s-healthcheck/SKILL.md
  incident-response/SKILL.md
evals/
  deploy-eval.json           # ADK conversation format
  healthcheck-eval.json
  incident-eval.json
```
