#!/bin/bash
##############################################################################
# Assignee Enforcement Engine - Auto-Assign Issues Based on Git History
# Purpose: Ensure every issue has at least one assignee
# Session: 20260216-ASSIGNEE-AUTOMATION-HARDENING
# Issue: #3286
# FedRAMP: [NIST-AC-2] Account management with automatic assignment
# Frequency: Every 5 minutes (via GitHub Actions)
# Mandate: NO ISSUE LEFT WITHOUT ASSIGNEES
##############################################################################

set -euo pipefail

REPO="${REPO:-kushin77/ElevatedIQ-Mono-Repo}"
BATCH_SIZE="${BATCH_SIZE:-100}"
DRY_RUN="${DRY_RUN:-false}"
if [[ "$*" == *"--dry-run"* ]]; then
    DRY_RUN="true"
fi
LOG_FILE="${LOG_FILE:-./scripts/pmo/logs/assignee_enforcer.log}"

# Source centralized logging lib for consistent helpers
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export LOG_FILE
if [[ "${DEBUG:-false}" == "true" ]]; then
    export LOG_LEVEL=DEBUG
fi
if [[ -f "${script_dir}/../lib/logging.sh" ]]; then
    # shellcheck source=/dev/null
    source "${script_dir}/../lib/logging.sh"
else
    # Fallback minimal logger
    log_info() { echo "[INFO] $*" >&2; }
    log_warn() { echo "[WARN] $*" >&2; }
    log_error() { echo "[ERROR] $*" >&2; }
    log_debug() { [[ "${DEBUG:-false}" == "true" ]] && echo "[DEBUG] $*" >&2; }
    log_success() { echo "[SUCCESS] $*" >&2; }
fi

# Create log directory if it doesn't exist
mkdir -p "$(dirname "$LOG_FILE")"

# Get issues without assignees
get_issues_without_assignees() {
    local state="${1:-open}"
    log_info "Fetching $state issues without assignees via REST API..."

    # 10X Upgrade: Use REST API to bypass GraphQL rate limits
    local result=$(gh api "repos/${REPO}/issues?state=${state}&per_page=${BATCH_SIZE}&assignee=none" 2>/dev/null || echo "[]")

    # Ensure valid JSON output
    if [[ -z "$result" ]] || [[ "$result" == "null" ]]; then
        echo "[]"
    else
        echo "$result"
    fi
}

# Get files modified in PRs related to the issue
get_related_files() {
    local issue_number="$1"
    local issue_title="$2"

    # Search for closed PRs with related keywords
    keywords=$(echo "$issue_title" | tr '[:upper:]' '[:lower:]' | grep -oE '\b[a-z]{4,}\b' | head -3 | tr '\n' '|' | sed 's/|$//')

    if [[ -n "$keywords" ]]; then
        gh pr list --repo "$REPO" --search "state:closed in:title $keywords" \
            --limit 5 --json "files" 2>/dev/null | \
        jq -r '.[] | select(.files != null) | .files[].path' 2>/dev/null | head -20 || echo ""
    fi
}

# Get author and recent contributors
get_candidate_assignees() {
    local issue_number="$1"
    local issue_title="$2"
    local issue_body="$3"
    local files="$4"

    log_info "Analyzing candidates for issue #$issue_number..."

    # Run smart selector
    local result=$(bash scripts/pmo/smart_assignee_selector.sh "$REPO" "$issue_number" "$issue_title" "$issue_body" "$files" 2>/dev/null || echo "")

    echo "$result"
}

