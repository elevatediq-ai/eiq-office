#!/bin/bash

# Purpose: Standardized script functionality managed by Elite PMO/usr/bin/env bash
set -euo pipefail
# Prepare and optionally execute a canary rollout for Phase 9.3
# Usage:
#   ./scripts/pmo/prepare_canary_rollout.sh --dry-run
#   ./scripts/pmo/prepare_canary_rollout.sh --execute --kube-context my-cluster

REPO="kushin77/ElevatedIQ-Mono-Repo"
K8S_DIR="apps/finops-dashboard-api/infra/k8s/phase9-3-canary"
DRY_RUN=true
EXECUTE=false
KUBE_CONTEXT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --execute) EXECUTE=true; DRY_RUN=false; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --kube-context) KUBE_CONTEXT="$2"; shift 2 ;;
    --help) echo "Usage: $0 [--dry-run|--execute] [--kube-context CONTEXT]"; exit 0 ;;
    *) echo "Unknown arg: $1"; exit 2 ;;
  esac
done

echo "[canary-helper] Phase 9.3 canary helper starting (dry_run=${DRY_RUN}, execute=${EXECUTE})"

if [ ! -d "$K8S_DIR" ]; then
  echo "Error: expected k8s manifests at $K8S_DIR" >&2
  exit 2
fi

if $DRY_RUN; then
  echo "[canary-helper] Validating Kubernetes manifests (client-side dry-run; validation disabled to avoid server OpenAPI fetch)..."
  kubectl apply --dry-run=client --validate=false -f "$K8S_DIR" || true
  echo "[canary-helper] Validating manifests (server-side dry-run, if context available)..."
  if [ -n "$KUBE_CONTEXT" ]; then
    kubectl --context "$KUBE_CONTEXT" apply --dry-run=server -f "$K8S_DIR" || true
  else
    echo "[canary-helper] No kube-context supplied; skipping server-side dry-run."
  fi
  echo "[canary-helper] Dry-run complete. To execute, re-run with --execute --kube-context YOUR_CONTEXT"
  exit 0
fi

echo "[canary-helper] Executing canary rollout to cluster${KUBE_CONTEXT:+ ($KUBE_CONTEXT)}"
APPLY_CMD=(kubectl)
if [ -n "$KUBE_CONTEXT" ]; then
  APPLY_CMD+=(--context "$KUBE_CONTEXT")
fi
APPLY_CMD+=(apply -f "$K8S_DIR")

echo "[canary-helper] Applying manifests..."
"${APPLY_CMD[@]}"

echo "[canary-helper] Waiting for rollout status on Deployments in $K8S_DIR"
DEPLOYMENTS=$(kubectl ${KUBE_CONTEXT:+--context "$KUBE_CONTEXT"} get -f "$K8S_DIR" -o jsonpath='{.items[?(@.kind=="Deployment")].metadata.name}' 2>/dev/null || true)
for d in $DEPLOYMENTS; do
  echo "[canary-helper] Checking rollout status for deployment: $d"
  kubectl ${KUBE_CONTEXT:+--context "$KUBE_CONTEXT"} rollout status deployment/$d --timeout=5m || {
    echo "[canary-helper] Rollout failed or timed out for $d; triggering rollback for safety." >&2
    kubectl ${KUBE_CONTEXT:+--context "$KUBE_CONTEXT"} rollout undo deployment/$d || true
    exit 3
  }
done

echo "[canary-helper] Canary rollout completed successfully."

echo "Post-deploy: verify health endpoints and alerting. Example checks:"
echo "  kubectl ${KUBE_CONTEXT:+--context $KUBE_CONTEXT} get pods -l app=finops-dashboard-api -o wide"
echo "  curl -sS http://<service-ip>:8000/health"
echo "  # Query Prometheus for error-rate, latency, and custom canary metrics"

exit 0
