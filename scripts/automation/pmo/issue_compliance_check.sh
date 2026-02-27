#!/usr/bin/env bash
# ==============================================================================
# Issue Compliance Checker - Elite PMO
# ==============================================================================
# Purpose: Ensures GitHub issues meet quality standards
# FedRAMP: CM-3 (Change Management)
# ==============================================================================

set -euo pipefail

REPO="kushin77/ElevatedIQ-Mono-Repo"
NC='\033[0m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'

check_issue() {
    local issue_number="$1"
    echo -e "${CYAN}Checking issue #${issue_number}...${NC}"

    local data=$(gh issue view "$issue_number" --repo "$REPO" --json title,body,labels)
    local title=$(echo "$data" | jq -r .title)
    local body=$(echo "$data" | jq -r .body)
    local labels=$(echo "$data" | jq -r '.labels[].name')

    local errors=0

    # 1. Check for Mandatory Labels
    if [[ ! "$labels" =~ type: ]]; then
        echo -e "${RED}✖ Missing type label (type:*)${NC}"
        ((errors++))
    fi

    if [[ ! "$labels" =~ priority: ]]; then
        echo -e "${RED}✖ Missing priority label (priority:*)${NC}"
        ((errors++))
    fi

    # 2. Check for Acceptance Criteria
    if [[ ! "$body" =~ "Acceptance Criteria" ]]; then
        echo -e "${RED}✖ Missing Acceptance Criteria section${NC}"
        ((errors++))
    fi

    # 3. Check for Effort Estimate
    if [[ ! "$body" =~ "Effort" ]]; then
        echo -e "${RED}✖ Missing Effort Estimate${NC}"
        ((errors++))
    fi

    if [ "$errors" -eq 0 ]; then
        echo -e "${GREEN}✓ Issue #${issue_number} is compliant${NC}"
        return 0
    else
        echo -e "${YELLOW}⚠ Issue #${issue_number} has $errors non-compliance issues${NC}"
        return 1
    fi
}

list_non_compliant() {
    echo -e "${CYAN}Scanning open issues for compliance...${NC}"
    local issues=$(gh issue list --repo "$REPO" --state open --json number --jq '.[].number')

    for issue in $issues; do
        check_issue "$issue" || true
    done
}

main() {
    case "${1:-scan}" in
        check)
            check_issue "${2:-}"
            ;;
        scan)
            list_non_compliant
            ;;
        *)
            echo "Usage: $0 {check <issue#>|scan}"
            ;;
    esac
}

main "$@"
