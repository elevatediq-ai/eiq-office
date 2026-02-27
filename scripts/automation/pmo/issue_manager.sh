#!/usr/bin/env bash
# ==============================================================================
# Elite Issue Manager - Top 0.01% GitHub Issue Automation
# ==============================================================================
# Purpose: Automated GitHub issue lifecycle management with MANDATORY MILESTONES
# FedRAMP: PM-5 (Project Management), CM-3 (Change Management)
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh" || source "${SCRIPT_DIR}/common.sh" # Fallback for flat install

# Use the Unified Issue Engine for all creation operations
UIE_BIN="$SCRIPT_DIR/uie.sh"

# ==============================================================================
# Create Epic Issue (WITH MANDATORY MILESTONE)
# ==============================================================================
create_epic() {
    local title="$1"
    local description="${2:-}"
    local priority="${3:-P1}"
    local phase="${4:-foundation}"

    echo -e "${CYAN}Creating Epic Issue with MANDATORY Milestone...${NC}"

    local body=$(cat <<EOF
# Epic: ${title}

## Overview
${description}

## Business Value
- **CEO**: [Strategic impact - to be filled]
- **CTO**: [Technical impact - to be filled]
- **CFO**: [Financial impact - to be filled]

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
_Created by Elite PMO System on $(date -Iseconds)_
EOF
)

    local labels="type:epic,priority:${priority},phase:${phase}"

    # Use the Unified Issue Engine (UIE)
    if bash "$UIE_BIN" --title "[EPIC] ${title}" --body "$body" --labels "$labels"; then
        echo -e "${GREEN}✓ Epic created successfully via UIE${NC}"
    else
        echo -e "${RED}✗ Failed to create epic${NC}"
        return 1
    fi
}

# ==============================================================================
# Create Task Issue (WITH MANDATORY MILESTONE)
# ==============================================================================
create_task() {
    local title="$1"
    local description="${2:-}"
    local priority="${3:-P2}"
    local epic="${4:-}"
    local effort="${5:-1 day}"

    echo -e "${CYAN}Creating Task Issue with MANDATORY Milestone...${NC}"

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
_Created by Elite PMO System on $(date -Iseconds)_
EOF
)

    local labels="type:task,priority:${priority}"

    # Use the Unified Issue Engine (UIE)
    if bash "$UIE_BIN" --title "[TASK] ${title}" --body "$body" --labels "$labels"; then
        echo -e "${GREEN}✓ Task created successfully via UIE${NC}"
    else
        echo -e "${RED}✗ Failed to create task${NC}"
        return 1
    fi
}

# ==============================================================================
# Update Issue Status
# ==============================================================================
update_status() {
    local issue_number="$1"
    local status="$2"
    local comment="${3:-}"

    echo -e "${CYAN}Updating issue #${issue_number} status to: ${status}${NC}"

    case "$status" in
        in-progress)
            gh issue edit "$issue_number" --repo "$REPO" --add-label "status: in-progress"
            local msg="🚀 **Status Update: In Progress**

Started work on this issue.
Session: $(date +%Y%m%d-%H%M%S)

${comment}"
            ;;
        blocked)
            gh issue edit "$issue_number" --repo "$REPO" --add-label "status: blocked" --remove-label "status: in-progress"
            local msg="🔴 **Status Update: Blocked**

This issue is currently blocked.

${comment}"
            ;;
        in-review)
            gh issue edit "$issue_number" --repo "$REPO" --add-label "status: in-review" --remove-label "status: in-progress"
            local msg="👀 **Status Update: In Review**

Work complete, PR created for review.

${comment}"
            ;;
        completed)
            gh issue close "$issue_number" --repo "$REPO" --comment "✅ **Status Update: Completed**

${comment}

Closed: $(date -Iseconds)"
            echo -e "${GREEN}✓ Issue #${issue_number} closed${NC}"
            return
            ;;
        *)
            echo -e "${RED}Unknown status: ${status}${NC}"
            return 1
            ;;
    esac

    gh issue comment "$issue_number" --repo "$REPO" --body "$msg"
    echo -e "${GREEN}✓ Issue #${issue_number} updated${NC}"
}

# ==============================================================================
# Assign Issue to Self
# ==============================================================================
assign_me() {
    local issue_number="$1"

    echo -e "${CYAN}Assigning issue #${issue_number} to current user...${NC}"

    local current_user=$(gh api user -q .login)

    gh issue edit "$issue_number" --repo "$REPO" --add-assignee "$current_user"
    echo -e "${GREEN}✓ Issue #${issue_number} assigned to @${current_user}${NC}"
}

# ==============================================================================
# Start Work on Issue
# ==============================================================================
start_work() {
    local issue_number="$1"
    local comment="${2:-}"

    echo -e "${CYAN}🚀 Starting work on issue #${issue_number}...${NC}"

    assign_me "$issue_number"

    # Create feature branch
    local branch_name="feat/issue-${issue_number}"
    echo -e "${CYAN}Creating branch ${branch_name}...${NC}"
    git checkout -b "$branch_name" || git checkout "$branch_name"

    update_status "$issue_number" "in-progress" "${comment}"

    echo -e "${GREEN}✓ Work started on issue #${issue_number}${NC}"
}

