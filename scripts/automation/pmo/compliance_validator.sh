#!/bin/bash
# ElevatedIQ: NIST 800-53 Compliance Validator
# Purpose: Automatically verify that files and PRs contain mandatory compliance metadata.

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

echo -e "🔍 ${GREEN}ElevatedIQ Compliance Validator (NIST 800-53)${NC}"

FAILURES=0

# Rule 1: Every ADR must reference a NIST control
echo -e "\nChecking ADRs for NIST mapping..."
for file in docs/architecture/*.md; do
    if ! grep -qE "NIST|FedRAMP" "$file"; then
        echo -e "${RED}[FAIL]${NC} $file missing NIST/FedRAMP control mapping"
        FAILURES=$((FAILURES + 1))
    else
        echo -e "${GREEN}[PASS]${NC} $file"
    fi
done

# Rule 4: Every Terraform module must reference a NIST control
echo -e "\nChecking Terraform files for NIST mapping..."
while IFS= read -r -d '' file; do
    if ! grep -qE "NIST|FedRAMP" "$file"; then
        echo -e "${RED}[FAIL]${NC} $file missing NIST/FedRAMP control mapping"
        FAILURES=$((FAILURES + 1))
    else
        echo -e "${GREEN}[PASS]${NC} $file"
    fi
done < <(find terraform/ infra/terraform/ apps/ -name "*.tf" -not -path "*/.terraform/*" -print0)

# Rule 2: Every script in scripts/ must have a header with Purpose
echo -e "\nChecking scripts for Purpose header..."
for file in scripts/**/*.sh; do
    if ! grep -i "Purpose:" "$file" > /dev/null; then
        echo -e "${RED}[FAIL]${NC} $file missing 'Purpose:' header"
        FAILURES=$((FAILURES + 1))
    else
        echo -e "${GREEN}[PASS]${NC} $file"
    fi
done

# Rule 3: Check for gitleaks config
if [ ! -f ".gitleaks.toml" ]; then
    echo -e "${RED}[FAIL]${NC} .gitleaks.toml missing (Required for NIST-SI-10)"
    FAILURES=$((FAILURES + 1))
else
    echo -e "${GREEN}[PASS]${NC} .gitleaks.toml present"
fi

# Rule 5: Every automated issue must have a Milestone and Project (NIST PM-5)
echo -e "\nChecking for issues missing metadata (NIST PM-5)..."
if [ -f "scripts/pmo/verify-issue-associations.sh" ]; then
    if ! ./scripts/pmo/verify-issue-associations.sh > /dev/null 2>&1; then
       echo -e "${RED}[FAIL]${NC} One or more issues missing Milestone or Project association"
       FAILURES=$((FAILURES + 1))
    else
       echo -e "${GREEN}[PASS]${NC} All issues have required associations"
    fi
fi

if [ $FAILURES -gt 0 ]; then
    echo -e "\n❌ ${RED}Compliance validation failed with $FAILURES issues.${NC}"
    exit 1
else
    echo -e "\n✅ ${GREEN}Compliance validation passed!${NC}"
    exit 0
fi
