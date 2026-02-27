#!/usr/bin/env bash
# ==============================================================================
# Assign Milestones to Issues Without Milestones
# ==============================================================================
# Purpose: Batch assign milestones to existing issues that don't have them
# Uses the same auto-assignment logic as issue creation
# ==============================================================================

set -euo pipefail

REPO="kushin77/ElevatedIQ-Mono-Repo"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER_SCRIPT="$SCRIPT_DIR/issue_creation_helper.sh"

# Load the helper functions
source "$HELPER_SCRIPT"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ==============================================================================
# Assign Milestone to Single Issue
# ==============================================================================
assign_milestone_to_issue() {
    local issue_number="$1"
    local title="$2"
    local labels="$3"

    # Auto-assign milestone
    local milestone
    milestone=$(auto_assign_milestone "$title" "$labels")

    echo -e "${BLUE}Assigning milestone '${milestone}' to issue #$issue_number${NC}"

    if gh issue edit "$issue_number" --repo "$REPO" --milestone "$milestone" 2>/dev/null; then
        echo -e "${GREEN}✓ Assigned milestone to #$issue_number${NC}"
        return 0
    else
        echo -e "${RED}❌ Failed to assign milestone to #$issue_number${NC}"
        return 1
    fi
}

# ==============================================================================
# Main Function
# ==============================================================================
main() {
    echo -e "${YELLOW}🔍 Finding issues without milestones...${NC}"

    # Get issues without milestones (limit to avoid rate limits)
    local issues_json
    issues_json=$(gh issue list --repo "$REPO" --state open --json number,title,labels --limit 50)

    local total_assigned=0
    local total_failed=0

    echo "$issues_json" | jq -c '.[]' | while read -r issue; do
        local number
        number=$(echo "$issue" | jq -r '.number')
        local title
        title=$(echo "$issue" | jq -r '.title')
        local labels
        labels=$(echo "$issue" | jq -r '.labels[].name' | tr '\n' ',' | sed 's/,$//')

        # Check if already has milestone
        local has_milestone
        has_milestone=$(gh issue view "$number" --repo "$REPO" --json milestone --jq '.milestone != null')

        if [[ "$has_milestone" == "true" ]]; then
            echo -e "${BLUE}Issue #$number already has milestone, skipping${NC}"
            continue
        fi

        if assign_milestone_to_issue "$number" "$title" "$labels"; then
            ((total_assigned++))
        else
            ((total_failed++))
        fi

        # Small delay to avoid rate limits
        sleep 1
    done

    echo -e "${GREEN}✅ Assigned milestones to $total_assigned issues${NC}"
    if [ $total_failed -gt 0 ]; then
        echo -e "${RED}❌ Failed to assign to $total_failed issues${NC}"
    fi
}

# Run main if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