# ==============================================================================
# Add Progress Update
# ==============================================================================
add_progress() {
    local issue_number="$1"
    local update="$2"

    echo -e "${CYAN}Adding progress update to issue #${issue_number}${NC}"

    local body="📝 **Progress Update**

${update}

_Updated: $(date -Iseconds)_"

    gh issue comment "$issue_number" --repo "$REPO" --body "$body"
    echo -e "${GREEN}✓ Progress update added${NC}"
}

# ==============================================================================
# List Issues by Status
# ==============================================================================
list_issues() {
    local status="${1:-open}"
    local label="${2:-}"

    echo -e "${CYAN}Listing ${status} issues (Oldest First)${NC}"

    local search_query="sort:created-asc"

    if [[ "$status" != "all" ]]; then
        search_query="$search_query state:$status"
    fi

    if [[ -n "$label" ]]; then
        search_query="$search_query label:\"$label\""
    fi

    gh issue list --repo "$REPO" --search "$search_query"
}

# ==============================================================================
# Generate Issue Report
# ==============================================================================
generate_report() {
    echo -e "${CYAN}╔═══════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  📊 Elite Issue Report - GitHub Issues Status    ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════╝${NC}"

    echo ""
    echo -e "${YELLOW}Open Issues (Oldest First):${NC}"
    gh issue list --repo "$REPO" --search "state:open sort:created-asc" | head -n 20

    echo ""
    echo -e "${YELLOW}Recently Closed (Last 10):${NC}"
    gh issue list --repo "$REPO" --state closed --limit 10

    echo ""
    echo -e "${YELLOW}Priority Breakdown (Oldest First):${NC}"
    echo -n "  P0 (Critical): "
    gh issue list --repo "$REPO" --search "state:open label:priority-p0 sort:created-asc" --json number --jq '. | length'
    echo -n "  P1 (High):     "
    gh issue list --repo "$REPO" --search "state:open label:priority-p1 sort:created-asc" --json number --jq '. | length'
    echo -n "  P2 (Medium):   "
    gh issue list --repo "$REPO" --search "state:open label:priority-p2 sort:created-asc" --json number --jq '. | length'

    echo ""
    echo -e "${YELLOW}Status Breakdown (Oldest First):${NC}"
    echo -n "  In Progress:   "
    gh issue list --repo "$REPO" --search "state:open label:\"status: in-progress\" sort:created-asc" --json number --jq '. | length'
    echo -n "  In Review:     "
    gh issue list --repo "$REPO" --search "state:open label:\"status: in-review\" sort:created-asc" --json number --jq '. | length'
    echo -n "  Blocked:       "
    gh issue list --repo "$REPO" --search "state:open label:\"status: blocked\" sort:created-asc" --json number --jq '. | length'
}

# ==============================================================================
# Sync Session to Issues
# ==============================================================================
sync_session() {
    local session_id="$1"

    echo -e "${CYAN}Syncing session ${session_id} to GitHub issues...${NC}"

    # Extract session info from SESSION_LOGS.md
    # (Simplified - would need more robust parsing)

    echo -e "${YELLOW}⚠ Manual sync required - review SESSION_LOGS.md${NC}"
    echo "  1. Identify issues worked on"
    echo "  2. Add progress comments"
    echo "  3. Update status labels"
    echo "  4. Close completed issues"
}

# ==============================================================================
# Main CLI
# ==============================================================================
main() {
    case "${1:-help}" in
        create-epic)
            create_epic "${2:-New Epic}" "${3:-}" "${4:-P1}" "${5:-foundation}"
            ;;
        create-task)
            create_task "${2:-New Task}" "${3:-}" "${4:-P2}" "${5:-}" "${6:-1 day}"
            ;;
        update-status)
            update_status "${2:-}" "${3:-in-progress}" "${4:-}"
            ;;
        assign-me)
            assign_me "${2:-}"
            ;;
        start-work)
            start_work "${2:-}" "${3:-}"
            ;;
        add-progress)
            add_progress "${2:-}" "${3:-Progress update}"
            ;;
        list)
            list_issues "${2:-open}" "${3:-}"
            ;;
        report)
            generate_report
            ;;
        sync-session)
            sync_session "${2:-}"
            ;;
        help|*)
            cat <<EOF
${CYAN}Elite Issue Manager - GitHub Issue Automation${NC}

Usage:
  $0 create-epic <title> [description] [priority] [phase]
  $0 create-task <title> [description] [priority] [epic] [effort]
  $0 update-status <issue#> <status> [comment]
  $0 assign-me <issue#>
  $0 start-work <issue#> [comment]
  $0 add-progress <issue#> <update>
  $0 list [state] [label]
  $0 report
  $0 sync-session <session-id>

Status Options:
  in-progress, blocked, in-review, completed

Priority Options:
  P0 (critical), P1 (high), P2 (medium)

Examples:
  $0 create-epic "Control Plane" "Build control plane MVP" P0 foundation
  $0 create-task "Implement API" "Create REST API endpoints" P1 9 "3 days"
  $0 update-status 42 in-progress "Starting implementation"
  $0 start-work 42 "Diving into the backend logic"
  $0 assign-me 42
  $0 add-progress 42 "Completed API design, starting coding"
  $0 update-status 42 completed "All tests passing, PR merged"
  $0 list open priority-p0
  $0 report

EOF
            ;;
    esac
}

main "$@"
