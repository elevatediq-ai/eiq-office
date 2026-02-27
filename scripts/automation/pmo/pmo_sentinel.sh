#!/bin/bash
##############################################################################
# PMO Sentinel - Global Enforcement & Governance Audit Engine
# Purpose: 10X Unified Governance Scanning (Assignees, Milestones, Metadata)
# FedRAMP: [NIST-AU-2, SI-4] Global Monitoring and Auditing
# Version: 3.0.0 (Elite Phase 3 Edition)
##############################################################################

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

REPO="${REPO:-kushin77/ElevatedIQ-Mono-Repo}"
DRY_RUN="${DRY_RUN:-true}"
BATCH_SIZE="${BATCH_SIZE:-100}" # Official GitHub REST Max
MAX_LOAD_PER_USER=10  # [NIST-AC-2] Prevent individual bottlenecks

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[PASS]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[FAIL]${NC} $*"; }

# ============================================================================
# MODULE 1: COMPLIANCE SCANNER (Label Integrity & Auto-Labeling 2.0)
# ============================================================================

auto_label_issue() {
    local issue_number="$1"
    local title="$2"
    local body="$3"
    local combined=$(echo "${title} ${body}" | tr '[:upper:]' '[:lower:]')

    local -a recommended_labels=()

    # Type Inference
    if [[ "$combined" =~ fix|bug|error|issue|fail ]]; then recommended_labels+=("type:bug"); fi
    if [[ "$combined" =~ feat|add|implement|enhance ]]; then recommended_labels+=("type:task"); fi
    if [[ "$combined" =~ doc|readme|wiki ]]; then recommended_labels+=("type:docs"); fi

    # Priority Inference
    if [[ "$combined" =~ urgent|critical|p0|blocker|outage ]]; then recommended_labels+=("priority-p0"); fi
    if [[ "$combined" =~ high|p1|important ]]; then recommended_labels+=("priority-p1"); fi

    if [[ ${#recommended_labels[@]} -gt 0 ]]; then
        log_info "Recommendation: Add labels [${recommended_labels[*]}] to #$issue_number"
        if [[ "$DRY_RUN" == "false" ]]; then
            # 10X REPLACEMENT: Use REST API to bypass GraphQL rate limits
            printf '%s\n' "${recommended_labels[@]}" | jq -R . | jq -s -c . | \
                gh api -X POST "repos/${REPO}/issues/${issue_number}/labels" --input - >/dev/null
            log_success "Remediated: Labels applied via REST."
        fi
    fi
}

scan_label_integrity() {
    local issue_number="$1"
    local title="$2"
    local body="$3"
    local labels_json="$4"

    # Use OR true to prevent set -e from exiting on jq -e "failure"
    local has_type=$(echo "$labels_json" | jq -e '.[] | select(.name | startswith("type:"))' >/dev/null 2>&1 && echo "true" || echo "false")
    local has_priority=$(echo "$labels_json" | jq -e '.[] | select(.name | startswith("priority-"))' >/dev/null 2>&1 && echo "true" || echo "false")

    if [[ "$has_type" == "false" || "$has_priority" == "false" ]]; then
        log_warn "Issue #$issue_number: Missing metadata labels (Type:$has_type, Priority:$has_priority)"
        auto_label_issue "$issue_number" "$title" "$body"
        return 1
    fi
    return 0
}

# ============================================================================
# MODULE 2: MILESTONE ENFORCEMENT
# ============================================================================

enforce_milestone() {
    local issue_number="$1"
    local current_milestone="$2"
    local title="$3"
    local body="$4"
    local labels_json="$5"

    if [[ "$current_milestone" == "null" ]]; then
        log_warn "Issue #$issue_number: No milestone assigned."

        # Determine target milestone using 10X Smart Selector
        local target_milestone_id=$(bash scripts/pmo/smart_milestone_selector.sh "$title" "$body" "$labels_json" || echo "")

        if [[ -n "$target_milestone_id" ]]; then
            log_info "Recommendation: Assign #$issue_number to milestone ID '$target_milestone_id'"
            if [[ "$DRY_RUN" == "false" ]]; then
                # 10X REPLACEMENT: Use REST API to bypass GraphQL rate limits
                gh api -X PATCH "repos/${REPO}/issues/${issue_number}" -f milestone="$target_milestone_id" >/dev/null
                log_success "Remediated: Milestone assigned via REST."
            fi
        else
            log_error "Could not determine milestone for #$issue_number"
            return 1
        fi
    fi
    return 0
}

# ============================================================================
# MODULE 2.5: COMPLIANCE INTEGRITY [NIST-PM-5]
# ============================================================================

check_compliance() {
    local number="$1"
    local title="$2"
    local labels_json="$3"

    local is_epic=$(echo "$labels_json" | jq -r '.[] | select(.name == "type:epic")' >/dev/null 2>&1 && echo "true" || echo "false")

    if [[ "$is_epic" == "true" ]]; then
        if [[ ! "$title" =~ ^\[EPIC\] ]]; then
            log_warn "EPIC #$number: Title missing [EPIC] prefix."
            if [[ "$DRY_RUN" == "false" ]]; then
                # 10X REPLACEMENT: Use REST API to bypass GraphQL rate limits
                gh api -X PATCH "repos/${REPO}/issues/${number}" -f title="[EPIC] $title" >/dev/null
                log_success "Remediated: Added [EPIC] prefix via REST."
            fi
        fi
    fi
}

# ============================================================================
# MODULE 3: LOAD BALANCER [NIST-AC-2]
# ============================================================================

# Pre-calculate user loads to avoid redundant API calls and rate limits
declare -A USER_LOADS

calculate_all_loads() {
    log_info "Pre-calculating user workloads via REST API..."
    # Fetch all open issues with assignees to calculate load in one pass
    local all_open=$(gh api "repos/${REPO}/issues?state=open&per_page=100")

    # Reset loads
    USER_LOADS=()

    while IFS= read -r user; do
        if [[ -n "$user" && "$user" != "null" ]]; then
            ((USER_LOADS["$user"]++)) || USER_LOADS["$user"]=1
        fi
    done < <(echo "$all_open" | jq -r '.[] | .assignees[].login')
}

check_user_load() {
    local user="$1"
    local load=${USER_LOADS["$user"]:-0}

    if [[ "$load" -ge "$MAX_LOAD_PER_USER" ]]; then
        log_warn "Bottleneck: @$user has $load active tasks (Limit: $MAX_LOAD_PER_USER)"
        return 1
    fi
    return 0
}

# ============================================================================
# MODULE 4: PR REVIEW ENFORCEMENT [NIST-AC-2]
# ============================================================================

audit_pr_reviews() {
    local pr_number="$1"
    # Use REST API for PR review requests too
    local review_count=$(gh api "repos/${REPO}/pulls/${pr_number}/requested_reviewers" | jq '.users | length')

    if [[ "$review_count" -eq 0 ]]; then
        log_warn "PR #$pr_number: No reviewers assigned."
        if [[ "$DRY_RUN" == "false" ]]; then
            local reviewers=$(bash scripts/pmo/pr_reviewer_selector.sh "$REPO" "$pr_number" 2>/dev/null || echo "")
            if [[ -n "$reviewers" ]]; then
                gh pr edit "$pr_number" --repo "$REPO" --add-reviewer "$reviewers"
                log_success "Remediated: Reviewers assigned ($reviewers)."
            fi
        fi
        return 1
    fi
    return 0
}

# ============================================================================
# MAIN AUDIT LOOP
# ============================================================================

header() {
    echo -e "\n${BLUE}══════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  🛡️ PMO SENTINEL: GLOBAL GOVERNANCE AUDIT ($REPO) ${NC}"
    echo -e "${BLUE}══════════════════════════════════════════════════════════════════${NC}"
    echo -e "Mode: $( [[ "$DRY_RUN" == "true" ]] && echo "AUDIT (Dry Run)" || echo "ENFORCEMENT (Live)" )"
}

main() {
    header

    calculate_all_loads

    log_info "Fetching issue batch (Size: $BATCH_SIZE) via REST API for maximum performance..."
    # 10X Upgrade: Use REST API to bypass GraphQL rate limits and increase speed
    local issues=$(gh api "repos/${REPO}/issues?state=open&per_page=${BATCH_SIZE}&sort=updated&direction=desc")

    # Use -r to get raw output from jq (no quotes)
    if [[ $(echo "$issues" | jq -r 'type' 2>/dev/null) != "array" ]]; then
        log_error "Failed to fetch issues or rate limited. Response summary:"
        echo "$issues" | jq -c '.message' 2>/dev/null || echo "$issues"
        return 1
    fi

    local total=0
    local failing=0

    # Process Issues
    while IFS= read -r issue; do
        ((total++)) || true
        local number=$(echo "$issue" | jq -r '.number')
        local title=$(echo "$issue" | jq -r '.title')
        local milestone_title=$(echo "$issue" | jq -r '.milestone.title // "null"')
        local labels_json=$(echo "$issue" | jq -c '.labels')
        local body=$(echo "$issue" | jq -r '.body // ""')

        # Extract login names from assignees
        local assignees=$(echo "$issue" | jq -r '.assignees[].login // "null"')

        echo -e "\n🔍 Analyzing Issue #$number: $title"

        # Milestone Enforcement
        enforce_milestone "$number" "$milestone_title" "$title" "$body" "$labels_json" || ((failing++)) || true

        # Compliance Prefixing
        check_compliance "$number" "$title" "$labels_json" || ((failing++)) || true

        # Label Integrity
        scan_label_integrity "$number" "$title" "$body" "$labels_json" || ((failing++)) || true

        # Assignee Check & Load Balance
        if [[ -z "$assignees" || "$assignees" == "null" ]]; then
            log_warn "Issue #$number: Unassigned."
            if [[ "$DRY_RUN" == "false" ]]; then
                bash scripts/pmo/assignee_enforcer.sh --issue "$number"
            fi
        else
            for user in $assignees; do
                check_user_load "$user" || true
            done
        fi
    done < <(echo "$issues" | jq -c '.[]')

    log_info "Fetching PR batch via REST API..."
    local prs=$(gh api "repos/${REPO}/pulls?state=open&per_page=${BATCH_SIZE}")

    while IFS= read -r pr; do
        ((total++)) || true
        local number=$(echo "$pr" | jq -r '.number')
        local title=$(echo "$pr" | jq -r '.title')

        echo -e "\n🔍 Analyzing PR #$number: $title"
        audit_pr_reviews "$number" || ((failing++)) || true
    done < <(echo "$prs" | jq -c '.[]' 2>/dev/null || echo "")

    echo -e "\n${BLUE}══════════════════════════════════════════════════════════════════${NC}"
    if [[ "$total" -gt 0 ]]; then
        log_info "Audit Complete. Score: $(( (total-failing)*100/total ))% Compliance"
        [[ "$failing" -gt 0 ]] && log_warn "Found $failing integrity issues." || log_success "Zero defects found in batch."
    else
        log_info "No items to audit."
    fi
}

# Helper to avoid issues with empty values
issue_val() {
    echo "$1" | jq -r "$2"
}

main "$@"
