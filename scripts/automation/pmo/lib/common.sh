#!/usr/bin/env bash
# ==============================================================================
# PMO Common Library - Reusable Functions for Any Repository
# ==============================================================================
# Purpose: Extracted core PMO logic that can be reused across repositories
# FedRAMP: PM-5 (Project Management), CM-3 (Change Management)
# Usage: source this file in your scripts, set REPO and REPO_ROOT, then use functions
# ==============================================================================

set -euo pipefail

# ==============================================================================
# Configuration
# ==============================================================================
# These should be set by the caller or set defaults
REPO="${REPO:-}"
REPO_ROOT="${REPO_ROOT:-.}"
PMO_LOG_DIR="${PMO_LOG_DIR:-${REPO_ROOT}/logs/pmo}"
SESSION_LOG="${SESSION_LOG:-${REPO_ROOT}/docs/management/SESSION_LOGS.md}"
PMO_DASHBOARD="${PMO_DASHBOARD:-${REPO_ROOT}/docs/management/PMO_DASHBOARD.md}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log_info() { echo -e "${CYAN}ℹ ${NC}$1"; }
log_success() { echo -e "${GREEN}✓ ${NC}$1"; }
log_error() { echo -e "${RED}✗ ${NC}$1"; }
log_warn() { echo -e "${YELLOW}⚠ ${NC}$1"; }

# SQLite DB Manager wrapper
pmo_db_manager() {
    python3 "${REPO_ROOT}/scripts/pmo/lib/db.py" "$@"
}

# ==============================================================================
# Health: Self-Diagnosis - SI-4
# ==============================================================================
pmo_health_check() {
    echo -e "${CYAN}🔍 PMO Orchestrator Health Check...${NC}"
    local status="PASS"

    # Check dependencies
    if ! command -v gh >/dev/null 2>&1; then echo -e "  ${RED}✗ gh CLI missing${NC}"; status="FAIL"; fi
    if ! command -v sqlite3 >/dev/null 2>&1 && ! command -v python3 >/dev/null 2>&1; then echo -e "  ${RED}✗ DB runtime missing${NC}"; status="FAIL"; fi

    # Check paths
    if [[ ! -d "${REPO_ROOT}/.pmo" ]]; then echo -e "  ${YELLOW}⚠ .pmo dir missing (initializing...)${NC}"; mkdir -p "${REPO_ROOT}/.pmo"; fi
    if [[ ! -f "${REPO_ROOT}/.pmo/sessions.db" ]]; then echo -e "  ${YELLOW}⚠ DB file missing (creating...)${NC}"; pmo_db_manager init; fi

    # Check GH Auth
    if ! gh auth status >/dev/null 2>&1; then echo -e "  ${RED}✗ GH Auth failed${NC}"; status="FAIL"; fi

    if [[ "$status" == "PASS" ]]; then
        echo -e "${GREEN}✅ PMO System Healthy${NC}"
        return 0
    else
        echo -e "${RED}❌ PMO System Degraded${NC}"
        return 1
    fi
}

# ==============================================================================
# Utility: Validate Required Parameters
# ==============================================================================
pmo_validate_repo() {
    if [[ -z "$REPO" ]]; then
        echo -e "${RED}✗ Error: REPO environment variable not set${NC}"
        echo "  Usage: export REPO='owner/repo-name' && source scripts/pmo/lib/common.sh"
        return 1
    fi

    if ! command -v gh >/dev/null 2>&1; then
        echo -e "${RED}✗ Error: GitHub CLI (gh) not installed${NC}"
        return 1
    fi

    # Verify authentication
    if ! gh auth status >/dev/null 2>&1; then
        echo -e "${RED}✗ Error: GitHub CLI not authenticated${NC}"
        echo "  Run: gh auth login"
        return 1
    fi

    return 0
}

# ==============================================================================
# Core: Create GitHub Issue
# ==============================================================================
pmo_create_issue() {
    local title="$1"
    local body="$2"
    local labels="${3:-}"
    local assignees="${4:-}"

    if ! pmo_validate_repo; then
        return 1
    fi

    local args=("--repo" "$REPO" "--title" "$title" "--body" "$body")

    if [[ -n "$labels" ]]; then
        args+=("--label" "$labels")
    fi

    if [[ -n "$assignees" ]]; then
        args+=("--assignee" "$assignees")
    fi

    gh issue create "${args[@]}"
}

