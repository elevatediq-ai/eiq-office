#!/bin/bash

# 🚀 ElevatedIQ: Enhancement 3 - Blocker Detection & Auto-Escalation
# Identifies stalled work and auto-escalates for help

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../" && pwd)"

LOG_FILE="$REPO_ROOT/logs/pmo/blocker-detection.log"
BLOCKER_CACHE="$REPO_ROOT/.pmo-cache/blockers"

mkdir -p "$(dirname "$LOG_FILE")" "$BLOCKER_CACHE"

# Configuration
STALL_THRESHOLD_HOURS=4  # Mark as stalled if no commits in 4 hours
PR_REVIEW_THRESHOLD_HOURS=2  # Mark as stalled if PR waiting >2h
CONFLICT_THRESHOLD_HOURS=1  # Mark as stalled if conflict unresolved >1h

# Logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Check issue for staleness
check_issue_staleness() {
    local issue_num="$1"

    if ! command -v gh &> /dev/null; then
        return 1
    fi

    # Get issue details
    local issue_json=$(gh issue view "$issue_num" \
        --repo "kushin77/ElevatedIQ-Mono-Repo" \
        --json title,state,labels,updatedAt 2>/dev/null)

    if [ -z "$issue_json" ]; then
        return 1
    fi

    # Check if in-progress
    if ! echo "$issue_json" | grep -q "status-in-progress"; then
        return 0
    fi

    # Get last update time
    local last_update=$(echo "$issue_json" | grep -oP '"updatedAt": "[^"]+' | cut -d'"' -f4)
    local last_update_epoch=$(date -d "$last_update" +%s)
    local now_epoch=$(date +%s)
    local hours_elapsed=$(( (now_epoch - last_update_epoch) / 3600 ))

    # Check stall threshold
    if [ "$hours_elapsed" -gt "$STALL_THRESHOLD_HOURS" ]; then
        echo "$hours_elapsed"  # Return hours stalled
        return 0
    fi

    return 1
}

# Find blocked issues
find_blocked_issues() {
    log "🔍 Scanning for blocked issues..."

    if ! command -v gh &> /dev/null; then
        log "⚠️  GitHub CLI not found"
        return 1
    fi

    local blocked_issues=()

    # Query: in-progress issues
    local issues=$(gh issue list \
        --repo "kushin77/ElevatedIQ-Mono-Repo" \
        --label "status-in-progress" \
        --state open \
        --json "number" \
        --limit 50 2>/dev/null)

    while read -r issue_num; do
        if staleness=$(check_issue_staleness "$issue_num"); then
            if [ -n "$staleness" ] && [ "$staleness" -gt "$STALL_THRESHOLD_HOURS" ]; then
                blocked_issues+=("$issue_num:$staleness")
                log "🚨 Blocked: Issue #$issue_num (stalled $staleness hours)"
            fi
        fi
    done <<< "$(echo "$issues" | grep -oP '"number": \K[0-9]+')"

    echo "${blocked_issues[@]}"
}

# Escalate blocker
escalate_blocker() {
    local issue_num="$1"
    local reason="$2"
    local hours_stalled="${3:-0}"

    log "📈 Escalating issue #$issue_num: $reason"

    if ! command -v gh &> /dev/null; then
        return 1
    fi

    # Add escalation label
    gh issue edit "$issue_num" \
        --repo "kushin77/ElevatedIQ-Mono-Repo" \
        --add-label "status-blocked,needs-help" 2>/dev/null || true

    # Add comment
    local comment="🚨 **BLOCKER DETECTED**

**Reason**: $reason
**Stalled for**: ${hours_stalled} hours
**Auto-escalated**: $(date '+%Y-%m-%d %H:%M:%S')

This issue has been auto-escalated for help.

**Actions**:
1. Check for dependencies (are we waiting on another issue?)
2. Leave a comment explaining what's needed to unblock
3. Tag reviewers or ask for help
4. If dependency, link to blocking issue via 'Blocked by #XXXX'

---
*Auto-escalated by PMO blocker detection*"

    gh issue comment "$issue_num" \
        --repo "kushin77/ElevatedIQ-Mono-Repo" \
        --body "$comment" 2>/dev/null || true

    log "✅ Escalated issue #$issue_num"
}

# Detect PR blockers
detect_pr_blockers() {
    log "🔍 Checking for stalled PRs..."

    if ! command -v gh &> /dev/null; then
        return 1
    fi

    local prs=$(gh pr list \
        --repo "kushin77/ElevatedIQ-Mono-Repo" \
        --state open \
        --json "number,title,createdAt" \
        --limit 20 2>/dev/null)

    while read -r pr_num; do
        local created_at=$(echo "$prs" | grep -A5 "\"number\": $pr_num" | grep -oP '"createdAt": "[^"]+' | cut -d'"' -f4)
        if [ -n "$created_at" ]; then
            local created_epoch=$(date -d "$created_at" +%s)
            local now_epoch=$(date +%s)
            local hours_open=$(( (now_epoch - created_epoch) / 3600 ))

            if [ "$hours_open" -gt "$PR_REVIEW_THRESHOLD_HOURS" ]; then
                log "🚨 PR blocker: #$pr_num ($hours_open hours without review)"
                # Escalate by adding comment
                gh pr comment "$pr_num" \
                    --repo "kushin77/ElevatedIQ-Mono-Repo" \
                    --body "📍 **Pending Review** - This PR has been waiting $hours_open hours. Please review or prioritize! 🙏" 2>/dev/null || true
            fi
        fi
    done <<< "$(echo "$prs" | grep -oP '"number": \K[0-9]+')"
}

