# A Central Catalog for AI Artifacts with agentregistry

Docs: https://aregistry.ai/docs/mcp/

**Demo flow:**

- **Part 1 — MCP locally:** install agentregistry, build an MCP server, publish it to the catalog, deploy it locally, and connect it to Claude Code.
- **Part 2 — Kubernetes + kagent:** run agentregistry in a Kubernetes cluster, build an agent, publish it to the registry, and deploy it with kagent.

---

# Part 1 — MCP Server Locally

## 1. Install agentregistry locally

```bash
docker login

curl -fsSL https://raw.githubusercontent.com/agentregistry-dev/agentregistry/main/scripts/get-arctl | bash

arctl daemon start

arctl version
```

## 2. Create an MCP server

```bash
arctl mcp init python my-mcp-server
```

View the scaffold:

```bash
tree my-mcp-server
```

Explain the files:

| File | Description |
|------|-------------|
| Dockerfile | The Dockerfile to spin up and run your MCP server in a containerized environment. |
| mcp.yaml | The MCP server configuration file that defines server metadata, transport settings, version, and other server-specific configuration. |
| pyproject.toml | The Python project configuration file that defines project dependencies, build settings, and metadata for the MCP server. |
| README.md | An introduction to the MCP server that you created with instructions for how to further customize it. |
| src | A directory that contains the details of the MCP server, such as supported tools and the Python script to bootstrap and run the server. |
| tests | A directory that contains generated tests. |

## 3. Add a tool

Scaffold an `add_number` tool (creates `src/tools/add_number.py`):

```bash
arctl mcp add-tool add_number --project-dir my-mcp-server
```

Edit the tool to add two numbers:

```python
@mcp.tool()
def add_numbers(a: float, b: float) -> str:
    """Add two numbers together and return the result.

    Args:
        a: The first number to add.
        b: The second number to add.

    Returns:
        A string representing the sum of the two numbers.
    """
    result = a + b
    return int(result)
```

## 4. Build and run

```bash
arctl mcp build my-mcp-server --image my-mcp-server

arctl mcp run my-mcp-server
```

Note the MCP server URL in the output, e.g. `MCP Server URL: http://localhost:57196/mcp`

### Test with MCP Inspector

```bash
npx modelcontextprotocol/inspector
```

- Transport type: **Streamable HTTP**
- URL: the MCP server URL from above (e.g. `http://localhost:57196/mcp`)
- Click **Connect** → Tools tab → run `add_number` with 5 and 3 → verify 8

## 5. Publish the MCP server to agentregistry

```bash
arctl mcp publish my-mcp-server \
  --type oci \
  --package-id my-mcp-server
```

Verify the catalog entry:

```bash
arctl mcp list
```

```
NAME                 VERSION   TYPE   DEPLOYED   UPDATED
user/my-mcp-server   0.1.0     oci    False      37s
```

Optional: open the agentregistry UI → **Servers** view to show the catalog entry.

## 6. Deploy the MCP server locally

```bash
arctl deployments create user/my-mcp-server \
  --type mcp \
  --version 0.1.0
```

Output gives you the Agent Gateway endpoint:

```
Deployed user/my-mcp-server (v0.1.0) with providerId=local
Agent Gateway endpoint: http://localhost:21212/mcp
```

## 7. Connect the MCP server to Claude Code locally

Add the deployed MCP server to Claude Code using the Agent Gateway endpoint:

```bash
claude mcp add --transport http my-mcp-server http://localhost:21212/mcp
```

Verify it's connected:

```bash
claude mcp list
```

Then start Claude Code and test the tool:

```bash
claude
```

- Run `/mcp` to confirm `my-mcp-server` is connected and the tools are listed
- Ask: "use the add_numbers tool to add 5 and 3"

### Alternative: Claude Desktop

Add to `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "my-mcp-server": {
      "command": "npx",
      "args": ["mcp-remote", "http://localhost:21212/mcp"]
    }
  }
}
```

Restart Claude Desktop and verify the tools appear under the tools icon.

---

# Part 2 — Kubernetes + kagent Integration

Here we manage agents in a Kubernetes environment with agentregistry and kagent.

## 1. Create a cluster

```bash
kind create cluster --name agentregistry

kubectl config get-contexts
```

## 2. Install agentregistry with Helm

```bash
helm upgrade -i agentregistry oci://ghcr.io/agentregistry-dev/agentregistry/charts/agentregistry \
    --namespace agentregistry \
    --create-namespace \
    --set config.jwtPrivateKey=$(openssl rand -hex 32) \
    --set image.tag=v0.3.3 \
    --set database.host=postgres-pgvector.agentregistry.svc.cluster.local \
    --set database.password=agentregistry \
    --set database.sslMode=disable
```

Port-forward the registry:

```bash
kubectl -n agentregistry port-forward svc/agentregistry 12121:12121
```

## 3. Install kagent (OSS)

```bash
export OPENAI_API_KEY="your-api-key-here"

helm install kagent-crds oci://ghcr.io/kagent-dev/kagent/helm/kagent-crds \
    --namespace kagent \
    --create-namespace

helm install kagent oci://ghcr.io/kagent-dev/kagent/helm/kagent \
    --namespace kagent \
    --set providers.default=openAI \
    --set providers.openAI.apiKey=$OPENAI_API_KEY
```

Open the kagent UI:

```bash
kubectl port-forward -n kagent svc/kagent-ui 8080:8080
```

## 4. Build the agent

```bash
arctl agent init adk python myagent --model-provider openai --model-name gpt-5.4
```

Explain the scaffold:

| File | Description |
|------|-------------|
| agent.yaml | The agent definition. This definition holds the registry location and version tag that you want to use when building and pushing the image to your registry. It also adds the MCP server references that you added to the agent. |
| docker-compose.yaml | A Docker compose file that is used to spin up and run your agent when you use the `arctl agent run` command. |
| Dockerfile | The Dockerfile to spin up and run your agent in a containerized environment. |
| myagent | A directory that includes the `agent.py` script that defines the agent, including the provider and model that you want to use. The directory also includes the agent card for agent discovery. |
| pyproject.toml | The dependency definition of your agent. |
| README.md | An introduction to the agent that you created with instructions for how to further customize it. |

Run the agent locally:

```bash
arctl agent run myagent
```

## 5. Publish the agent

```bash
arctl agent build myagent

arctl agent publish myagent

arctl agent list
```

## 6. Deploy the agent to Kubernetes with kagent

```bash
arctl deployments create myagent \
 --type agent \
 --provider-id kubernetes-default \
 --namespace kagent
```

Verify the deployment:

```bash
kubectl get pods | grep myagent

kubectl get agent -o yaml
```

---

# Cleanup

```bash
arctl deployments list
arctl deployments delete <deployment-ID>

arctl mcp delete user/my-mcp-server --version 0.1.0
```
