#!/usr/bin/env bash
#############################################################
# ensure-portforward.sh
# Source this file to ensure all port-forwards are running.
# Usage: source ./scripts/ensure-portforward.sh
#############################################################

_ensure_pf() {
  local svc="$1" ns="$2" local_port="$3" remote_port="$4" label="$5"

  if lsof -i ":${local_port}" -sTCP:LISTEN &>/dev/null; then
    return 0
  fi

  echo "  Starting port-forward: ${label} (localhost:${local_port})"
  kubectl port-forward "svc/${svc}" -n "${ns}" "${local_port}:${remote_port}" &>/dev/null &
  sleep 1

  if ! lsof -i ":${local_port}" -sTCP:LISTEN &>/dev/null; then
    echo "  WARNING: ${label} port-forward may have failed"
  fi
}

_ensure_pf_dynamic() {
  local ns="$1" local_port="$2" remote_port="$3" label="$4"

  if lsof -i ":${local_port}" -sTCP:LISTEN &>/dev/null; then
    return 0
  fi

  # Find the gateway proxy service (not the controller)
  local svc
  svc=$(kubectl get svc -n "${ns}" -o name 2>/dev/null | grep -v controller | head -1 | sed 's|service/||')
  if [ -z "${svc}" ]; then
    echo "  WARNING: ${label} — no service found in ${ns}"
    return 1
  fi

  echo "  Starting port-forward: ${label} (localhost:${local_port}) → ${svc}"
  kubectl port-forward "svc/${svc}" -n "${ns}" "${local_port}:${remote_port}" &>/dev/null &
  sleep 1

  if ! lsof -i ":${local_port}" -sTCP:LISTEN &>/dev/null; then
    echo "  WARNING: ${label} port-forward may have failed"
  fi
}

echo "==> Ensuring port-forwards are running..."
_ensure_pf agentevals  default  8001 8001 "agentevals UI"
_ensure_pf agentevals  default  4317 4317 "agentevals OTLP (gRPC)"
_ensure_pf kagent-controller kagent 8083 8083 "kagent API"
_ensure_pf kagent-ui         kagent 8082 8080 "kagent UI"
_ensure_pf_dynamic agentgateway-system 9090 80 "agentgateway proxy"
# agentregistry: NodePort 30121 → host 12121 via kind config
echo "==> Port-forwards ready."
echo ""
