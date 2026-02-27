#!/bin/bash

################################################################################
# 🚨 Blocker Detection & Auto-Escalation System - Phase 2
# Purpose: Real-time detection and escalation of blocked/stalled work
# Triggers: Issues in-progress >4h, PRs in review >6h, velocity drops
# Actions: Auto-escalation, notifications, risk flagging
# Refs: #2790 Enhancement #3, #2779 Phase 2 Intelligence
################################################################################

set -euo pipefail

REPO="${REPO:-kushin77/ElevatedIQ-Mono-Repo}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/blocker_detection.log"

# Colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
GREEN='\033[0;32m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*" | tee -a "$LOG_FILE"; }
log_warn() { echo -e "${YELLOW}[⚠️ BLOCKER]${NC} $*" | tee -a "$LOG_FILE"; }
log_escalate() { echo -e "${RED}[🚨 ESCALATE]${NC} $*" | tee -a "$LOG_FILE"; }

################################################################################
# Blocker Detection Rules
################################################################################

detect_stalled_issues() {
    log_info "🔍 Detecting stalled issues (in-progress >4h without updates)..."

    local threshold_seconds=$((4 * 3600))
    local current_time=$(date +%s)
    local blockers_found=0

    # Query issues in-progress with old updates
    gh issue list \
        --repo "$REPO" \
        --state open \
        --label "status:in-progress" \
        --json number,title,updatedAt 2>/dev/null | \
    jq -r '.[] | "\(.number)|\(.title)|\(.updatedAt)"' | while IFS='|' read -r number title updated_at; do

        if [ -z "$number" ]; then continue; fi

        # Parse timestamp and check staleness
        local updated_epoch=$(date -d "$updated_at" +%s 2>/dev/null || echo 0)
        local age_seconds=$((current_time - updated_epoch))

        if [ $age_seconds -gt $threshold_seconds ]; then
            ((blockers_found++))
            log_warn "STALLED: Issue #$number - In-progress for $((age_seconds / 3600))h: $title"

            # Auto-escalate
            escalate_stalled_issue "$number" "$age_seconds"
        fi
    done

    [ $blockers_found -gt 0 ] && log_escalate "Found $blockers_found stalled issues"
}

detect_stale_prs() {
    log_info "🔍 Detecting stale PRs (in review >6h)..."

    local threshold_seconds=$((6 * 3600))
    local current_time=$(date +%s)
    local stale_prs=0

    gh pr list \
        --repo "$REPO" \
        --state open \
        --search "review:pending" \
        --json number,title,updatedAt 2>/dev/null | \
    jq -r '.[] | "\(.number)|\(.title)|\(.updatedAt)"' | while IFS='|' read -r number title updated_at; do

        if [ -z "$number" ]; then continue; fi

        local updated_epoch=$(date -d "$updated_at" +%s 2>/dev/null || echo 0)
        local age_seconds=$((current_time - updated_epoch))

        if [ $age_seconds -gt $threshold_seconds ]; then
            ((stale_prs++))
            log_warn "STALE PR: #$number - Awaiting review for $((age_seconds / 3600))h: $title"

            escalate_stale_pr "$number" "$age_seconds"
        fi
    done

    [ $stale_prs -gt 0 ] && log_escalate "Found $stale_prs stale PRs"
}

detect_blocked_issues() {
    log_info "🔍 Detecting explicitly blocked issues..."

    local blocked_count=0

    gh issue list \
        --repo "$REPO" \
        --state open \
        --label "status:blocked" \
        --json number,title,updatedAt 2>/dev/null | \
    jq -r '.[] | "\(.number)|\(.title)|\(.updatedAt)"' | while IFS='|' read -r number title updated_at; do

        if [ -z "$number" ]; then continue; fi

        ((blocked_count++))
        log_warn "BLOCKED: Issue #$number - Status: blocked: $title"

        # Check why it's blocked
        gh issue view "$number" --repo "$REPO" --json body -q '.body' 2>/dev/null | \
        grep -i "blocked\|waiting\|dependency" | head -1 | \
        while read -r reason; do
            log_info "  Reason: $reason"
        done
    done

    [ $blocked_count -gt 0 ] && log_escalate "Found $blocked_count explicitly blocked issues"
}

detect_velocity_drops() {
    log_info "🔍 Detecting velocity anomalies..."

    # Get today's and yesterday's velocity
    local today_velocity=$(git log --since="00:00" --oneline 2>/dev/null | wc -l)
    local yesterday_velocity=$(git log --since="yesterday 00:00" --until="00:00" --oneline 2>/dev/null | wc -l)
    local seven_day_avg=$(git log --since="7 days ago" --oneline 2>/dev/null | wc -l)
    seven_day_avg=$((seven_day_avg / 7))

    # Flag if velocity drops >50%
    if [ $yesterday_velocity -gt 0 ] && [ $today_velocity -lt $((yesterday_velocity / 2)) ]; then
        log_warn "VELOCITY DROP: Today ($today_velocity commits) vs Yesterday ($yesterday_velocity commits)"

        # Check for known issues
        local p0_blockers=$(gh issue list --repo "$REPO" --state open --label "priority:P0,status:blocked" --json number | jq 'length')

        if [ "$p0_blockers" -gt 0 ]; then
            log_escalate "Possible cause: $p0_blockers P0 blockers"
        fi
    fi
}

################################################################################
# Auto-Escalation Actions
################################################################################

