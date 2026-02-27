#!/usr/bin/env bash
# ==============================================================================
# 🚀 ElevatedIQ 10X PMO: Automated Blocker & Failure Detection
# ==============================================================================
# Purpose: Scan for stalled work, test failures, and unresolved conflicts.
# Refs: #3448, #4256
# ==============================================================================

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOG_FILE="${REPO_ROOT}/scripts/pmo/blocker_detection.log"
ESCALATION_SCRIPT="${REPO_ROOT}/scripts/pmo/escalate_failure.sh"

# Ensure escalation script is executable
if [ ! -x "$ESCALATION_SCRIPT" ]; then
    chmod +x "$ESCALATION_SCRIPT"
fi

echo "🔍 Starting Blocker Detection Scan..." | tee "$LOG_FILE"

# Helper function to escalate
escalate() {
    local title="$1"
    local body="$2"
    local labels="$3"

    # Only escalate if title is provided
    if [ -z "$title" ]; then return; fi

    echo "🚨 Escalating: $title" | tee -a "$LOG_FILE"
    if [ -x "$ESCALATION_SCRIPT" ]; then
        "$ESCALATION_SCRIPT" "$title" "$body" "$labels"
    else
        echo "⚠️ Escalation script not found or not executable: $ESCALATION_SCRIPT" | tee -a "$LOG_FILE"
    fi
}

# 1. Scan for Stale In-Progress Issues
echo "--- Stale Issue Report ---" >> "$LOG_FILE"
# Issues in-progress with no activity for > 4 hours (simulated check here, would use API in prod)
# For now, we list open in-progress issues
gh api "search/issues?q=repo:kushin77/ElevatedIQ-Mono-Repo+is:issue+is:open+label:\"status: in-progress\"" --jq '.items[] | "Issue #\(.number): \(.title)"' >> "$LOG_FILE"

# 2. Scan for Test Failures in Logs
echo "--- Test Failure Scan ---" >> "$LOG_FILE"
FAILURES=$(grep -r "FAIL" "${REPO_ROOT}/logs" 2>/dev/null | head -n 5)
if [ -n "$FAILURES" ]; then
    echo "$FAILURES" >> "$LOG_FILE"
    escalate "[CRITICAL] Test Failures Detected" "The following test failures were found in logs:\n\n```\n$FAILURES\n```" "bug,automated-report,priority-p0"
fi

# 3. Detect Git Conflicts
echo "--- Conflict Detector ---" >> "$LOG_FILE"
CONFLICTS=$(grep -r "<<<<<<< HEAD" "$REPO_ROOT" --exclude-dir=".git" | head -n 5)
if [ -n "$CONFLICTS" ]; then
    echo "$CONFLICTS" >> "$LOG_FILE"
    escalate "[CRITICAL] Git Merge Conflicts Detected" "Unresolved merge conflicts found in codebase:\n\n```\n$CONFLICTS\n```" "bug,automated-report,priority-p0"
fi

# 4. Terraform Validation Scan (Phase A Compliance)
echo "--- Terraform Validation Failures ---" >> "$LOG_FILE"
TF_ERRORS=$(grep -r "Error: " "${REPO_ROOT}/infra/phase-a" 2>/dev/null | head -n 5)
if [ -n "$TF_ERRORS" ]; then
    echo "$TF_ERRORS" >> "$LOG_FILE"
    escalate "[CRITICAL] Terraform Validation Failed" "Terraform Phase A validation errors:\n\n```\n$TF_ERRORS\n```" "bug,automated-report,priority-p0"
fi

echo "✅ Blocker detection complete. Report saved to: $LOG_FILE"
