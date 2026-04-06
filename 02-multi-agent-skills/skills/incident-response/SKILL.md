---
name: incident-response
description: Multi-agent incident response coordination with root cause analysis and remediation.
---

# Incident Response Skill

## Description
Coordinate multi-agent incident response for Kubernetes environments. Orchestrate the deploy agent and healthcheck agent to triage issues, correlate findings, and produce an incident summary with root cause analysis.

## Triggers
- User reports a production incident or outage
- User asks to "investigate", "triage", or "respond to" an issue
- Multiple symptoms are reported simultaneously (e.g., pods crashing AND high latency)
- User asks "what went wrong with the last deployment"

## Instructions

### Triage phase
1. Ask the user for: affected service/namespace, symptoms, when it started
2. Delegate to the healthcheck agent to assess current state of the affected workloads
3. If a recent deployment is suspected, delegate to the deploy agent to check rollout history

### Investigation phase
1. Correlate findings from sub-agents:
   - Timeline: when did the deployment happen vs. when did symptoms start?
   - Scope: is the issue isolated to one deployment or cluster-wide?
   - Cause: does the health report explain the symptoms?
2. If root cause is unclear, expand the search:
   - Check other deployments in the same namespace
   - Check namespace resource quotas
   - Check cluster-level events

### Response phase
1. If the issue is caused by a bad deployment:
   - Delegate to deploy agent to rollback
   - Delegate to healthcheck agent to verify recovery
2. If the issue is infrastructure-related:
   - Report the infrastructure issue with evidence
   - Suggest manual remediation steps

### Incident summary format
```
INCIDENT SUMMARY
================
Affected: <service(s)> in <namespace(s)>
Duration: <start> to <end/ongoing>
Severity: <P1/P2/P3>
Root Cause: <one-line summary>

TIMELINE:
- <timestamp>: <event>
- <timestamp>: <event>

ROOT CAUSE ANALYSIS:
<detailed explanation>

ACTIONS TAKEN:
- <action and result>

STATUS: <Resolved|Mitigated|Investigating>
```

## Validation Criteria
- Sub-agents are used appropriately (don't do their job manually)
- Findings are correlated into a coherent timeline
- Root cause is identified with evidence
- If rollback is needed, it is performed and verified
- Incident summary is complete and accurate

## Example

**Input:** "Our nginx app in the demo namespace is returning 503s after the last deploy"

**Expected agent delegation:**
1. Delegate to healthcheck agent -> "Check health of nginx in demo namespace"
2. Delegate to deploy agent -> "Show rollout history for nginx in demo namespace"
3. Correlate findings
4. If bad deploy: delegate to deploy agent -> "Rollback nginx in demo namespace"
5. Delegate to healthcheck agent -> "Verify nginx in demo is healthy after rollback"

**Expected output:** A complete incident summary with timeline, root cause, and resolution status.
