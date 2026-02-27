#!/usr/bin/env bash
# ==============================================================================
# 🛡️ ElevatedIQ Workspace Resilience Daemon v2.0
# ==============================================================================
# Purpose: Autonomous monitoring and self-healing for Dev Workspaces.
# NIST 800-53: SI-4 (Monitoring), SI-11 (Error Handling), CM-6 (Hardening)
# ==============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STATE_DIR="${REPO_ROOT}/.pmo/daemon"
STATE_FILE="${STATE_DIR}/state.json"
mkdir -p "$STATE_DIR"

# Configuration
CHECK_INTERVAL=300 # 5 minutes
MEM_THRESHOLD_MB=1024
DISK_THRESHOLD_PERCENT=90
REPO="kushin77/ElevatedIQ-Mono-Repo"

# Level 3 Autonomy: Proactive Mode and Context Snapshotting
PROACTIVE_MODE=true
SNAPSHOT_INTERVAL=1800 # 30 minutes

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[$(date +%H:%M:%S) INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[$(date +%H:%M:%S) WARN]${NC} $1"; }
log_error() { echo -e "${RED}[$(date +%H:%M:%S) FAIL]${NC} $1"; }

# ==============================================================================
# Issue Management Logic
# ==============================================================================
create_pmo_issue() {
    local title="$1"
    local body="$2"
    local label="bug,priority-p0"

    # Check if an open issue with this title already exists to prevent spam
    local existing=$(gh issue list --repo "$REPO" --search "$title in:title state:open" --json number -q '.[].number')

    if [ -z "$existing" ]; then
        log_info "Creating auto-generated stability issue: $title"
        # 10X Upgrade: Use Unified Issue Engine (UIE)
        bash "$(dirname "${BASH_SOURCE[0]}")/../uie.sh" --title "$title" --body "$body" --labels "$label"
    else
        log_info "Stability issue already exists (#$existing). Updating instead of creating duplicate."
        gh issue comment "$existing" --repo "$REPO" --body "⚠️ **Recurring Alert**: $title"$'\n\n'"Detected again at $(date +%Y-%m-%dT%H:%M:%S)"
    fi
}

# ==============================================================================
# Auto-Remediation & Snapshotting
# ==============================================================================
auto_prune() {
    local target="$1"
    local desc="$2"

    log_warn "Initiating auto-prune for: $desc"
    # Safety Check: Never delete root or non-cache paths violently
    if [[ "$target" == *htmlcov* ]] || [[ "$target" == *__pycache__* ]] || [[ "$target" == *.tfplan ]]; then
        find "${REPO_ROOT}" -path "*$target*" -print0 | xargs -0 rm -rf
        echo "- $(date): Auto-pruned $desc" >> "${STATE_DIR}/remediation.log"
        log_info "Auto-prune complete: $desc"
    else
        log_error "Safety Prevented deletion of: $target"
    fi
}

save_context_snapshot() {
    local snapshot_file="${STATE_DIR}/context_snapshot.json"

    # Capture modified files as proxy for active context
    local modified_files=$(git -C "${REPO_ROOT}" status --porcelain | awk '{print $2}' | jq -R -s -c 'split("\n")[:-1]')
    local branch=$(git -C "${REPO_ROOT}" branch --show-current)
    local terminals_active=$(ls -1 "${REPO_ROOT}/.vscode-terminal-tracking"/*.json 2>/dev/null | wc -l || echo "0")

    cat > "$snapshot_file" <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "host": "$(hostname)",
  "git_branch": "$branch",
  "active_terminals_count": $terminals_active,
  "modified_files_context": $modified_files
}
EOF
}

# ==============================================================================
# Diagnostic Checks
# ==============================================================================
check_memory() {
    local free_mem=$(free -m | awk '/Mem:/ {print $4}')
    if [ "$free_mem" -lt "$MEM_THRESHOLD_MB" ]; then
        log_warn "Critical low memory detected: ${free_mem}MB free."

        # PROACTIVE MODE: Auto-Prune high-impact garbage
        log_info "⚠️  PROACTIVE MODE: Triggering Emergency Prune..."
        auto_prune "__pycache__" "Python Cache Files"
        auto_prune "htmlcov" "HTML Coverage Reports"

        # Re-check
        local new_free=$(free -m | awk '/Mem:/ {print $4}')
        if [ "$new_free" -lt "$MEM_THRESHOLD_MB" ]; then
             create_pmo_issue "[STABILITY] Critical Low Memory (Remediation Failed)" \
            "### host: $(hostname)
The workspace daemon detected critical memory depletion and ATTEMPTED remediation but failed to reclaim enough space.
**Details:**
- Initial Free: ${free_mem}MB
- Post-Prune Free: ${new_free}MB
- Threshold: ${MEM_THRESHOLD_MB}MB

**Action Required:** Manual intervention needed. Close VS Code windows."
             return 1
        else
             log_info "✅ Remediation Successful. Free Mem: ${new_free}MB"
             create_pmo_issue "[STABILITY] Low Memory Auto-Resolved" \
            "### host: $(hostname)
Daemon successfully averted a memory crash.
- **Action**: Auto-Pruned __pycache__ & htmlcov
- **Result**: Recovered $((new_free - free_mem))MB RAM"
        fi
    fi
    return 0
}

check_disk() {
    local disk_usage=$(df -h "${REPO_ROOT}" | tail -1 | awk '{print $5}' | sed 's/%//')
    if [ "$disk_usage" -gt "$DISK_THRESHOLD_PERCENT" ]; then
        log_warn "Critical disk usage: ${disk_usage}%."

        # PROACTIVE MODE
        log_info "⚠️  PROACTIVE MODE: Pruning binary artifacts..."
        auto_prune ".tfplan" "Terraform Plans"
        auto_prune "*.log" "Old Logs"

        create_pmo_issue "[STABILITY] Critical Disk Usage in Workspace" \
            "### host: $(hostname)
Disk usage exceeds safety threshold. Auto-prune attempted.
**Details:**
- Current Usage: ${disk_usage}%
- Threshold: ${DISK_THRESHOLD_PERCENT}%"
        return 1
    fi
    return 0
}

check_bloat() {
    local bloat_found=false
    # Check for htmlcov (giant indexer killer)
    if [ -d "${REPO_ROOT}/apps/control_plane/htmlcov" ]; then
        auto_prune "${REPO_ROOT}/apps/control_plane/htmlcov" "Detected Bloat: htmlcov"
        bloat_found=true
    fi

    if $bloat_found; then
        echo "- $(date): Cleaned up workspace bloat" >> "${STATE_DIR}/remediation.log"
    fi
}

# ==============================================================================
# Main Loop
# ==============================================================================
main() {
    log_info "========================================="
    log_info "Eiq Workspace Resilience Daemon v2.0 (Proactive)"
    log_info "Interval: ${CHECK_INTERVAL}s"
    log_info "========================================="

    while true; do
        # 1. Save Context (The "Immortal Workspace" Feature)
        save_context_snapshot

        # 2. Healt Checks
        check_bloat
        check_memory || true
        check_disk || true

        # Monitor VS Code Watcher status
        local watcher_limit=$(cat /proc/sys/fs/inotify/max_user_watches)
        if [ "$watcher_limit" -lt 524288 ]; then
             create_pmo_issue "[STABILITY] Inoptimal Inotify Watcher Limit" \
                "Inotify watcher limit ($watcher_limit) is too low for a mono-repo.
**Recommendation:** Set fs.inotify.max_user_watches=524288"
        fi

        log_info "Cycle complete. Sleeping for ${CHECK_INTERVAL}s..."
        sleep "$CHECK_INTERVAL"
    done
}

main "$@"
