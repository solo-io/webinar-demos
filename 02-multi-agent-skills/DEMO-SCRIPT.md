# Multi-Agent Skills Demo Script

> **Duration:** ~35 minutes
> **Audience:** Platform engineers, DevOps, SRE
> **Pre-req:** Docker Desktop (8GB+ RAM), kind, kubectl, helm, `OPENAI_API_KEY`
> **Stack:** kagent + agentgateway + agentregistry + agentevals — all in a kind cluster

---

## The Story

Meet two teams.

**Team A** is the SRE team. They're the ones who get paged at 2am. They know Kubernetes inside and out — the exact kubectl commands to run, in what order, what to look for. They've been doing this for years. The problem is, that knowledge lives in their heads. When someone leaves, the knowledge leaves with them. When the new hire joins, they spend months learning what the senior engineers already know.

**Team B** is the platform engineering team. They're building automation for the whole org. They don't want to become Kubernetes experts — they want to *use* the expertise that already exists. They want to wire things together, not reinvent the wheel.

Today, Team A is going to capture their expertise as **skills** — portable, versioned, executable. They'll build specialist agents and share them through a catalog.

Then Team B is going to search that catalog, discover what Team A built, and compose it into something bigger — an incident response agent that coordinates the specialists. Team B never writes a single kubectl command. They just wire together what's already there.

All of it runs through **agentgateway** — an AI-native proxy that governs every LLM call, every MCP tool invocation, every agent-to-agent message. No direct calls to OpenAI. Everything observable, everything governed.

That's the demo. Two teams. Shared skills. Multi-agent composition. Full-stack governance. Let's go.

---

## Pre-Demo Setup (do this before the audience joins)

```bash
export OPENAI_API_KEY='sk-...'
./scripts/01-setup-kind.sh
./scripts/02-install-stack.sh
```

Verify the stack:
```bash
kubectl get pods -n kagent
kubectl get pods -n agentgateway-system
kubectl get pods -n agentregistry
kubectl get pods -n default -l app.kubernetes.io/name=agentevals
```

If you restarted your terminal:
```bash
source ./scripts/ensure-portforward.sh
```

---

## SCENE 1: The World We Live In (~3 min)

> **Goal:** Connect with the audience. This isn't abstract — they've lived this.

"Quick show of hands. Who here has been paged at 2am in the last year?"

*(wait for hands)*

"And what did you do? You opened a terminal. `kubectl get pods`. `kubectl describe deployment`. `kubectl logs`. Maybe you know exactly which five commands to run, in what order, because you've done it a hundred times.

Now — does the person sitting next to you know those same five commands? Does the new hire who started last month? When you go on vacation, does your team scramble?

We talk about infrastructure as code. But the *expertise* — the 'check events before logs because it's faster,' the 'always do a dry-run before apply' — that still lives in people's heads. And heads leave the company.

What if we could turn that expertise into something shareable? Something that lives in a catalog, not a Slack thread? Something any agent, on any team, can pick up and use?

That's what we're building today."

---

## SCENE 2: The Full Stack (~3 min)

> **Goal:** Briefly show what's running. Four components, one cluster.

"Before we start building, let me show you what's running. Everything is in a kind cluster on my laptop. Four components, all open source."

**[SHOW SLIDE: The Stack]**

"**kagent** — Kubernetes-native AI agents. CRDs. `kubectl apply`. MCP tools. OTel tracing built-in.

**agentgateway** — the AI-native proxy. Every LLM call, every MCP tool invocation, every agent-to-agent message flows through it. Think of it as Envoy for AI traffic. Security policies, observability, cost controls.

**agentregistry** — the skill catalog. Like Artifact Hub, but for AI. Register skills, agents, MCP servers. Search and discover.

**agentevals** — trust and verify. OTel traces. Golden paths. Trajectory scoring. CI/CD integration.

The key thing — no local CLIs beyond kubectl and helm. Everything runs in-cluster with web UIs and REST APIs.

Let me show you the architecture."

```bash
kubectl get pods -n agentgateway-system
kubectl get gateway ai-gateway -n agentgateway-system
```

"See that? agentgateway is running. It has a Gateway resource — standard Kubernetes Gateway API — with an OpenAI backend. Every LLM call from our agents will flow through this gateway. No direct calls to OpenAI."

---

