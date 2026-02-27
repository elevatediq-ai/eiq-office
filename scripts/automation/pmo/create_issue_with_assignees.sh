#!/bin/bash
##############################################################################
# Create Issue with Auto-Assigned Assignees
# Purpose: Interactive CLI wizard for assignee-aware issue creation
# Session: 20260216-ASSIGNEE-AUTOMATION
# FedRAMP: [NIST-CM-3] Configuration management with audit trail
##############################################################################

set -euo pipefail

REPO="${REPO:-kushin77/ElevatedIQ-Mono-Repo}"

log_info() { echo "ℹ️  $*"; }
log_success() { echo "✅ $*"; }
log_section() { echo; echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; echo "📋 $*"; echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; }

# Interactive prompts
prompt_issue_title() {
    local title=""
    while [[ -z "$title" ]]; do
        echo -n "📝 Issue Title: "
        read -r title
        [[ -z "$title" ]] && echo "❌ Title cannot be empty"
    done
    echo "$title"
}

prompt_issue_description() {
    echo -n "📄 Issue Description (or 'skip'): "
    read -r description
    echo "$description"
}

prompt_issue_labels() {
    echo -n "🏷️  Labels (comma-separated, or 'skip'): "
    read -r labels
    echo "$labels"
}

prompt_issue_milestone() {
    log_info "Available milestones:"
    gh milestone list --repo "$REPO" --json "number,title" | jq -r '.[] | "\(.number): \(.title)"' || true

    echo -n "🎯 Milestone number (or 'skip'): "
    read -r milestone
    echo "$milestone"
}

confirm_before_create() {
    local title="$1"
    local description="$2"
    local labels="$3"
    local milestone="$4"
    local assignees="$5"

    echo
    echo "╔════════════════════════════════════════════════╗"
    echo "║           REVIEW BEFORE CREATING              ║"
    echo "╠════════════════════════════════════════════════╣"
    echo "Title:       $title"
    echo "Description: ${description:0:35}..."
    echo "Labels:      ${labels:-none}"
    echo "Milestone:   ${milestone:-none}"
    echo "Auto-Assign: ${assignees:-none}"
    echo "╚════════════════════════════════════════════════╝"
    echo

    echo -n "Create this issue? (y/n): "
    read -r confirm
    [[ "$confirm" == "y" ]] && return 0 || return 1
}

# Create the issue
create_issue() {
    local title="$1"
    local description="$2"
    local labels="$3"
    local milestone="$4"
    local assignees="$5"

    local cmd="gh issue create --repo '$REPO' --title '$title'"

    [[ "$description" != "skip" ]] && cmd="$cmd --body '$(echo "$description" | sed "s/'/'\"'\"'/g")'"

    if [[ "$labels" != "skip" && -n "$labels" ]]; then
        cmd="$cmd --label '$(echo "$labels" | sed "s/, */,/g")'"
    fi

    if [[ "$milestone" != "skip" && -n "$milestone" ]]; then
        cmd="$cmd --milestone '$milestone'"
    fi

    # Create the issue
    local issue_number=$(eval "$cmd" | grep -oE '#[0-9]+' | tr -d '#')

    if [[ -n "$issue_number" ]]; then
        log_success "Issue #$issue_number created!"

        # Assign if assignees provided
        if [[ "$assignees" != "skip" && -n "$assignees" ]]; then
            log_info "Assigning to: $assignees"
            for assignee in $(echo "$assignees" | tr ',' ' ' | sed 's/ $//'); do
                gh issue edit "$issue_number" --add-assignee "$assignee" --repo "$REPO" 2>/dev/null || true
            done
            log_success "Issue #$issue_number assigned!"
        fi

        echo "$issue_number"
    else
        log_info "Failed to create issue"
        return 1
    fi
}

# Main flow
main() {
    log_section "Create Issue with Auto-Assignees"

    # Collect inputs
    local title=$(prompt_issue_title)
    local description=$(prompt_issue_description)
    local labels=$(prompt_issue_labels)
    local milestone=$(prompt_issue_milestone)

    # Analyze and suggest assignees
    log_section "Analyzing for Auto-Assignees"
    log_info "Running smart assignee selector..."

    local assignees=$(bash scripts/pmo/smart_assignee_selector.sh "$REPO" "" "$title" "$description" "" 2>/dev/null || echo "")

    if [[ -n "$assignees" ]]; then
        log_success "Found potential assignees:"
        echo "$assignees" | nl -w2 -s'. '
        assignees=$(echo "$assignees" | paste -sd ',' -)
    else
        log_info "No automatic assignees detected"
        assignees="skip"
    fi

    # Confirm and create
    if confirm_before_create "$title" "$description" "$labels" "$milestone" "$assignees"; then
        create_issue "$title" "$description" "$labels" "$milestone" "$assignees"
    else
        log_info "Issue creation cancelled"
        return 1
    fi
}

main "$@"