escalate_stalled_issue() {
    local issue_number="$1"
    local age_seconds="$2"
    local age_hours=$((age_seconds / 3600))

    log_escalate "Escalating stalled issue #$issue_number (age: ${age_hours}h)"

    # Post escalation comment
    gh issue comment "$issue_number" \
        --repo "$REPO" \
        --body "🚨 **BLOCKER DETECTION**

This issue has been in-progress for **${age_hours}h** without updates.

**Action Required:**
1. Provide status update on this issue
2. Document any blockers preventing progress
3. Request help if needed (mention @team)
4. Move to \`status: blocked\` if waiting on external dependency

[Blocker Detection System - Phase 2](#2779)" \
        2>/dev/null || log_warn "Failed to post escalation comment"

    # Add escalation label
    gh issue edit "$issue_number" \
        --repo "$REPO" \
        --add-label "health:escalated" 2>/dev/null || true
}

escalate_stale_pr() {
    local pr_number="$1"
    local age_seconds="$2"
    local age_hours=$((age_seconds / 3600))

    log_escalate "Escalating stale PR #$pr_number (age: ${age_hours}h)"

    # Post reviewer notification
    gh pr comment "$pr_number" \
        --repo "$REPO" \
        --body "👀 **REVIEW ATTENTION NEEDED**

This PR has been awaiting review for **${age_hours}h**.

**Action Items:**
- [ ] Assign reviewer(s) if not yet assigned
- [ ] Tag @team for review assistance
- [ ] Convert to draft if work in progress
- [ ] Close if no longer needed

[Blocker Detection System - Phase 2](#2779)" \
        2>/dev/null || log_warn "Failed to post reviewer notification"
}

################################################################################
# Risk Scoring & Reporting
################################################################################

calculate_blocker_risk_score() {
    log_info "📊 Calculating blocker risk score..."

    local stalled=$(gh issue list --repo "$REPO" --state open --label "status:in-progress" --json updatedAt | \
        jq '[.[] | select(.updatedAt < (now - 14400))] | length' 2>/dev/null || echo 0)
    local blocked=$(gh issue list --repo "$REPO" --state open --label "status:blocked" --json number | jq 'length' 2>/dev/null || echo 0)
    local stale_prs=$(gh pr list --repo "$REPO" --state open --search "review:pending" --json updatedAt | \
        jq '[.[] | select(.updatedAt < (now - 21600))] | length' 2>/dev/null || echo 0)

    # Calculate risk score (0-100)
    local risk_score=$((stalled * 5 + blocked * 10 + stale_prs * 3))

    echo "$risk_score|$stalled|$blocked|$stale_prs"
}

generate_blocker_report() {
    log_info "📋 Generating blocker detection report..."

    IFS='|' read -r score stalled blocked stale <<< "$(calculate_blocker_risk_score)"

    cat > "${SCRIPT_DIR}/blocker_report.md" <<EOF
# 🚨 Blocker Detection Report

**Generated**: $(date -u +%FT%TZ)
**Risk Level**: $([ $score -lt 10 ] && echo "🟢 LOW" || [ $score -lt 30 ] && echo "🟡 MEDIUM" || echo "🔴 HIGH")
**Risk Score**: $score/100

---

## 📊 Blocker Summary

| Category | Count | Severity |
|----------|-------|----------|
| Stalled Issues (>4h) | $stalled | $([ $stalled -gt 0 ] && echo "🔴 HIGH" || echo "🟢 NONE") |
| Blocked Issues | $blocked | $([ $blocked -gt 0 ] && echo "🟡 MEDIUM" || echo "🟢 NONE") |
| Stale PRs (>6h review) | $stale | $([ $stale -gt 0 ] && echo "🔴 HIGH" || echo "🟢 NONE") |

---

## 🎯 Risk Level Assessment

$([ $score -lt 10 ] && echo "### 🟢 LOW RISK (Score: $score/100)

All systems healthy. No immediate blockers detected." || [ $score -lt 30 ] && echo "### 🟡 MEDIUM RISK (Score: $score/100)

Minor blockers detected. Recommend attention within 2 hours." || echo "### 🔴 HIGH RISK (Score: $score/100)

Critical blockers detected. Immediate action required!")

---

## ✅ Recommended Actions

$([ $stalled -gt 0 ] && echo "1. **Address Stalled Issues** ($stalled issues)
   - Post status updates
   - Request help if blocked
   - Move to 'blocked' status if waiting on external factor" || echo "1. ✅ No stalled issues")

$([ $blocked -gt 0 ] && echo "2. **Resolve Blocked Issues** ($blocked issues)
   - Identify root cause
   - Escalate if P0
   - Create tracking for blockers" || echo "2. ✅ No explicitly blocked issues")

$([ $stale -gt 0 ] && echo "3. **Speed Up PR Review** ($stale PRs waiting)
   - Assign reviewers
   - Reduce scope if needed
   - Increase review frequency" || echo "3. ✅ All PRs being reviewed promptly")

---

**Detection System**: Phase 2 Intelligence
**SLA**: <5 minute detection + escalation
**Reference**: #2790, #2779
EOF

    log_info "Blocker report generated: ${SCRIPT_DIR}/blocker_report.md"
}

################################################################################
# Main Entry Point
################################################################################

main() {
    log_info "🚨 Blocker Detection & Escalation System v1.0"
    log_info "Phase 2: Real-time blocker detection"

    # Run all detection rules
    detect_stalled_issues
    detect_stale_prs
    detect_blocked_issues
    detect_velocity_drops

    # Generate reports
    generate_blocker_report

    log_info "Blocker detection cycle complete"
}

main "$@"
