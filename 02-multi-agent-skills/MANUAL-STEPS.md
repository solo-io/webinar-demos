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
  --set 'command={agentevals}' \
  --set 'args={serve,--dev}' \
  --set env[0].name=OPENAI_API_KEY \
  --set env[0].value="${OPENAI_API_KEY}" \
  --wait --timeout 300s
```

Verify:
```bash
kubectl get pods -l app.kubernetes.io/name=agentevals
```

---

## Step 3: Install agentgateway

agentgateway is an AI-native proxy that governs LLM, MCP, and A2A traffic. All LLM calls from kagent will flow through it.

### Install Gateway API CRDs

```bash
kubectl apply --server-side --force-conflicts -f \
  https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.0/standard-install.yaml
```

### Install agentgateway CRDs + control plane

```bash
helm upgrade -i agentgateway-crds \
  oci://cr.agentgateway.dev/charts/agentgateway-crds \
  --create-namespace \
  --namespace agentgateway-system \
  --version v1.0.1

helm upgrade -i agentgateway \
  oci://cr.agentgateway.dev/charts/agentgateway \
  --namespace agentgateway-system \
  --version v1.0.1 \
  --wait --timeout 180s
```

### Create the OpenAI secret

```bash
kubectl create secret generic openai-secret \
  -n agentgateway-system \
  --from-literal=Authorization="Bearer ${OPENAI_API_KEY}" \
  --dry-run=client -o yaml | kubectl apply -f -
```

### Apply gateway resources

```bash
kubectl apply -f gateway/gateway.yaml
kubectl apply -f gateway/openai-backend.yaml
kubectl apply -f gateway/openai-route.yaml
```

Or if you prefer to apply them inline:

```bash
# Gateway listener
cat <<'EOF' | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: ai-gateway
  namespace: agentgateway-system
spec:
  gatewayClassName: agentgateway
  listeners:
  - protocol: HTTP
    port: 80
    name: http
    allowedRoutes:
      namespaces:
        from: All
EOF

# OpenAI backend
cat <<'EOF' | kubectl apply -f -
apiVersion: agentgateway.dev/v1alpha1
kind: AgentgatewayBackend
metadata:
  name: openai
  namespace: agentgateway-system
spec:
  ai:
    provider:
      openai:
        model: gpt-5.4-mini-2026-03-17
  policies:
    auth:
      secretRef:
        name: openai-secret
EOF

# Route /openai traffic to the backend
cat <<'EOF' | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: openai
  namespace: agentgateway-system
spec:
  parentRefs:
  - name: ai-gateway
    namespace: agentgateway-system
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /openai
    backendRefs:
    - name: openai
      namespace: agentgateway-system
      group: agentgateway.dev
      kind: AgentgatewayBackend
EOF
```

Verify:
```bash
kubectl get gateway,agentgatewaybackend,httproute -n agentgateway-system
kubectl get pods -n agentgateway-system
```

Wait for the proxy pod:
```bash
kubectl get deploy -n agentgateway-system
```

You should see the agentgateway controller and a gateway proxy deployment.

---

## Step 4: Install kagent

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
  --set providers.openAI.model=gpt-5.4-mini-2026-03-17 \
  --set otel.tracing.enabled=true \
  --set otel.tracing.exporter.otlp.endpoint="agentevals.default.svc.cluster.local:4317" \
  --set otel.tracing.exporter.otlp.insecure=true \
  --set otel.tracing.exporter.otlp.protocol="grpc" \
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

### Route kagent through agentgateway

Patch the ModelConfig so all LLM requests flow through the gateway:

```bash
# Find the gateway proxy service name
kubectl get svc -n agentgateway-system

# Patch ModelConfig with the gateway URL
kubectl patch modelconfig default-model-config -n kagent \
  --type merge \
  -p '{"spec":{"baseUrl":"http://ai-gateway.agentgateway-system.svc:80/openai/v1"}}'
```

> **Note:** The service name `ai-gateway` matches the Gateway resource name. If your proxy service has a different name, adjust the URL accordingly. Check with `kubectl get svc -n agentgateway-system`.

Verify the patch:
```bash
kubectl get modelconfig default-model-config -n kagent -o yaml | grep baseUrl
```

---

## Step 5: Install agentregistry

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

## Step 6: Set Up Port-Forwards

```bash
# Kill any existing port-forwards
pkill -f "port-forward.*agentevals" 2>/dev/null || true
pkill -f "port-forward.*kagent" 2>/dev/null || true
pkill -f "port-forward.*agentgateway" 2>/dev/null || true

# agentevals UI + OTLP
kubectl port-forward svc/agentevals -n default 8001:8001 &>/dev/null &
kubectl port-forward svc/agentevals -n default 4317:4317 &>/dev/null &

# kagent API + UI (note: kagent-ui listens on port 8080 internally)
kubectl port-forward svc/kagent-controller -n kagent 8083:8083 &>/dev/null &
kubectl port-forward svc/kagent-ui -n kagent 8082:8080 &>/dev/null &

