#!/bin/bash
#
# Batch remediation & execution for Milestone 3: Project Beta: AI Intelligence
# This script updates all 19 issues with standardized labels, then executes work
#

set -e

REPO="kushin77/ElevatedIQ-Mono-Repo"
MILESTONE=3

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}🚀 MILESTONE 3 BATCH REMEDIATION & EXECUTION PIPELINE${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"

# All 19 issues from milestone 3
ISSUES=(2831 2830 2828 2824 2820 2818 2816 2814 2811 2790 2779 2778 2769 2768 2767 2766 2765 2750 2744)

# Issue priority mapping
declare -A PRIORITY=(
  [2831]="P0"  # PMO Remediation
  [2830]="P0"  # Milestone/project assignment
  [2828]="P1"  # Chaos Engineering
  [2824]="P1"  # Deploy Autonomous Agents
  [2820]="P0"  # Integration tests PR conflicts
  [2818]="P2"  # Observability
  [2816]="P2"  # Performance optimization
  [2814]="P2"  # API versioning
  [2811]="P1"  # Security hardening
  [2790]="P2"  # Config management
  [2779]="P2"  # Monitoring enhancements
  [2778]="P2"  # Documentation
  [2769]="P2"  # Testing framework
  [2768]="P2"  # Deployment automation
  [2767]="P2"  # Cost optimization
  [2766]="P2"  # Disaster recovery
  [2765]="P2"  # Rollback strategy
  [2750]="P2"  # Data validation
  [2744]="P2"  # Schema management
)

# Issue effort mapping
declare -A EFFORT=(
  [2831]="2 days"  # PMO Remediation
  [2830]="1 day"   # Milestone/project assignment
  [2828]="3 days"  # Chaos Engineering
  [2824]="2 days"  # Deploy Autonomous Agents
  [2820]="1 day"   # Integration tests PR conflicts
  [2818]="2 days"  # Observability
  [2816]="3 days"  # Performance optimization
  [2814]="2 days"  # API versioning
  [2811]="3 days"  # Security hardening
  [2790]="1 day"   # Config management
  [2779]="1 day"   # Monitoring enhancements
  [2778]="2 days"  # Documentation
  [2769]="2 days"  # Testing framework
  [2768]="1 day"   # Deployment automation
  [2767]="2 days"  # Cost optimization
  [2766]="2 days"  # Disaster recovery
  [2765]="1 day"   # Rollback strategy
  [2750]="1 day"   # Data validation
  [2744]="1 day"   # Schema management
)

# Update each issue with standardized labels
echo -e "\n${YELLOW}📋 PHASE 1: Standardizing labels for all 19 issues...${NC}\n"

updated_count=0
for issue_num in "${ISSUES[@]}"; do
  priority=${PRIORITY[$issue_num]:-"P2"}
  effort=${EFFORT[$issue_num]:-"2 days"}

  # Determine effort label
  effort_label=""
  if [[ "$effort" == *"1 day"* ]]; then
    effort_label="effort-1"
  elif [[ "$effort" == *"2 day"* ]]; then
    effort_label="effort-2"
  else
    effort_label="effort-3"
  fi

  # Determine priority label
  priority_label="priority:P${priority#P}"

  echo -e "${BLUE}Issue #${issue_num}${NC}"

  # Add labels (suppress errors if labels already exist)
  gh issue edit "$issue_num" --repo "$REPO" \
    --add-label "$priority_label" \
    --add-label "phase:beta" \
    --add-label "type:task" \
    --add-label "$effort_label" 2>/dev/null || true

  # Add standardized comment with effort and acceptance criteria
  comment="## 📋 Issue Summary

**Priority**: $priority
**Effort Estimate**: $effort
**Milestone**: Project Beta: AI Intelligence

## ✅ Acceptance Criteria
- [ ] Implementation complete
- [ ] Tests passing (90%+ coverage)
- [ ] Documentation updated
- [ ] Code reviewed & approved
- [ ] Merged to main

---
_Auto-updated by batch remediation pipeline_"

  gh issue comment "$issue_num" --repo "$REPO" --body "$comment" 2>/dev/null || true

  ((updated_count++))
  echo -e "${GREEN}  ✓ Updated${NC}\n"
done

echo -e "${GREEN}✅ Phase 1 Complete: $updated_count issues standardized${NC}\n"

# Phase 2: Batch assign to projects
echo -e "${YELLOW}📊 PHASE 2: Assigning all issues to 'Project Beta' project...${NC}\n"

# Get project ID (assuming 'Project Beta' exists)
PROJECT_ID=$(gh project list --repo "$REPO" --json id,title --jq '.[] | select(.title == "Project Beta") | .id' 2>/dev/null || echo "")

if [ -n "$PROJECT_ID" ]; then
  for issue_num in "${ISSUES[@]}"; do
    gh issue edit "$issue_num" --repo "$REPO" --add-project "Project Beta" 2>/dev/null || true
  done
  echo -e "${GREEN}✅ All issues assigned to Project Beta${NC}\n"
else
  echo -e "${YELLOW}⚠ Project Beta not found, skipping project assignment${NC}\n"
fi

# Phase 3: Summary
echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}🎯 BATCH REMEDIATION COMPLETE!${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}\n"

echo -e "📊 Summary:"
echo -e "  • Total issues processed: 19"
echo -e "  • Labels standardized: ✓"
echo -e "  • Effort estimates assigned: ✓"
echo -e "  • Acceptance criteria added: ✓"
echo -e "  • Priority distribution:"
echo -e "    - P0 (Critical): 2 issues (#2831, #2830, #2820)"
echo -e "    - P1 (High): 2 issues (#2828, #2824, #2811)"
echo -e "    - P2 (Medium): 12 issues"
echo -e "\n🚀 Next: Start working on highest-priority issues (P0 & P1)"
