#!/usr/bin/env bash
# ==============================================================================
# Milestone Compliance Validator - Zero-Tolerance Enforcement
# ==============================================================================
# Purpose: Scan all scripts for gh issue create commands missing --milestone
# FedRAMP: CM-3 (Configuration Management)
# Usage: ./validate_milestone_compliance.sh [--fix]
# ==============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIX_MODE=false

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

if [[ "${1:-}" == "--fix" ]]; then
    FIX_MODE=true
    echo -e "${YELLOW}⚠️  Fix mode not implemented - manual review required${NC}"
fi

echo -e "${CYAN}╔═══════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  🔍 Milestone Compliance Validator (Zero-Tolerance)  ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════════╝${NC}"

VIOLATIONS=0
TOTAL_CHECKS=0

# Function to check a file for violations
check_file() {
    local file="$1"
    local violations_in_file=0

    # Find all gh issue create commands
    while IFS= read -r line_num; do
        TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

        # Extract the full command (may span multiple lines)
        local start_line=$line_num
        local end_line=$((line_num + 10))  # Check next 10 lines
        local command_block=$(sed -n "${start_line},${end_line}p" "$file")

        # Check if --milestone is present in the command block
        if ! echo "$command_block" | grep -q -- "--milestone"; then
            violations_in_file=$((violations_in_file + 1))
            echo -e "${RED}❌ VIOLATION:${NC} Line $line_num in ${file#$REPO_ROOT/}"
            echo -e "   ${YELLOW}Missing --milestone parameter${NC}"
            echo -e "   ${CYAN}Context:${NC}"
            sed -n "${start_line},$((start_line + 3))p" "$file" | sed 's/^/     /'
            echo ""
        fi
    done < <(grep -n "gh issue create" "$file" | cut -d':' -f1)

    return $violations_in_file
}

# Scan all shell scripts
echo -e "${CYAN}Scanning shell scripts...${NC}"
while IFS= read -r -d '' file; do
    if check_file "$file"; then
        :
    else
        VIOLATIONS=$((VIOLATIONS + $?))
    fi
done < <(find "$REPO_ROOT/scripts" -type f -name "*.sh" ! -path "*/test_*" ! -path "*/_archived/*" -print0)

# Scan Python scripts
echo -e "${CYAN}Scanning Python scripts...${NC}"
while IFS= read -r -d '' file; do
    # Check for subprocess calls or f-strings with gh issue create
    if grep -q "gh issue create" "$file"; then
        if check_file "$file"; then
            :
        else
            VIOLATIONS=$((VIOLATIONS + $?))
        fi
    fi
done < <(find "$REPO_ROOT/scripts" -type f -name "*.py" ! -path "*/test_*" ! -path "*/_archived/*" -print0)

echo ""
echo -e "${CYAN}╔═══════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  📊 Validation Results                                ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════════╝${NC}"
echo -e "Total gh issue create commands checked: ${TOTAL_CHECKS}"
echo -e "Violations found: ${VIOLATIONS}"

if [ $VIOLATIONS -gt 0 ]; then
    echo ""
    echo -e "${RED}╔═══════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║  ❌ COMPLIANCE FAILURE - IMMEDIATE ACTION REQUIRED    ║${NC}"
    echo -e "${RED}╚═══════════════════════════════════════════════════════╝${NC}"
    echo -e "${YELLOW}All GitHub issue creation MUST include a milestone.${NC}"
    echo -e "${YELLOW}Available milestones:${NC}"
    gh api repos/kushin77/ElevatedIQ-Mono-Repo/milestones --jq '.[] | "  - \(.title)"'
    echo ""
    echo -e "${CYAN}Fix instructions:${NC}"
    echo -e "  Add ${GREEN}--milestone \"Milestone Name\"${NC} to each gh issue create command."
    echo -e "  Default milestone: ${GREEN}\"Project Eta: Backlog\"${NC}"
    exit 1
else
    echo -e "${GREEN}✅ All gh issue create commands include --milestone parameter${NC}"
    echo -e "${GREEN}🎯 100% Milestone Compliance Achieved${NC}"
    exit 0
fi