# Assign issue to selected assignees
assign_issue() {
    local issue_number="$1"
    local assignees="$2"

    if [[ -z "$assignees" ]]; then
        log_warn "Issue #$issue_number: No assignees could be determined. Skipping."
        return 1
    fi

    # Convert comma-separated to space-separated for gh command
    local assignee_list=$(echo "$assignees" | tr ',' ' ')

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would assign #$issue_number to: $assignee_list"
        return 0
    fi

    log_info "Assigning #$issue_number to: $assignee_list"

    local any_assigned=false
    # Add assignees one by one (gh doesn't support multiple adds in single command)
    for assignee in $assignee_list; do
        if gh issue edit "$issue_number" --add-assignee "$assignee" --repo "$REPO" >/dev/null 2>&1; then
            log_success "Assigned #$issue_number to @$assignee"
            any_assigned=true
        else
            log_error "Failed to assign #$issue_number to @$assignee"
            # continue attempting other assignees instead of failing the whole call
        fi
    done

    if [[ "$any_assigned" == true ]]; then
        return 0
    else
        return 1
    fi
}

# Add enforcement comment to issue
add_enforcement_comment() {
    local issue_number="$1"
    local assignees="$2"

    if [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi

    local comment="🤖 **Auto-Assignment Completed**

✅ This issue has been automatically assigned based on git history analysis and domain expertise matching.

**Assigned to:** $(echo "$assignees" | tr ',' '\n' | sed 's/^/@/' | paste -sd ',' -)"

    gh issue comment "$issue_number" --repo "$REPO" --body "$comment" >/dev/null 2>&1 || true
}


# Sanitize assignee list: remove invalid tokens and non-collaborators
sanitize_assignee_list() {
    local raw="$1"
    local whitelist_file="docs/management/valid_assignees.txt"
    local -a known=()
    local -a out=()

    # Load known repo assignees (cache file preferred)
    if [[ -f "$whitelist_file" ]]; then
        mapfile -t known < "$whitelist_file"
    else
        mapfile -t known < <(gh api repos/"$REPO"/assignees --jq '.[].login' 2>/dev/null || true)
    fi

    for token in $(echo "$raw" | tr ',\n' ' '); do
        token=$(echo "$token" | sed 's/^@//; s|^app/||; s/[^a-zA-Z0-9-]//g')
        [[ -z "$token" ]] && continue
        [[ "$token" =~ ^[0-9]+$ ]] && log_debug "Skipping numeric token '$token'" && continue

        # GitHub login pattern
        if [[ ! "$token" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{0,38}$ ]]; then
            log_debug "Skipping malformed token '$token'"
            continue
        fi

        if printf '%s\n' "${known[@]}" | grep -qx "$token"; then
            out+=("$token")
        else
            log_debug "User '$token' not in repo assignees/collaborators; skipping"
        fi
    done

    # Return comma-separated list
    if [[ ${#out[@]} -gt 0 ]]; then
        echo "${out[*]}" | tr ' ' ','
    else
        echo ""
    fi
}

# Process batch of issues
process_issue_batch() {
    local issues_json="$1"
    local count=0
    local assigned=0
    local failed=0

    # Validate JSON first
    if ! echo "$issues_json" | jq empty 2>/dev/null; then
        log_warn "Invalid JSON response, skipping batch"
        echo "0:0"
        return
    fi

    # Check if array is empty
    local json_size=$(echo "$issues_json" | jq '. | length' 2>/dev/null | head -n 1 || echo 0)
    if [[ ! "$json_size" =~ ^[0-9]+$ ]] || [[ "$json_size" -eq 0 ]]; then
        log_info "No valid unassigned issues to process"
        echo "0:0"
        return
    fi

    while IFS= read -r issue_line; do
        [[ -z "$issue_line" ]] && continue
        ((count++))

        local number=$(echo "$issue_line" | jq -r '.number // empty' 2>/dev/null)
        local title=$(echo "$issue_line" | jq -r '.title // "Untitled"' 2>/dev/null)

        [[ -z "$number" ]] && continue

        local body=$(echo "$issue_line" | jq -r '.body // ""' 2>/dev/null)

        log_info "Processing issue #$number ($count/$BATCH_SIZE): $title"

        # Get related files
        local files=$(get_related_files "$number" "$title" || echo "")

        # Get candidate assignees
        local raw_assignees=$(get_candidate_assignees "$number" "$title" "$body" "$files" || echo "")

        # Sanitize output from the smart selector (drop numeric/malformed tokens)
        local assignees=$(sanitize_assignee_list "$raw_assignees" || echo "")

        if [[ -z "$assignees" ]]; then
            log_warn "Issue #$number: No valid assignees after sanitization (raw: '$raw_assignees')"

            # Mark for PMO triage so a human can review (do not attempt assignment)
            if [[ "$DRY_RUN" != "true" ]]; then
                gh issue edit "$number" --add-label "status:triage-pending" --repo "$REPO" >/dev/null 2>&1 || true
                gh issue comment "$number" --repo "$REPO" --body "⚠️ Auto-assignment found invalid candidates; marking as status:triage-pending for PMO review." >/dev/null 2>&1 || true
            fi

            continue
        fi

        if assign_issue "$number" "$assignees"; then
            add_enforcement_comment "$number" "$assignees"
            ((assigned++))
            log_success "Issue #$number assigned successfully"
        else
            ((failed++))
            log_error "Issue #$number assignment failed"
        fi

    done < <(echo "$issues_json" | jq -c '.[]' 2>/dev/null || true)

    echo "$assigned:$failed"
}

# Generate enforcement report
generate_report() {
    local assigned="$1"
    local failed="$2"
    local total=$((assigned + failed))

    local report_msg="
╔════════════════════════════════════════════════════════════╗
║         ASSIGNEE ENFORCEMENT REPORT ($(date '+%Y-%m-%d %H:%M:%S'))          ║
╠════════════════════════════════════════════════════════════╣
║ Issues Processed:        $total                              ║
║ Successfully Assigned:   $assigned                              ║
║ Assignment Failed:       $failed                              ║
║ Success Rate:            $([[ $total -gt 0 ]] && echo "$(( assigned * 100 / total ))%" || echo "0%")                           ║
║ Repository:              $REPO                  ║
║ Dry Run:                 $DRY_RUN                           ║
╚════════════════════════════════════════════════════════════╝
"
    log_info "$report_msg"

    return 0
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    log_info "🚀 Assignee Enforcement Engine Started"
    log_info "Repository: $REPO"
    log_info "Batch Size: $BATCH_SIZE"
    log_info "Dry Run Mode: $DRY_RUN"

    # Process open issues
    local open_issues=$(get_issues_without_assignees "open")

    # Initialize counters
    local assigned=0
    local failed=0

    if [[ "$open_issues" == "[]" ]]; then
        log_success "All open issues have assignees ✅"
    else
        log_info "Found open issues without assignees"

        # Process batch and parse results (format: assigned:failed)
        local result=$(process_issue_batch "$open_issues" || echo "0:0")
        assigned=$(echo "$result" | cut -d: -f1 || echo 0)
        failed=$(echo "$result" | cut -d: -f2 || echo 0)

        assigned=${assigned:-0}
        failed=${failed:-0}
    fi

    generate_report "$assigned" "$failed"

    # Optional: Also process recently closed issues (last 7 days)
    local closed_issues=$(gh issue list --repo "$REPO" --state closed --search "no:assignee" \
        --limit 20 --json "number,title,body,author,closedAt" 2>/dev/null | \
        jq '.[] | select(.closedAt | fromdateiso8601 > (now - 604800))' | jq -s '.' 2>/dev/null || echo "[]")

    if [[ "$closed_issues" != "[]" && "$closed_issues" != "" ]]; then
        log_info "Backfilling assignees for recently closed issues..."
        local result=$(process_issue_batch "$closed_issues" || echo "0:0")

        # Parse counts safely
        local assigned=$(echo "$result" | grep -oE '[0-9]+:[0-9]+' | cut -d: -f1 || echo 0)
        local failed=$(echo "$result" | grep -oE '[0-9]+:[0-9]+' | cut -d: -f2 || echo 0)

        assigned=${assigned:-0}
        failed=${failed:-0}

        generate_report "$assigned" "$failed"
    fi

    log_success "Assignee Enforcement Engine Complete"
}

# Execute main function only when script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
