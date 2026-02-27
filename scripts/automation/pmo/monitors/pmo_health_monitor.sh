#!/bin/bash
# =============================================================
# 🚀 100X PMO - SYSTEM HEALTH MONITOR
# =============================================================
# Purpose: Monitor the health and performance of the 100X PMO
# Status: PRODUCTION READY
# =============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LOG_DIR="${REPO_ROOT}/logs/pmo_health"
mkdir -p "$LOG_DIR"

check_script_integrity() {
    echo "🔍 Checking script integrity..."
    local scripts=("pmo_orchestrator_100x.sh" "multi_project_manager.sh" "automated_workflow_engine.sh" "intelligent_cherry_picker.sh")
    for script in "${scripts[@]}"; do
        if [[ -f "${SCRIPT_DIR}/${script}" ]]; then
            echo "✅ ${script} exists"
            if [[ -x "${SCRIPT_DIR}/${script}" ]]; then
                echo "✅ ${script} is executable"
            else
                echo "⚠️  ${script} is not executable. Fixing..."
                chmod +x "${SCRIPT_DIR}/${script}"
            fi
        else
            echo "❌ ${script} is MISSING"
        fi
    done
}

check_api_limits() {
    echo "🌐 Checking GitHub API limits..."
    if command -v gh &> /dev/null; then
        gh api rate_limit --jq '.resources.core' | jq -C '.'
        gh api rate_limit --jq '.resources.graphql' | jq -C '.'
    else
        echo "❌ gh CLI not found"
    fi
}

check_log_health() {
    echo "📝 Checking log health..."
    local latest_log=$(ls -t "${REPO_ROOT}/logs/100x_production_launch_"* 2>/dev/null | head -1)
    if [[ -n "$latest_log" ]]; then
        echo "✅ Latest log found: $(basename "$latest_log")"
        if grep -q "ERROR" "$latest_log"; then
            echo "⚠️  Errors detected in latest logs!"
            grep "ERROR" "$latest_log" | tail -n 5
        else
            echo "✅ No errors in latest logs."
        fi
    else
        echo "⚠️  No production launch logs found."
    fi
}

report_metrics() {
    echo "📊 System Metrics Summary..."
    echo "  • Projects: $(grep -c "Project" "${REPO_ROOT}/docs/pmo/PRODUCTION_MONITORING.md" 2>/dev/null || echo "0") active"
    echo "  • Status: $(grep "Status:" "${REPO_ROOT}/docs/pmo/PRODUCTION_MONITORING.md" 2>/dev/null | awk '{print $NF}' || echo "UNKNOWN")"
}

echo "╔══════════════════════════════════════════════╗"
echo "║ 🛡️  100X PMO HEALTH MONITOR                 ║"
echo "╚══════════════════════════════════════════════╝"

check_script_integrity
echo "---"
check_api_limits
echo "---"
check_log_health
echo "---"
report_metrics

echo "🚀 Health check complete."
