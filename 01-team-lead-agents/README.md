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
./setup.sh
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
- Configure env vars $GITHUB_USERNAME and $GITHUB_REPO

**Deploy GitHub MCP Server:**
```bash
export GITHUB_PERSONAL_ACCESS_TOKEN="your-token-here"
```

Then:
```bash
envsubst < gh-mcp-server.yaml | kubectl apply -f -
```

### 4. Deploy Agents
Make sure you have the GITHUB_USERNAME and GITHUB_REPO environment variables defined, pointing to the repository where issues and PRs are to be created, then:

```shell
for agent_file in agents/*.yaml; do
  envsubst < "$agent_file" | kubectl apply -f -
done
```

If you happened to deploy kagent with the minimal profile (no agents), then deploy the `k8s-agent` too:

```shell
kubectl apply -f k8s-agent.yaml
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
├── setup.sh            # Creates kind cluster
├── verify-setup.sh     # Verifies everything is working
├── kind-config.yaml    # Cluster configuration
├── agents/             # All agent YAML files
│   ├── github-issues-agent.yaml
│   ├── github-pr-agent.yaml
│   └── teamlead-agent.yaml
└── slack/              # Optional Slack integration
```

## Verify Setup

Before running the demo, verify everything is working:
```bash
./verify-setup.sh
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
