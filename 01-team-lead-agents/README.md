# AI Team Lead Agent Demo

Demo of AI agents that automatically diagnose Kubernetes issues and create comprehensive GitHub issues with full documentation.

## What This Does

You deploy a broken pod → Ask the AI agent "why is it failing?" → Agent investigates, finds the issue, and creates a detailed GitHub issue with logs, root cause, and proposed fix.

## Quick Setup

### Prerequisites
- Docker Desktop
- [kind](https://kind.sigs.k8s.io/)
- [Helm](https://helm.sh/)
- kubectl
- OpenAI API key
- GitHub Personal Access Token

### 1. Create Cluster
```bash
kind create cluster --name kagent-oss-demo --config kind-config.yaml

# Wait for cluster to be ready
kubectl -n kube-system rollout status deploy/coredns
kubectl -n local-path-storage rollout status deploy/local-path-provisioner
```

### 2. Install kagent
```bash
export OPENAI_API_KEY="your-key-here"

helm install kagent-crds oci://ghcr.io/kagent-dev/kagent/helm/kagent-crds \
    --namespace kagent --create-namespace

helm install kagent oci://ghcr.io/kagent-dev/kagent/helm/kagent \
    --namespace kagent \
    --set providers.default=openAI \
    --set providers.openAI.apiKey=$OPENAI_API_KEY

kubectl wait --for=condition=ready pod -l app=kagent -n kagent --timeout=300s
```

### 3. Configure GitHub
**Edit `agents/github-issues-agent.yaml`, `agents/github-pr-agent.yaml`, and `agents/teamlead-agent.yaml`:**
- Replace `sebbycorp/ai-kagent-demo` with your repo: `YOUR_USERNAME/YOUR_REPO`

**Deploy GitHub MCP Server:**
```bash
export GITHUB_PERSONAL_ACCESS_TOKEN="your-token-here"

kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: github-pat
  namespace: kagent
type: Opaque
stringData:
  GITHUB_PERSONAL_ACCESS_TOKEN: $GITHUB_PERSONAL_ACCESS_TOKEN
---
apiVersion: kagent.dev/v1alpha2
kind: RemoteMCPServer
metadata:
  name: github-mcp-remote
  namespace: kagent
spec:
  description: GitHub Copilot MCP Server
  url: https://api.githubcopilot.com/mcp/
  protocol: STREAMABLE_HTTP
  headersFrom:
    - name: Authorization
      valueFrom:
        type: Secret
        name: github-pat
        key: GITHUB_PERSONAL_ACCESS_TOKEN
  timeout: 5s
  terminateOnClose: true
EOF
```

### 4. Deploy Agents
```bash
kubectl apply -f agents/
```

### 5. Start UI
```bash
kubectl port-forward svc/kagent-ui -n kagent 8080:8080
```
Open: http://localhost:8080

### 6. Run Demo

**Deploy broken pod:**
```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: ngi14
spec:
  containers:
  - name: nginx
    image: nginx:latesttttt
    ports:
    - containerPort: 80
EOF
```

**In the kagent UI, go to `team-lead-agent` and ask:**
```
Why is the Nginx Pod failing in my default namespace?
If there is an issue, create a GitHub issue with all details.
```

The agent will:
1. Investigate the pod using the k8s-agent
2. Find the issue (typo in image tag)
3. Create a comprehensive GitHub issue with logs, events, root cause, and proposed fix

Check your GitHub repo for the new issue!

## Project Structure

```
├── README.md           # This file
├── kind-config.yaml    # Cluster configuration
├── agents/             # All agent YAML files
│   ├── github-issues-agent.yaml
│   ├── github-pr-agent.yaml
│   └── teamlead-agent.yaml
└── slack/              # Optional Slack integration
```

## Verify Setup

Check that everything is ready:
```bash
kubectl get nodes
kubectl get pods -n kagent
kubectl get agents -n kagent
kubectl get remotemcpserver -n kagent
```

## Try These Prompts

```
Create a PR to fix the nginx pod issue
```

```
Check all pods in the default namespace and report any problems
```

```
List all high-priority GitHub issues and summarize them
```

## Clean Up

```bash
kubectl delete pod ngi14
kind delete cluster --name kagent-oss-demo
```

## Architecture

```
User → Team Lead Agent → K8s Agent (diagnose) → GitHub Issues Agent (document)
                       → GitHub PR Agent (fix)
```

The **Team Lead Agent** orchestrates specialized agents:
- **k8s-agent**: Kubernetes troubleshooting
- **github-issues-agent**: Creates comprehensive issues
- **github-pr-agent**: Creates and reviews PRs

## Resources

- [kagent Docs](https://kagent.dev/docs)
- [Model Context Protocol](https://modelcontextprotocol.io)

---

**Bonus:** Check the `slack/` folder for Slack integration setup.