# ==============================================================================
# Core: Update GitHub Issue Status
# ==============================================================================
pmo_update_issue_status() {
    local issue_number="$1"
    local status="$2"
    local comment="${3:-}"

    if ! pmo_validate_repo; then
        return 1
    fi

    echo -e "${CYAN}Updating issue #${issue_number} status to: ${status}${NC}"

    case "$status" in
        in-progress)
            gh issue edit "$issue_number" --repo "$REPO" --add-label "status:in-progress" 2>/dev/null || true
            local msg="🚀 **Status: In Progress**

Session: $(date +%Y%m%d-%H%M%S)

${comment}"
            ;;
        blocked)
            gh issue edit "$issue_number" --repo "$REPO" --add-label "status:blocked" --remove-label "status:in-progress" 2>/dev/null || true
            local msg="🔴 **Status: Blocked**

${comment}"
            ;;
        in-review)
            gh issue edit "$issue_number" --repo "$REPO" --add-label "status:in-review" --remove-label "status:in-progress" 2>/dev/null || true
            local msg="👀 **Status: In Review**

${comment}"
            ;;
        completed)
            gh issue close "$issue_number" --repo "$REPO" --comment "✅ **Completed**

${comment}

Closed: $(date -Iseconds)" 2>/dev/null || true
            echo -e "${GREEN}✓ Issue #${issue_number} closed${NC}"
            return 0
            ;;
        *)
            echo -e "${RED}Unknown status: ${status}${NC}"
            return 1
            ;;
    esac

    if [[ -n "$msg" ]]; then
        gh issue comment "$issue_number" --repo "$REPO" --body "$msg"
    fi

    echo -e "${GREEN}✓ Issue #${issue_number} updated${NC}"
}

# ==============================================================================
# Core: List Issues
# ==============================================================================
pmo_list_issues() {
    local state="${1:-open}"
    local label="${2:-}"
    local limit="${3:-50}"

    if ! pmo_validate_repo; then
        return 1
    fi

    local args=("--repo" "$REPO" "--state" "$state" "--limit" "$limit")

    if [[ -n "$label" ]]; then
        args+=("--search" "label:\"$label\"")
    fi

    gh issue list "${args[@]}"
}

# ==============================================================================
# Core: Add Comment to Issue
# ==============================================================================
pmo_add_issue_comment() {
    local issue_number="$1"
    local comment="$2"

    if ! pmo_validate_repo; then
        return 1
    fi

    gh issue comment "$issue_number" --repo "$REPO" --body "$comment"
    echo -e "${GREEN}✓ Comment added to issue #${issue_number}${NC}"
}

# ==============================================================================
# Core: Assign Issue
# ==============================================================================
pmo_assign_issue() {
    local issue_number="$1"
    local assignee="$2"

    if ! pmo_validate_repo; then
        return 1
    fi

    gh issue edit "$issue_number" --repo "$REPO" --add-assignee "$assignee"
    echo -e "${GREEN}✓ Issue #${issue_number} assigned to @${assignee}${NC}"
}

# ==============================================================================
# Core: Create Epic Issue
# ==============================================================================
pmo_create_epic() {
    local title="$1"
    local description="${2:-}"
    local priority="${3:-P1}"
    local phase="${4:-foundation}"

    local body=$(cat <<EOF
# Epic: ${title}

## Overview
${description}

## Business Value
- **CEO**: [Strategic impact]
- **CTO**: [Technical impact]
- **CFO**: [Financial impact]

## Success Criteria
- [ ] Criterion 1
- [ ] Criterion 2

## Sub-Issues
(Will be added as work progresses)

## Architecture Decisions
(Will be documented as decisions are made)

## Compliance Requirements
- **NIST Controls**: (to be identified)
- **FedRAMP Impact**: (to be assessed)

**Effort**: TBD | **Priority**: ${priority} | **Phase**: ${phase}

---
_Created by PMO System on $(date -Iseconds)_
EOF
)

    local labels="type:epic,priority:${priority},phase:${phase}"
    pmo_create_issue "[EPIC] ${title}" "$body" "$labels"
}

