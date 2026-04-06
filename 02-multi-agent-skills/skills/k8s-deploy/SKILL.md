---
name: k8s-deploy
description: Deploy Kubernetes manifests with dry-run validation, progressive rollout, and automatic rollback on failure.
---

# Kubernetes Deployment Skill

## Description
Deploy Kubernetes manifests with dry-run validation, progressive rollout, and automatic rollback on failure. This skill handles the full deployment lifecycle: validate, apply, verify, rollback if needed.

## Triggers
- User asks to "deploy", "apply", or "roll out" Kubernetes resources
- User provides YAML manifests with kind: Deployment, StatefulSet, or Service
- User references a Helm chart for installation or upgrade

## Instructions

### Pre-deployment validation
1. Parse and validate the manifest YAML schema
2. Run `k8s_apply_manifest` with dry-run=server against the target cluster
3. Compare against running resources with `k8s_get_resource_yaml`
4. Check for common issues: missing resource limits, no readiness probes, privileged containers

### Deployment execution
1. Apply with `k8s_apply_manifest` for the resource
2. Monitor rollout with `k8s_get_resources` to check deployment status
3. Wait for readiness probes to pass (timeout: 120s)

### Post-deployment verification
1. Verify pod status is Running and Ready via `k8s_get_resources`
2. Check for CrashLoopBackOff or ImagePullBackOff via `k8s_get_events`
3. Verify service endpoints are populated
4. Optionally check connectivity via `k8s_check_service_connectivity`

### Error handling
- **Dry-run fails**: Return the validation error and suggest fixes
- **Rollout timeout**: Check pod events with `k8s_get_events`, return diagnostics, offer rollback
- **CrashLoopBackOff**: Collect logs with `k8s_get_pod_logs`, suggest fixes
- **Rollback**: Execute rollback and verify previous version is healthy

## Validation Criteria
- All pods in Ready state
- Rollout status reports "successfully rolled out"
- No error events in the last 60 seconds
- Service endpoints are populated (if service exists)

## Example

**Input:** "Deploy nginx with 3 replicas to the demo namespace"

**Expected tool sequence:**
1. k8s_apply_manifest (with dry-run=server flag)
2. k8s_apply_manifest (actual apply)
3. k8s_get_resources (check rollout status)
4. k8s_get_resources (verify pods are ready)
5. k8s_get_events (check for errors)

**Expected output:** "Deployment nginx successfully rolled out to namespace demo. 3/3 replicas ready. No error events detected."
