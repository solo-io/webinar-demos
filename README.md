# Webinar Demos

Shareable demo code and configurations from webinars covering AI agents, Kubernetes-native agent orchestration, and API gateway patterns for agentic workloads.

Each folder contains a self-contained demo with its own README, setup scripts, and agent configurations so you can follow along or run the demos yourself.

## Demos

| Demo | Description |
|------|-------------|
| [01-team-lead-agents](./01-team-lead-agents/) | AI Team Lead agent that diagnoses Kubernetes issues and creates GitHub issues/PRs using kagent |
| [02-multi-agent-skills](./02-multi-agent-skills/) | Multi-agent system with reusable skills, evals, and an Agent Gateway |
| [03-agent-registry](./03-agent-registry/) | Central catalog for AI artifacts with agentregistry — build and publish MCP servers locally, connect them to Claude Code, then run the registry on Kubernetes and deploy agents with kagent |

## YouTube Series

Hands-on AgentGateway episodes with step-by-step deploy/test/cleanup scripts:

| Episode | Description |
|---------|-------------|
| [03-virtual-mcp](./youtube-series/03-virtual-mcp/) | Virtual API keys for LLM access control — per-user keys with daily token budgets, API key authentication, and token-based rate limiting through AgentGateway |

## Key Projects

These demos feature and build on the following open-source projects:

- [kagent.dev](https://kagent.dev) - Kubernetes-native framework for building, deploying, and operating AI agents
- [agentgateway.dev](https://agentgateway.dev) - Gateway for managing and routing agentic API traffic (MCP, A2A)
- [aregistery.ai](https://aregistery.ai) - Registry for discovering and sharing agent skills and tools
- [aevals.ai](https://aevals.ai) - Evaluation framework for testing and benchmarking AI agents

## Getting Started

Each demo has its own prerequisites and setup instructions. Navigate into a demo folder and follow the README to get started.

## Contributing

Have a webinar demo to share? Open a PR with a new numbered folder following the existing pattern.