# ==============================================================================
# Core: Create Task Issue
# ==============================================================================
pmo_create_task() {
    local title="$1"
    local description="${2:-}"
    local priority="${3:-P2}"
    local epic="${4:-}"
    local effort="${5:-1 day}"

    local epic_ref=""
    if [[ -n "$epic" ]]; then
        epic_ref="**Epic**: #${epic}"
    fi

    local body=$(cat <<EOF
# Task: ${title}

## Objective
${description}

## Acceptance Criteria
- [ ] Implementation complete
- [ ] Tests passing
- [ ] Documentation updated
- [ ] Security scan clean

## Technical Approach
1. (To be filled during implementation)

## Files to Modify
- (To be identified)

## Dependencies
- Blocks: (none)
- Blocked by: (none)

## Testing Requirements
- [ ] Unit tests
- [ ] Integration tests
- [ ] Security scan (Snyk/Gitleaks)

**Effort**: ${effort} | **Priority**: ${priority}
${epic_ref}

---
_Created by PMO System on $(date -Iseconds)_
EOF
)

    local labels="type:task,priority:${priority}"
    pmo_create_issue "[TASK] ${title}" "$body" "$labels"
}

# ==============================================================================
# Session: Initialize Session Log (if file doesn't exist)
# ==============================================================================
pmo_init_session_log() {
    if [[ ! -f "$SESSION_LOG" ]]; then
        mkdir -p "$(dirname "$SESSION_LOG")"
        cat > "$SESSION_LOG" <<EOF
# PMO Session Logs

> Centralized audit trail for all Copilot/PMO sessions

**Last Updated**: $(date -Iseconds)

## Active Sessions

(Sessions tracked below)

EOF
        echo -e "${GREEN}✓ Session log initialized at ${SESSION_LOG}${NC}"
    fi
}

# ==============================================================================
# Session: Log Update
# ==============================================================================
pmo_log_session_update() {
    local session_id="$1"
    local message="$2"
    local entry_type="${3:-progress}"

    pmo_init_session_log

    echo -e "${CYAN}[${session_id}] ${message}${NC}"

    # Append to session log
    # This is a simplified version - production would use structured logging
    echo "- [$(date +%H:%M:%S)] [${entry_type}] ${message}" >> "${SESSION_LOG}"
}

# ==============================================================================
# Utility: Format Duration
# ==============================================================================
pmo_format_duration() {
    local seconds=$1
    local hours=$((seconds / 3600))
    local minutes=$(((seconds % 3600) / 60))
    local secs=$((seconds % 60))

    if ((hours > 0)); then
        printf "%dh %dm %ds" "$hours" "$minutes" "$secs"
    elif ((minutes > 0)); then
        printf "%dm %ds" "$minutes" "$secs"
    else
        printf "%ds" "$secs"
    fi
}

# ==============================================================================
# Utility: Generate Report Header
# ==============================================================================
pmo_print_header() {
    local title="$1"
    local width="${2:-60}"

    echo ""
    echo -e "${CYAN}╔$(printf '═%.0s' $(seq 1 $((width - 2))))╗${NC}"
    printf "${CYAN}║${NC} %s${CYAN}║${NC}\n" "$(printf '%-*s' $((width - 2)) "$title")"
    echo -e "${CYAN}╚$(printf '═%.0s' $(seq 1 $((width - 2))))╝${NC}"
}

# ==============================================================================
# Export all functions for use by other scripts
# ==============================================================================
export -f pmo_validate_repo
export -f pmo_create_issue
export -f pmo_update_issue_status
export -f pmo_list_issues
export -f pmo_add_issue_comment
export -f pmo_assign_issue
export -f pmo_create_epic
export -f pmo_create_task
export -f pmo_init_session_log
export -f pmo_log_session_update
export -f pmo_format_duration
export -f pmo_print_header

echo ""