## SCENE 3: Team A Builds the Specialists (~8 min)

> **Goal:** The SRE team captures their expertise as skills and builds specialist agents.

"So here's Team A. They're the SRE team. They know Kubernetes cold. And they're tired of being the only ones who can diagnose a failing deployment at 2am.

So they do something smart. They write down *exactly* how they triage an incident — not the hand-wavy version, the actual steps — and they turn it into a skill."

#### Show the healthcheck skill

```bash
cat skills/k8s-healthcheck/SKILL.md
```

"This is a skill. Structured markdown. It says: here are your tools — `k8s_get_resources`, `k8s_describe_resource`, `k8s_get_pod_logs`. Here's the sequence: check pods first, then conditions, then events, then logs if something looks wrong. Here's how to format the report.

This is Maria's brain. Maria's your senior SRE. She's been doing this for eight years. She knows things like 'always check events before diving into logs' and 'if pods are pending, check node resources, not the deployment.' That knowledge is now in this file.

And the key thing — **this skill is portable**. It's not buried in one agent's config. It's not locked to one team. Anyone can use it."

#### Show the agent CRD

```bash
cat agents/02-healthcheck-agent.yaml
```

"Now the agent. This is a Kubernetes custom resource — `kagent.dev/v1alpha2`. If you can write a Deployment YAML, you can write this. Look at this:

```yaml
skills:
  gitRefs:
    - url: https://github.com/solo-io/webinar-demos
      ref: main
      path: 02-multi-agent-skills/skills/k8s-healthcheck
      name: k8s-healthcheck
```

The agent pulls its skill straight from git. When kagent deploys this agent, an init container clones the repo, extracts the SKILL.md, and mounts it into the pod. The skill lives in git — versioned, tagged, reviewable. Same GitOps workflow your team already uses.

Model config, tools from the MCP server, skill from git. `kubectl apply` and it's running."

#### Deploy the specialists

```bash
./scripts/03-deploy-agents.sh
```

"Team A deploys two specialist agents:

1. **Healthcheck agent** — five read-only tools. It can look at everything but touch nothing. Like a doctor who examines but doesn't operate.
2. **Deploy agent** — six tools including `k8s_apply_manifest`. It can actually change things. But it validates first — dry-run before apply, rollout status after.

One reads. One writes. That's deliberate. You don't want your diagnostic tool accidentally deleting pods."

#### Deploy a test workload and try it

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

