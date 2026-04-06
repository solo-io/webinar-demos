---
name: k8s-healthcheck
description: Diagnose Kubernetes workload health with structured reports and actionable remediation steps.
---

# Kubernetes Health Check Skill

## Description
Diagnose the health of Kubernetes workloads by inspecting pod status, events, logs, resource usage, and node conditions. Produces a structured health report with actionable remediation steps.

## Triggers
- User asks to "check health", "diagnose", or "troubleshoot" a workload
- User reports pods are crashing, not starting, or misbehaving
- User asks "why is X not working" for a Kubernetes resource

## Instructions

### Health check sequence
1. Get the target resource (Deployment, StatefulSet, DaemonSet, or Pod) via `k8s_get_resources`
2. List all pods owned by the resource and their current status
3. For any pod not in Running/Ready state, collect:
   - Pod details via `k8s_describe_resource`
   - Container logs via `k8s_get_pod_logs` (last 50 lines, including previous container if restarted)
4. Check for recent events in the namespace via `k8s_get_events`

### Diagnosis rules
- **Pending + no events**: Likely scheduling issue — check node resources, taints, affinity
- **Pending + FailedScheduling**: Report which constraint failed (CPU, memory, node selector)
- **ImagePullBackOff**: Check image name, tag, and registry auth
- **CrashLoopBackOff**: Read logs from previous container, check OOMKilled
- **Running but not Ready**: Check readiness probe config and endpoint
- **Evicted**: Check node disk/memory pressure

### Report format
Produce a structured report:
```
RESOURCE: <name> in <namespace>
STATUS: <Healthy|Degraded|Unhealthy>
PODS: <ready>/<total> ready

ISSUES:
- [SEVERITY] <issue description>
  EVIDENCE: <what you found>
  FIX: <recommended action>
```

## Validation Criteria
- All relevant pods are inspected
- Root cause is identified (not just symptoms)
- Remediation steps are specific and actionable
- No false positives (don't flag healthy resources)

## Example

**Input:** "Check the health of the nginx deployment in namespace demo"

**Expected tool sequence:**
1. k8s_get_resources (get deployment)
2. k8s_get_resources (list pods)
3. k8s_describe_resource (describe unhealthy pods)
4. k8s_get_pod_logs (get container logs)
5. k8s_get_events (check for error events)

**Expected output:** "RESOURCE: nginx in demo | STATUS: Healthy | PODS: 3/3 ready | No issues detected."