# agentgateway proxy (find the proxy service dynamically)
GW_SVC=$(kubectl get svc -n agentgateway-system -o name | grep -v controller | head -1 | sed 's|service/||')
kubectl port-forward "svc/${GW_SVC}" -n agentgateway-system 9090:80 &>/dev/null &
```

> **agentregistry** is exposed via NodePort — no port-forward needed. It's at `http://localhost:12121`.

Test connectivity:
```bash
curl -s http://localhost:8083/api/agents | python3 -m json.tool
curl -s http://localhost:12121/v0/skills | python3 -m json.tool
curl -s http://localhost:9090/openai/v1/models 2>/dev/null || echo "(gateway test)"
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
| agentgateway proxy | http://localhost:9090 |
| agentregistry | http://localhost:12121 |

---

## Step 7: Team A — Deploy Specialist Agents

Team A (SRE) builds and deploys the specialist agents — the building blocks.

First confirm the auto-created resources exist:
```bash
kubectl get modelconfig default-model-config -n kagent
kubectl get remotemcpserver kagent-tool-server -n kagent
```

Deploy the two specialist agents:
```bash
kubectl apply -f agents/01-deploy-agent.yaml
kubectl apply -f agents/02-healthcheck-agent.yaml
```

Verify:
```bash
kubectl get agents -n kagent
curl -s http://localhost:8083/api/agents | python3 -m json.tool
```

You should see 2 agents:
- **k8s-deploy-agent** — 6 MCP tools, deploys with dry-run validation
- **k8s-healthcheck-agent** — 5 read-only diagnostic tools

---

## Step 8: Team A — Test the Specialists

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

## Step 9: Team A — Register in agentregistry

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
    "modelName": "gpt-5.4-mini-2026-03-17"
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
    "modelName": "gpt-5.4-mini-2026-03-17"
  }' | python3 -m json.tool

```

### Register MCP Servers + agentgateway

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

# Register agentgateway
curl -s -X POST http://localhost:12121/v0/servers \
  -H "Content-Type: application/json" \
  -d '{
    "$schema": "https://static.modelcontextprotocol.io/schemas/2025-10-17/server.schema.json",
    "name": "agentgateway-dev/agentgateway",
    "version": "1.0.1",
    "title": "agentgateway",
    "description": "AI-native proxy for LLM, MCP, and A2A traffic with security policies, observability, and cost controls."
  }' | python3 -m json.tool
```

### Verify

```bash
# Should show 2 skills (k8s-deploy, k8s-healthcheck)
curl -s http://localhost:12121/v0/skills | python3 -m json.tool

# Should show 2 agents (k8s-deploy-agent, k8s-healthcheck-agent)
curl -s http://localhost:12121/v0/agents | python3 -m json.tool

# Should show 3 servers (kagent-tool-server, kagent-grafana-mcp, agentgateway)
curl -s http://localhost:12121/v0/servers | python3 -m json.tool
```

Browse the catalog at http://localhost:12121 — you should see Team A's 2 skills and 2 agents. No incident agent yet.

---

## Step 10: Team B — Discover & Compose the Incident Agent

Team B (Platform Engineering) searches the catalog, finds Team A's work, and composes a higher-level agent.

### Search the registry

```bash
# What kubernetes skills are available?
curl -s "http://localhost:12121/v0/skills?search=kubernetes" | python3 -m json.tool

# What agents are available?
curl -s http://localhost:12121/v0/agents | python3 -m json.tool
```

Team B finds two specialist agents built by Team A. They compose them into an incident response agent:

### Deploy the incident agent

```bash
cat agents/03-incident-agent.yaml
```

Note the tools section — it uses `type: Agent` to orchestrate Team A's agents:
```yaml
tools:
  - type: Agent
    agent:
      name: k8s-deploy-agent
  - type: Agent
    agent:
      name: k8s-healthcheck-agent
```

```bash
kubectl apply -f agents/03-incident-agent.yaml
```

Verify:
```bash
kubectl get agents -n kagent
```

Team B didn't write a single kubectl command in their agent. They composed it from skills that already existed in the registry.

### Team B registers their work back in the catalog

```bash
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
    "modelName": "gpt-5.4-mini-2026-03-17"
  }' | python3 -m json.tool
```

Now the registry has all 3 skills and 3 agents. Browse http://localhost:12121 to verify.

---

## Step 11: Run Agents & View Traces

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
| curl to :8083 fails | Re-run port-forwards (Step 6) or `source ./scripts/ensure-portforward.sh` |
| No traces in agentevals | Check kagent OTel config: `kubectl get pods -n kagent` and logs |
| agentregistry :12121 down | `kubectl get pods -n agentregistry` — check for CrashLoopBackOff |
| agentregistry CrashLoopBackOff | Likely pgvector issue — ensure you used the pgvector image flags |
| agentgateway proxy not ready | `kubectl get gateway,deploy -n agentgateway-system` |
| LLM calls failing through gateway | Check: `kubectl logs -l app.kubernetes.io/name=agentgateway -n agentgateway-system` |
| kind OOM | Docker Desktop → Resources → 8GB+ RAM |
| Helm OCI 403 | `echo $GH_TOKEN | helm registry login ghcr.io -u x --password-stdin` |
