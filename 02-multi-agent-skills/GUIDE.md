# Multi-Agent Skills: Build, Register, Evaluate

> Build 3 multi-agents with skills in kagent, register them in AgentRegistry, route LLM traffic through agentgateway, and evaluate them with AgentEvals — all in a kind cluster.

## Prerequisites

Only 4 tools needed locally:

| Tool | Install |
|------|---------|
| Docker Desktop (8GB+ RAM) | [docker.com](https://docker.com) |
| kind | `brew install kind` |
| kubectl | `brew install kubectl` |
| Helm 3 | `brew install helm` |

Plus an OpenAI API key: `export OPENAI_API_KEY='sk-...'`

> **No other CLIs needed.** kagent, agentgateway, agentregistry, and agentevals all run in-cluster with web UIs and REST APIs.

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                     kind cluster                              │
│                                                               │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │ kagent (ns: kagent)                                     │ │
│  │                                                         │ │
│  │  incident-response-agent                                │ │
│  │    ├── calls → k8s-deploy-agent (6 MCP tools)          │ │
│  │    └── calls → k8s-healthcheck-agent (5 MCP tools)     │ │
│  │                                                         │ │
│  │  Model: gpt-5.4-mini  |  OTel tracing → agentevals     │ │
│  │  LLM traffic → agentgateway → OpenAI                   │ │
│  └─────────────────────────────────────────────────────────┘ │
│                                                               │
│  ┌──────────────────────┐  ┌──────────────────────────────┐ │
│  │ agentgateway         │  │ agentregistry                │ │
│  │ (ns: agentgateway-   │  │ (ns: agentregistry)          │ │
│  │  system)              │  │ REST API :12121              │ │
│  │ LLM proxy :80         │  └──────────────────────────────┘ │
│  │ Gateway API CRDs     │                                    │
│  └──────────────────────┘  ┌──────────────────────────────┐ │
│                             │ agentevals (ns: default)     │ │
│                             │ OTLP receiver :4318          │ │
│                             │ Web UI + API :8001           │ │
│                             └──────────────────────────────┘ │
└──────────────────────────────────────────────────────────────┘
```

## Quick Start

```bash
export OPENAI_API_KEY='sk-...'

./scripts/01-setup-kind.sh        # Create kind cluster
./scripts/02-install-stack.sh     # Install kagent, agentgateway, agentregistry, agentevals
./scripts/03-deploy-agents.sh     # Team A: deploy specialist agents
./scripts/04-register-agents.sh   # Team A: register skills, agents, servers in catalog
./scripts/05-compose-agent.sh     # Team B: discover skills, compose incident agent
./scripts/06-run-and-eval.sh      # Run agents, view traces, evaluate
```

If you restart your terminal:
```bash
source ./scripts/ensure-portforward.sh
```

## Access Points

| Service | URL | How |
|---------|-----|-----|
| kagent UI | http://localhost:8082 | Chat with agents interactively |
| kagent API | http://localhost:8083 | REST + A2A protocol |
| agentgateway proxy | http://localhost:9090 | LLM/MCP/A2A proxy |
| agentregistry | http://localhost:12121 | Skill catalog (NodePort) |
| agentevals | http://localhost:8001 | Trace viewer + eval engine |

## The 3 Agents

| Agent | Role | Tools | Skill (from git) |
|-------|------|-------|------|
| `k8s-deploy-agent` | Deployment specialist | `k8s_apply_manifest`, `k8s_get_resources`, `k8s_get_events`, `k8s_get_pod_logs`, `k8s_describe_resource`, `k8s_delete_resource` | `k8s-deploy` |
| `k8s-healthcheck-agent` | Health diagnostics | `k8s_get_resources`, `k8s_describe_resource`, `k8s_get_resource_yaml`, `k8s_get_events`, `k8s_get_pod_logs` | `k8s-healthcheck` |
| `incident-response-agent` | Orchestrator | `k8s-deploy-agent`, `k8s-healthcheck-agent` (agent-as-tool) | `incident-response` |

Each agent pulls its skill from git via `spec.skills.gitRefs` — kagent's init container clones the repo and mounts the SKILL.md into the pod at deploy time.

## The Full Stack

| Component | Role | Project |
|-----------|------|---------|
| **kagent** | Build & run Kubernetes-native AI agents | [kagent.dev](https://kagent.dev) |
| **agentgateway** | Govern LLM, MCP, and A2A traffic | [agentgateway.dev](https://agentgateway.dev) |
| **agentregistry** | Discover & share skills across teams | [agentregistry](https://github.com/agentregistry-dev/agentregistry) |
| **agentevals** | Trust & verify with OTel traces + evals | [agentevals](https://github.com/agentevals-dev/agentevals) |

## How to Interact (No CLIs)

### Chat via kagent UI
Open http://localhost:8082, click an agent, start chatting.

### Invoke via curl (A2A protocol)
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
        "parts": [{"kind": "text", "text": "Check health of pods in default namespace"}]
      }
    }
  }'
```

### List agents via API
```bash
curl -s http://localhost:8083/api/agents | python3 -m json.tool
```

### Test the gateway proxy
```bash
curl -s http://localhost:9090/openai/v1/models
```

### Register skills via API
```bash
curl -X POST http://localhost:12121/v0/skills \
  -H "Content-Type: application/json" \
  -d '{
    "name": "k8s-deploy",
    "description": "Deploy with dry-run validation and rollback",
    "version": "1.0.0",
    "category": "kubernetes",
    "repository": {"url": "https://github.com/...", "source": "github"}
  }'
```

### Browse skills
```bash
curl -s http://localhost:12121/v0/skills | python3 -m json.tool
curl -s "http://localhost:12121/v0/skills?search=kubernetes"
```

### View traces + run evals
Open http://localhost:8001 — traces flow automatically from kagent via OTLP.

---

## Cleanup

```bash
pkill -f "port-forward" 2>/dev/null || true
kind delete cluster --name multi-agent-demo
rm -rf .tmp/
```

## Troubleshooting

| Issue | Fix |
|-------|-----|
| curl to :8083 fails | `source ./scripts/ensure-portforward.sh` |
| No traces in agentevals | Check: `kubectl logs -l app.kubernetes.io/name=agentevals` |
| agentregistry :12121 down | Check: `kubectl get pods -n agentregistry` |
| agentgateway proxy not ready | Check: `kubectl get gateway,deploy -n agentgateway-system` |
| Helm OCI pull 403 | `echo $GH_TOKEN \| helm registry login ghcr.io -u x --password-stdin` |
| kind OOM | Docker Desktop → Resources → 8GB+ RAM |
| PVC stuck Pending | `kubectl get sc` — kind has `standard` by default |

## Links

- [kagent.dev](https://kagent.dev)
- [agentgateway.dev](https://agentgateway.dev)
- [agentregistry](https://github.com/agentregistry-dev/agentregistry)
- [agentevals](https://github.com/agentevals-dev/agentevals)
