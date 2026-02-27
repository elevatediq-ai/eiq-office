#!/usr/bin/env bash
# ==============================================================================
# 100X PMO: Continuous Drift Monitoring Daemon (NIST SI-4)
# ==============================================================================

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DRIFT_SCRIPT="${REPO_ROOT}/scripts/pmo/drift_monitor.sh"
INTERVAL=3600  # 1 Hour

echo "🚀 Starting 100X Drift Daemon (Interval: ${INTERVAL}s)..."

while true; do
    echo "[$(date -u)] 🔎 Executing drift check cycle..."
    bash "$DRIFT_SCRIPT"
    echo "[$(date -u)] 💤 Sleeping for ${INTERVAL}s."
    sleep "$INTERVAL"
done