# Check for merge conflicts
detect_merge_conflicts() {
    log "🔍 Checking for unresolved conflicts..."

    if ! command -v gh &> /dev/null; then
        return 1
    fi

    local conflicted_prs=$(gh pr list \
        --repo "kushin77/ElevatedIQ-Mono-Repo" \
        --state open \
        --json "number,mergeStateStatus" \
        --limit 50 2>/dev/null)

    while read -r pr_line; do
        if echo "$pr_line" | grep -q "BLOCKED"; then
            local pr_num=$(echo "$pr_line" | grep -oP '"number": \K[0-9]+')
            log "🚨 Merge conflict: PR #$pr_num"

            gh pr comment "$pr_num" \
                --repo "kushin77/ElevatedIQ-Mono-Repo" \
                --body "⚠️ **Merge Conflict Detected** - Please resolve conflicts to unblock merge." 2>/dev/null || true
        fi
    done <<< "$conflicted_prs"
}

# Generate blocker report
generate_blocker_report() {
    log "📊 Generating blocker report..."

    local report_file="$BLOCKER_CACHE/blockers-$(date +%Y%m%d_%H%M%S).txt"

    {
        echo "╔════════════════════════════════════════════════════════════╗"
        echo "║  🚨 ElevatedIQ: Blocker Detection Report                    ║"
        echo "║  Time: $(date '+%Y-%m-%d %H:%M:%S')                        ║"
        echo "╚════════════════════════════════════════════════════════════╝"
        echo ""
        echo "🚨 Stalled Issues (Blocked)"
        blocked=$(find_blocked_issues)
        if [ -z "$blocked" ]; then
            echo "  ✅ No blocked issues detected"
        else
            while IFS=: read -r issue_num hours; do
                echo "  ⛔ Issue #$issue_num: Stalled $hours hours"
            done <<< "$blocked"
        fi
        echo ""
        echo "⏳ Status Summary"
        echo "  Scan Time: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "  Stall Threshold: $STALL_THRESHOLD_HOURS hours"
        echo "  PR Review Threshold: $PR_REVIEW_THRESHOLD_HOURS hours"
        echo ""
    } | tee "$report_file"

    log "✅ Report saved: $report_file"
}

# Automatic escalation daemon
run_daemon() {
    local interval="${1:-3600}"  # Default: 1 hour

    log "🤖 Starting blocker detection daemon (interval: ${interval}s)"

    while true; do
        log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        log "Running blocker detection cycle..."

        # Detect blockers
        if blocked=$(find_blocked_issues); then
            while IFS=: read -r issue_num hours; do
                if [ -n "$issue_num" ]; then
                    escalate_blocker "$issue_num" "No commits for $hours hours" "$hours"
                fi
            done <<< "$blocked"
        fi

        # Check PR blockers
        detect_pr_blockers
        detect_merge_conflicts

        # Generate report
        generate_blocker_report

        log "✅ Cycle complete. Next check in ${interval}s"
        sleep "$interval"
    done
}

# Main entry point
case "${1:-}" in
    "detect")
        log "🔍 Running one-time blocker detection..."
        blocked=$(find_blocked_issues)
        if [ -n "$blocked" ]; then
            while IFS=: read -r issue_num hours; do
                escalate_blocker "$issue_num" "No commits for $hours hours" "$hours"
            done <<< "$blocked"
        fi
        detect_pr_blockers
        detect_merge_conflicts
        generate_blocker_report
        ;;
    "daemon")
        run_daemon "${2:-3600}"
        ;;
    "report")
        generate_blocker_report
        ;;
    *)
        cat << 'USAGE'
🚀 ElevatedIQ: Blocker Detection & Auto-Escalation

Identifies stalled work and auto-escalates for help.

Usage:
  detect              Run one-time detection
  daemon [interval]   Run continuously (default: 3600s = 1 hour)
  report              Generate blocker report

Examples:
  ./blocker-detection.sh detect
  ./blocker-detection.sh daemon 300        # Check every 5 minutes
  ./blocker-detection.sh report

Features:
  ✓ Detects stalled in-progress issues (no commits >4h)
  ✓ Flags slow PR reviews (waiting >2h)
  ✓ Detects unresolved merge conflicts
  ✓ Auto-escalates with "needs-help" label
  ✓ Generates blocker reports

Setup:
  # Run as background daemon
  nohup ./scripts/pmo/blocker-detection.sh daemon 300 > /dev/null 2>&1 &
USAGE
        ;;
esac