**[OPEN BROWSER: http://localhost:8082]**

- Click on `k8s-healthcheck-agent`
- Type: **"Check the health of the nginx-demo deployment in default namespace"**

*(While it runs, narrate)*

"Watch what's happening. It's doing exactly what Maria would do. Get the pods. Describe the deployment. Check events. But it does it in ten seconds, and the output is structured.

No Python installed. No pip. No CLI. The agent runs inside the cluster. Maria's expertise is running 24/7, not just when she's on-call.

And here's the thing — every one of those LLM calls just flowed through agentgateway. We didn't configure anything special in the agent. The ModelConfig points to the gateway, and the gateway routes to OpenAI. Governed. Observable. One line of config.

Now — this is great for Team A. But what about everyone else?"

---

## SCENE 4: Team A Shares Their Work (~6 min)

> **Goal:** Team A registers their skills so other teams can discover them. The registry is the bridge between teams.

"Team A has working agents. Working skills. But right now, they live in a Git repo that only Team A knows about. The platform team doesn't know these exist. The networking team is about to spend three weeks building their own healthcheck automation — because nobody told them it already exists.

Sound familiar? This is the Helm chart problem all over again. Before Artifact Hub, everyone was copy-pasting charts from random repos. We solved it with registries.

Skills need the same thing."

#### Register skills, agents, and servers

```bash
./scripts/04-register-agents.sh
```

"Team A registers everything. Skills, agents, MCP servers, and agentgateway itself. Just REST API calls — `POST /v0/skills`, `POST /v0/agents`, `POST /v0/servers`. Name, description, version, repo URL. Like pushing a container image to a registry.

And notice — the skills point back to the git repo. When someone finds the skill in the catalog, they get the repo URL. They can add it to their own agent's `gitRefs` and kagent pulls it automatically. No copy-paste. No Slack thread. Git URL. Done."

#### Browse the registry

**[OPEN BROWSER: http://localhost:12121]**

- Show the skills with descriptions and versions
- Show the agents — framework, model, descriptions
- Show the servers — including agentgateway
- Click into k8s-healthcheck skill

"This is agentregistry. Think of it like Artifact Hub, but for AI.

Right now it has Team A's work. Two skills. Two agents. Three servers — the MCP tool server, Grafana MCP, and agentgateway.

This is the catalog. This is how Team B is going to find what they need."

---

## SCENE 5: Team B Discovers & Composes (~8 min)

> **Goal:** The payoff. Team B never touches kubectl. They find what exists and wire it together.

"Now let's switch hats. We're Team B — the platform engineering team. We've been asked to build incident response automation. We don't know Kubernetes at the level Team A does. We don't *want* to. We want to use what already exists.

So the first thing we do? We search the catalog."

#### Search the registry

```bash
curl -s "http://localhost:12121/v0/skills?search=kubernetes" | python3 -m json.tool
```

"Look at that. Two Kubernetes skills. One for deployment, one for health checks. Both built by Team A. Versioned, documented, battle-tested.

Let's see what agents are available."

```bash
curl -s http://localhost:12121/v0/agents | python3 -m json.tool
```

"Two specialist agents. One reads, one writes. Exactly what we need for incident response — someone to diagnose, someone to fix.

Here's the beautiful thing. Team B doesn't need to understand how `k8s_get_resources` works. They don't need to know the diagnostic sequence Maria built into the healthcheck skill. They just need to know: *this agent can diagnose*, and *this agent can deploy*.

So Team B builds the orchestrator."

#### Show the incident agent

```bash
cat agents/03-incident-agent.yaml
```

"Look at the tools:

```yaml
tools:
  - type: Agent
    agent:
      name: k8s-deploy-agent
  - type: Agent
    agent:
      name: k8s-healthcheck-agent
```

Team B's agent doesn't know kubectl. Its tools *are Team A's agents*. `type: Agent`. It knows how to coordinate. 'Diagnose first. What did you find? Do we need to remediate? Yes — call the deploy agent. Now verify again.'

It's an incident commander. It delegates to specialists it found in the catalog."

#### Register the incident agent in the catalog first

```bash
./scripts/05-compose-agent.sh register
```

*(Or if you prefer to show it manually)*

```bash
# Register the incident-response skill
curl -s -X POST http://localhost:12121/v0/skills \
  -H "Content-Type: application/json" \
  -d '{
    "name": "incident-response",
    "description": "Multi-agent incident coordination — triage, investigate, remediate",
    "version": "0.1.0",
    "repo_url": "https://github.com/solo-io/webinar-demos",
    "path": "02-multi-agent-skills/skills/incident-response"
  }'

# Register the incident-response agent
curl -s -X POST http://localhost:12121/v0/agents \
  -H "Content-Type: application/json" \
  -d '{
    "name": "incident-response-agent",
    "description": "Coordinates healthcheck and deploy agents for end-to-end incident response",
    "framework": "kagent",
    "model": "gpt-4o",
    "repo_url": "https://github.com/solo-io/webinar-demos",
    "path": "02-multi-agent-skills/agents/03-incident-agent.yaml"
  }'
```

"Before we deploy anything, we register it. Same flow Team A used. The incident-response skill and agent go into the catalog — now *every* team can discover it. The registry is the single source of truth. If it's not in the catalog, it doesn't exist."

**[OPEN BROWSER: http://localhost:12121]**

- Refresh the registry
- Show the incident-response skill and agent now listed alongside Team A's work

"Look — Team B's work is right there next to Team A's. Three skills. Three agents. Two teams. One catalog."

#### Now deploy it to kagent

```bash
./scripts/05-compose-agent.sh deploy
```

*(Or if you prefer to show it manually)*

```bash
kubectl apply -f agents/03-incident-agent.yaml
```

"*Now* we deploy. Registry first, then runtime. The agent pulls its skill from the same git repo it was registered with. Same URL. Same version. The catalog told us what exists — kagent makes it run.

**That's the workflow.** Register → Discover → Deploy. Team B just built multi-agent incident response without writing a single kubectl command. They composed it from skills that already existed, registered it back so the *next* team can find it, and deployed it with `kubectl apply`.

**That's the power of shared skills.** Maria left the company two months ago — but her healthcheck expertise is pulled from git and running inside Team B's agent right now. Versioned. Tagged. Auditable. And now Team B's incident-response pattern is in the catalog too — for Team C."

#### Run the incident scenario

**[OPEN BROWSER: http://localhost:8082]**

- Click on `incident-response-agent`
- Type: **"We're seeing 503 errors from nginx-demo in default namespace. Investigate and produce an incident summary."**

*(While it runs — this takes a bit because it's calling sub-agents)*

"Watch the chain. The incident agent calls the healthcheck agent — that's Maria's skill running. The healthcheck agent calls its tools, talks to the Kubernetes API, comes back with findings. The incident agent reads the results, decides what to do next, maybe calls the deploy agent...

Two teams. Three agents. Shared skills. Nobody had to rewrite anything.

And every single LLM call in that chain — the incident agent's reasoning, the healthcheck agent's diagnosis, the deploy agent's actions — all of it flowed through agentgateway. One proxy. Full visibility."

#### Same thing via API

```bash
curl -s -L -X POST http://localhost:8083/api/a2a/kagent/incident-response-agent \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0", "id": "1", "method": "message/send",
    "params": {"message": {"kind": "message", "role": "user",
      "parts": [{"kind": "text", "text": "We are seeing 503 errors from nginx-demo in default namespace. Investigate and produce an incident summary."}]
    }}
  }' | python3 -m json.tool
```

---

## SCENE 6: Trust, But Verify (~7 min)

> **Goal:** The scene most agent demos skip. Make the audience uncomfortable, then show the answer.

"So we've got agents that work. Shared skills. Multi-agent composition. Everything looks great in the demo.

But let me ask you something honestly. Would you trust this at 2am? Not watching it in a demo — *actually* trust it. Let the incident agent run, take action, and go back to sleep?

*(pause)*

Because here's what I've seen. A team builds an agent. Works great in testing. They ship it. Three weeks later, someone notices that 10% of the time, the healthcheck agent skips the event check and jumps straight to 'everything looks fine.' Nobody caught it because the output *looked* right. The agent confidently said 'all healthy' — it just didn't actually look.

You wouldn't ship a microservice without tests. You wouldn't deploy a Helm chart without validation. But with agents, we're all just... hoping?

That's what agentevals solves."

#### Show the live traces

**[OPEN BROWSER: http://localhost:8001]**

- Show the sessions list — every agent call from today is already here
- Click into the incident agent session
- Expand the span tree

"Every agent call we've made today is already here. We set up an OTel Collector as a gRPC-to-HTTP bridge and pointed kagent at it:

```
kagent (gRPC :4317) → OTel Collector → agentevals (HTTP :4318)
```

That's it. OTel traces. Same protocol you use for your microservices.

*(click into the incident agent trace)*

Look at this span tree. The incident agent called the healthcheck agent — there's the span. The healthcheck agent called `k8s_get_resources` — there, with the arguments it passed. Then `k8s_describe_resource`. Then `k8s_get_events`. Every step. Every argument. Every response.

This is the difference between 'the agent said it checked everything' and 'I can *prove* it checked everything.'"

#### The golden path

"Now here's where it gets powerful. This trace — it's a good run. The agent did the right things in the right order. What if we could say: 'that one — that's the golden path. Score every future run against it.'

That's what an **eval set** is."

```bash
cat evals/healthcheck-eval.json
```

"This is ADK format. It says: when someone asks 'check the health of nginx-demo,' the agent should call `k8s_get_resources`, then `k8s_describe_resource`, then `k8s_get_events` — and the final response should mention pod status and health conditions.

You can write these by hand, or create them straight from a trace in the UI. Do a run that looks good, mark it as golden, done."

#### How scoring works

"agentevals has built-in metrics. The ones you'll care about:

- **`tool_trajectory_avg_score`** — did the agent call the right tools in the right order? You can be strict (`EXACT`) or flexible (`IN_ORDER`, `ANY_ORDER`).
- **`response_match_score`** — does the final answer match what we expected?
- **`hallucinations_v1`** — did the agent make up information that isn't in the tool responses?

Remember that 10% failure where the agent skipped the event check? Trajectory scoring catches that instantly. 'Expected: get_resources → describe → get_events. Actual: get_resources → describe. Score: 0.66. FAIL.'

And this runs in CI/CD. You merge a change to your skill? The pipeline runs the agent, sends traces to agentevals, scores them. Failing score blocks the deploy. Same pattern as integration tests — but for agent behavior.

No re-runs. You record the trace once, evaluate as many times as you want."

---

## Closing (~2 min)

> **Goal:** Bring it home. Two teams. Full stack. Full lifecycle.

"Let's go back to where we started. Two teams.

**Team A** — the SRE team — took the expertise that lived in Maria's head and turned it into skills. Structured markdown. Portable. They built specialist agents — one for diagnosis, one for remediation — and deployed them with `kubectl apply`. Then they registered everything in a catalog so other teams could find it.

**Team B** — the platform team — searched that catalog. Found two specialist agents. Didn't write a single kubectl command. They composed an incident response agent that orchestrates the specialists. Maria left two months ago, but her diagnostic sequence is running inside Team B's agent right now.

**agentgateway** governed every LLM call, every tool invocation, every agent-to-agent message in the chain. One proxy. Standard Gateway API. Security, observability, cost controls — the same patterns you already use for your microservices.

**agentevals** closes the loop. Every tool call traced. Every run scored against the golden path. Trust isn't 'it worked in the demo' — it's 'I can prove it followed the right steps, every time.'

Six things to take away:

1. **Skills are the new unit of operational knowledge.** Not runbooks. Not wiki pages. Executable, versioned, composable. Pulled from git at deploy time — same GitOps you already use.

2. **Agents are Kubernetes-native.** CRDs. `kubectl apply`. GitOps. The workflow you already know.

3. **Multi-agent is composition, not complexity.** `type: Agent` — four lines of YAML. Specialists that mirror how your teams actually work.

4. **A catalog makes knowledge outlive people.** Register once, discover everywhere. The SRE who built it left — the skill didn't.

5. **Governance is not optional.** agentgateway gives you the same proxy layer for AI traffic that Envoy gives you for microservices. Security, observability, cost controls.

6. **Evaluation is non-negotiable.** OTel traces. Golden paths. Trajectory scoring. Same rigor you apply to code — now applied to agent behavior.

Everything you saw runs on a kind cluster on my laptop. kubectl and helm. All open source. kagent, agentgateway, agentregistry, agentevals.

Thank you."

---

## Troubleshooting

| Issue | Fix |
|-------|-----|
| curl to :8083 fails | `source ./scripts/ensure-portforward.sh` |
| No traces in agentevals | Check kagent OTel config in Helm values |
| Registry :12121 down | Check: `kubectl get pods -n agentregistry` |
| agentgateway proxy not ready | Check: `kubectl get gateway,deploy -n agentgateway-system` |
| LLM calls failing | Check: `kubectl logs -l app.kubernetes.io/name=agentgateway -n agentgateway-system` |
| kind OOM | Docker Desktop → 8GB+ RAM |
| A2A returns empty | Add `-L` flag to curl (API redirects with trailing slash) |

## Script Flow

```
01-setup-kind.sh          # Create kind cluster
02-install-stack.sh       # Install kagent, agentgateway, agentregistry, agentevals
03-deploy-agents.sh       # Team A: deploy specialist agents (healthcheck + deploy)
04-register-agents.sh     # Team A: register skills, agents, servers in catalog
05-compose-agent.sh       # Team B: register in catalog, then deploy incident agent
06-run-and-eval.sh        # Both: run agents, view traces, evaluate
ensure-portforward.sh     # Restart dead port-forwards
```

## File Structure

```
agents/
  01-deploy-agent.yaml      # Team A: 6 MCP tools — can read and write
  02-healthcheck-agent.yaml # Team A: 5 MCP tools — read-only diagnostics
  03-incident-agent.yaml    # Team B: 2 agent-as-tool — orchestrates the others
gateway/
  gateway.yaml              # Gateway API resource — listener on port 80
  openai-backend.yaml       # AgentgatewayBackend — OpenAI provider
  openai-route.yaml         # HTTPRoute — /openai path to OpenAI backend
skills/
  k8s-deploy/SKILL.md       # Team A: deployment runbook
  k8s-healthcheck/SKILL.md  # Team A: diagnostic runbook
  incident-response/SKILL.md # Team B: coordination playbook
evals/
  deploy-eval.json           # ADK conversation format
  healthcheck-eval.json
  incident-eval.json
```
