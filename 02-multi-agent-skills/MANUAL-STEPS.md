# Manual Steps: Multi-Agent Skills Demo

> Step-by-step commands to set up the entire demo by hand.
> No scripts required — just copy-paste each block.

---

## Prerequisites

| Tool | Install |
|------|---------|
| Docker Desktop (8GB+ RAM) | [docker.com](https://docker.com) |
| kind | `brew install kind` |
| kubectl | `brew install kubectl` |
| Helm 3 | `brew install helm` |

```bash
export OPENAI_API_KEY='sk-...'
```

---

## Step 1: Create the Kind Cluster

```bash
cat <<'EOF' | kind create cluster --name multi-agent-demo --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    extraPortMappings:
      - containerPort: 30121
        hostPort: 12121
        listenAddress: "127.0.0.1"
        protocol: TCP
EOF
```

Verify:
```bash
kubectl cluster-info --context kind-multi-agent-demo
kubectl get nodes
```

---

## Step 2: Install agentevals

agentevals receives OTel traces from kagent and provides a web UI for evaluation. It must be installed first because kagent sends traces to its OTLP endpoint.

```bash
# Clone the repo (Helm chart isn't published to a registry)
git clone --depth 1 https://github.com/agentevals-dev/agentevals.git /tmp/agentevals

# Install via Helm
helm upgrade --install agentevals \
  /tmp/agentevals/charts/agentevals \
  --namespace default \
  --set tag=0.6.3 \
  --wait --timeout 300s
```

Verify:
```bash
kubectl get pods -l app.kubernetes.io/name=agentevals
```

---

## Step 3: Install kagent

kagent is the Kubernetes-native AI agent framework. It auto-creates a `default-model-config` (ModelConfig), `kagent-openai` (Secret), and `kagent-tool-server` (RemoteMCPServer).

```bash
# Install CRDs first
helm install kagent-crds oci://ghcr.io/kagent-dev/kagent/helm/kagent-crds \
  --namespace kagent --create-namespace

# Install kagent with OTel tracing pointed at agentevals
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
```

Wait for pods and verify auto-created resources:
```bash
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=kagent \
  --namespace kagent --timeout=120s

kubectl get modelconfig -n kagent
kubectl get remotemcpserver -n kagent
```

You should see `default-model-config` and `kagent-tool-server`.

---

## Step 4: Install agentregistry

agentregistry provides a skill catalog with a REST API and web UI. The bundled PostgreSQL needs the pgvector image (the migration SQL creates the `vector` extension).

```bash
JWT_KEY=$(openssl rand -hex 32)

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
```

Verify:
```bash
kubectl get pods -n agentregistry
```

---

## Step 5: Set Up Port-Forwards

```bash
# Kill any existing port-forwards
pkill -f "port-forward.*agentevals" 2>/dev/null || true
pkill -f "port-forward.*kagent" 2>/dev/null || true

# agentevals UI + OTLP
kubectl port-forward svc/agentevals -n default 8001:8001 &>/dev/null &
kubectl port-forward svc/agentevals -n default 4318:4318 &>/dev/null &

# kagent API + UI (note: kagent-ui listens on port 8080 internally)
kubectl port-forward svc/kagent-controller -n kagent 8083:8083 &>/dev/null &
kubectl port-forward svc/kagent-ui -n kagent 8082:8080 &>/dev/null &
```

> **agentregistry** is exposed via NodePort — no port-forward needed. It's at `http://localhost:12121`.

Test connectivity:
```bash
curl -s http://localhost:8083/api/agents | python3 -m json.tool
curl -s http://localhost:12121/v0/skills | python3 -m json.tool
```

If port-forwards die later, restart them:
```bash
source ./scripts/ensure-portforward.sh
```

### Access Points

| Service | URL |
|---------|-----|
| agentevals UI | http://localhost:8001 |
| kagent UI | http://localhost:8082 |
| kagent API | http://localhost:8083 |
| agentregistry | http://localhost:12121 |

---

## Step 6: Deploy the 3 Agents

First confirm the auto-created resources exist:
```bash
kubectl get modelconfig default-model-config -n kagent
kubectl get remotemcpserver kagent-tool-server -n kagent
```

Then apply the agent CRDs:
```bash
kubectl apply -f agents/01-deploy-agent.yaml
kubectl apply -f agents/02-healthcheck-agent.yaml
kubectl apply -f agents/03-incident-agent.yaml
```

Verify:
```bash
kubectl get agents -n kagent
curl -s http://localhost:8083/api/agents | python3 -m json.tool
```

You should see 3 agents:
- **k8s-deploy-agent** — 6 MCP tools, deploys with dry-run validation
- **k8s-healthcheck-agent** — 5 read-only diagnostic tools
- **incident-response-agent** — orchestrates the other two (`type: Agent`)

---

## Step 7: Test an Agent

### Via the kagent UI

Open http://localhost:8082, click `k8s-healthcheck-agent`, and chat:

> Check the health of all pods in the kagent namespace

### Via curl (A2A protocol)

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

## Step 8: Register Skills in agentregistry

No CLI needed — just curl to the REST API:

```bash
# Register k8s-deploy skill
curl -s -X POST http://localhost:12121/v0/skills \
  -H "Content-Type: application/json" \
  -d '{
    "name": "k8s-deploy",
    "description": "Deploy Kubernetes manifests with dry-run validation, progressive rollout, and automatic rollback on failure.",
    "version": "1.0.0",
    "title": "Kubernetes Deployment Skill",
    "category": "kubernetes",
    "repository": {
      "url": "https://github.com/solo-io/multi-agent-skills-demo/tree/main/skills/k8s-deploy",
      "source": "github"
    }
  }' | python3 -m json.tool

# Register k8s-healthcheck skill
curl -s -X POST http://localhost:12121/v0/skills \
  -H "Content-Type: application/json" \
  -d '{
    "name": "k8s-healthcheck",
    "description": "Diagnose Kubernetes workload health with structured reports and actionable remediation steps.",
    "version": "1.0.0",
    "title": "Kubernetes Health Check Skill",
    "category": "kubernetes",
    "repository": {
      "url": "https://github.com/solo-io/multi-agent-skills-demo/tree/main/skills/k8s-healthcheck",
      "source": "github"
    }
  }' | python3 -m json.tool

# Register incident-response skill
curl -s -X POST http://localhost:12121/v0/skills \
  -H "Content-Type: application/json" \
  -d '{
    "name": "incident-response",
    "description": "Multi-agent incident response coordination with root cause analysis and remediation.",
    "version": "1.0.0",
    "title": "Incident Response Skill",
    "category": "operations",
    "repository": {
      "url": "https://github.com/solo-io/multi-agent-skills-demo/tree/main/skills/incident-response",
      "source": "github"
    }
  }' | python3 -m json.tool
```

### Register Agents

```bash
# Register k8s-deploy-agent
curl -s -X POST http://localhost:12121/v0/agents \
  -H "Content-Type: application/json" \
  -d '{
    "name": "k8s-deploy-agent",
    "version": "1.0.0",
    "title": "Kubernetes Deploy Agent",
    "description": "Deploys Kubernetes manifests with dry-run validation, progressive rollout, and automatic rollback on failure.",
    "image": "ghcr.io/kagent-dev/kagent/controller:latest",
    "language": "go",
    "framework": "kagent",
    "modelProvider": "openai",
    "modelName": "gpt-4o"
  }' | python3 -m json.tool

# Register k8s-healthcheck-agent
curl -s -X POST http://localhost:12121/v0/agents \
  -H "Content-Type: application/json" \
  -d '{
    "name": "k8s-healthcheck-agent",
    "version": "1.0.0",
    "title": "Kubernetes Health Check Agent",
    "description": "Diagnoses Kubernetes workload health with structured reports and actionable remediation steps.",
    "image": "ghcr.io/kagent-dev/kagent/controller:latest",
    "language": "go",
    "framework": "kagent",
    "modelProvider": "openai",
    "modelName": "gpt-4o"
  }' | python3 -m json.tool

# Register incident-response-agent
curl -s -X POST http://localhost:12121/v0/agents \
  -H "Content-Type: application/json" \
  -d '{
    "name": "incident-response-agent",
    "version": "1.0.0",
    "title": "Incident Response Agent",
    "description": "Multi-agent orchestrator that coordinates deploy and healthcheck agents for incident response.",
    "image": "ghcr.io/kagent-dev/kagent/controller:latest",
    "language": "go",
    "framework": "kagent",
    "modelProvider": "openai",
    "modelName": "gpt-4o"
  }' | python3 -m json.tool
```

### Register MCP Servers

```bash
# Register kagent-tool-server
curl -s -X POST http://localhost:12121/v0/servers \
  -H "Content-Type: application/json" \
  -d '{
    "$schema": "https://static.modelcontextprotocol.io/schemas/2025-10-17/server.schema.json",
    "name": "kagent-dev/kagent-tool-server",
    "version": "1.0.0",
    "title": "kagent Tool Server",
    "description": "MCP tool server providing Kubernetes operations: apply, get, describe, logs, events, delete."
  }' | python3 -m json.tool

# Register kagent-grafana-mcp
curl -s -X POST http://localhost:12121/v0/servers \
  -H "Content-Type: application/json" \
  -d '{
    "$schema": "https://static.modelcontextprotocol.io/schemas/2025-10-17/server.schema.json",
    "name": "kagent-dev/kagent-grafana-mcp",
    "version": "1.0.0",
    "title": "kagent Grafana MCP",
    "description": "MCP server for Grafana dashboard queries and observability data."
  }' | python3 -m json.tool
```

### Verify

```bash
# List all skills
curl -s http://localhost:12121/v0/skills | python3 -m json.tool

# List all agents
curl -s http://localhost:12121/v0/agents | python3 -m json.tool

# List all servers
curl -s http://localhost:12121/v0/servers | python3 -m json.tool

# Search
curl -s "http://localhost:12121/v0/skills?search=kubernetes" | python3 -m json.tool
```

Browse the catalog at http://localhost:12121.

---

## Step 9: Run Agents & View Traces

### Deploy a test workload

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

### Invoke the deploy agent

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

### Invoke the healthcheck agent

```bash
curl -s -L -X POST http://localhost:8083/api/a2a/kagent/k8s-healthcheck-agent \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0", "id": "2", "method": "message/send",
    "params": {"message": {"kind": "message", "role": "user",
      "parts": [{"kind": "text", "text": "Full health check on nginx-demo in default namespace"}]
    }}
  }' | python3 -m json.tool
```

### Invoke the incident response agent (multi-agent)

```bash
curl -s -L -X POST http://localhost:8083/api/a2a/kagent/incident-response-agent \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0", "id": "3", "method": "message/send",
    "params": {"message": {"kind": "message", "role": "user",
      "parts": [{"kind": "text", "text": "We are seeing intermittent 503 errors from nginx-demo in default namespace. Investigate and produce an incident summary."}]
    }}
  }' | python3 -m json.tool
```

### View traces in agentevals

Open http://localhost:8001 — traces flow automatically from kagent via OTLP. Every tool call appears as a span. You can run evaluations against the eval sets in `evals/`.

---

## Cleanup

```bash
pkill -f "port-forward" 2>/dev/null || true
kind delete cluster --name multi-agent-demo
rm -rf /tmp/agentevals
```

---

## Troubleshooting

| Issue | Fix |
|-------|-----|
| curl to :8083 fails | Re-run port-forwards (Step 5) or `source ./scripts/ensure-portforward.sh` |
| No traces in agentevals | Check kagent OTel config: `kubectl get pods -n kagent` and logs |
| agentregistry :12121 down | `kubectl get pods -n agentregistry` — check for CrashLoopBackOff |
| agentregistry CrashLoopBackOff | Likely pgvector issue — ensure you used the pgvector image flags |
| kind OOM | Docker Desktop → Resources → 8GB+ RAM |
| Helm OCI 403 | `echo $GH_TOKEN | helm registry login ghcr.io -u x --password-stdin` |
