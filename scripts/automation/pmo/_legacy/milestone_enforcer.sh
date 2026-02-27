#!/bin/bash
#
# PMO Milestone Enforcer
# Purpose: Validate and enforce milestone/phase labels and issue hygiene hourly
# Runs hourly to validate and auto-fix issue categorization
# Enforcement rules per NIST-PM-5 governance standards
#

set -e

REPO="kushin77/ElevatedIQ-Mono-Repo"
PHASE_MAP=(
  "phase-6:9"
  "phase-7:10"
  "phase-9-2b:11"
  "phase-9.2b:11"
  "operations:11"
  "phase-9-3:12"
  "phase-9.3:12"
  "intelligence:12"
  "phase-9-4:13"
  "phase-9.4:13"
  "scaling:13"
  "phase-10:14"
  "foundation:15"
  "ai-native:16"
  "infrastructure:17"
  "security:18"
  "finops:19"
  "pmo:20"
  "phase-2:21"
)

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 PMO Milestone Enforcer - Starting at $(date)${NC}"
echo "Repository: $REPO"
echo ""

# Stats
STATS_FIXED=0
STATS_WARNED=0
STATS_ERROR=0
STATS_OK=0

# Rule 1: Enforce phase labels exist
echo -e "${BLUE}📋 Rule 1: Checking for missing phase labels...${NC}"
UNPHASED=$(gh api repos/$REPO/issues --jq '.[] | select(.state=="open" and (.labels | length) == 0) | .number' 2>/dev/null || echo "")
if [ ! -z "$UNPHASED" ]; then
  for issue in $UNPHASED; do
    echo -e "${YELLOW}⚠️  Issue #$issue has no labels${NC}"
    gh issue comment $issue --repo $REPO --body "⚠️ **No Phase Detected** - Please add a phase label: \`phase-6\`, \`phase-7\`, \`phase-9-2b\`, \`phase-9-3\`, \`phase-9-4\`, \`phase-10\`, or similar. See [PMO Guidelines](../PMO_AUTOMATION_ARCHITECTURE.md)." 2>/dev/null || true
    ((STATS_WARNED++))
  done
else
  echo -e "${GREEN}✅ All open issues have labels${NC}"
fi
echo ""

# Rule 1.1: Enforce NIST Traceability in Title (BEST PRACTICE)
echo -e "${BLUE}📋 Rule 1.1: Checking for NIST Traceability in titles...${NC}"
NON_NIST=$(gh api repos/$REPO/issues --jq '.[] | select(.state=="open" and (.title | test("\\[NIST-[A-Z]+-[0-9]+\\]") | not)) | .number' 2>/dev/null || echo "")
if [ ! -z "$NON_NIST" ]; then
  for issue in $NON_NIST; do
    echo -e "${YELLOW}⚠️  Issue #$issue missing NIST tag in title${NC}"
    # We won't comment on every single one yet to avoid spam, but we log it for the dashboard
    ((STATS_WARNED++))
  done
else
  echo -e "${GREEN}✅ All open issues have NIST tags${NC}"
fi
echo ""

# Rule 2: Auto-assign missing milestones
echo -e "${BLUE}📋 Rule 2: Auto-assigning missing milestones...${NC}"
UNMILESTONED=$(gh api repos/$REPO/issues --jq '.[] | select(.state=="open" and .milestone==null) | {number: .number, labels: [.labels[].name]}' 2>/dev/null || echo "[]")

if [ "$UNMILESTONED" != "[]" ]; then
  while IFS= read -r line; do
    ISSUE_DATA=$(echo "$line" | jq -r '.number")
    # Extract issue number and labels
    ISSUE_NUM=$(echo "$line" | jq -r '.number')
    LABELS=$(echo "$line" | jq -r '.labels | join(",")')

    # Try to find matching milestone
    MILESTONE=""
    for mapping in "${PHASE_MAP[@]}"; do
      LABEL="${mapping%:*}"
      MILESTONE_ID="${mapping#*:}"
      if [[ "$LABELS" == *"$LABEL"* ]]; then
        MILESTONE="$MILESTONE_ID"
        break
      fi
    done

    if [ ! -z "$MILESTONE" ]; then
      echo -e "${GREEN}✅ Assigning #$ISSUE_NUM to Milestone $MILESTONE${NC}"
      gh api -X PATCH repos/$REPO/issues/$ISSUE_NUM -f milestone=$MILESTONE 2>/dev/null || echo -e "${RED}❌ Failed to assign milestone${NC}"
      ((STATS_FIXED++))
    else
      echo -e "${YELLOW}⚠️  #$ISSUE_NUM: No milestone mapping found for labels: $LABELS${NC}"
      ((STATS_WARNED++))
    fi
  done < <(echo "$UNMILESTONED" | jq -c '.[]')
else
  echo -e "${GREEN}✅ All open issues have milestones assigned${NC}"
fi
echo ""

# Rule 3: Warn about stale session records
echo -e "${BLUE}📋 Rule 3: Checking for stale session records...${NC}"
STALE_RECORDS=$(gh api repos/$REPO/issues --jq ".[] | select(.labels | map(.name) | index(\"session-record\") != null) | select(.updated_at < \"$(date -d '24 hours ago' -Iseconds)\") | .number" 2>/dev/null || echo "")
if [ ! -z "$STALE_RECORDS" ]; then
  for issue in $STALE_RECORDS; do
    echo -e "${YELLOW}⚠️  Stale session record: #$issue (should be archived or closed)${NC}"
    ((STATS_WARNED++))
  done
else
  echo -e "${GREEN}✅ No stale session records detected${NC}"
fi
echo ""

# Rule 4: Check for blocked/urgent items
echo -e "${BLUE}📋 Rule 4: Checking for blocked or urgent issues...${NC}"
URGENT=$(gh api repos/$REPO/issues --jq ".[] | select(.labels | map(.name) | (index(\"blocked\") != null or index(\"urgent\") != null)) | {number: .number, title: .title[:40]} " 2>/dev/null || echo "[]")

if [ "$URGENT" != "[]" ]; then
  URGENT_COUNT=$(echo "$URGENT" | jq 'length // 0')
  echo -e "${YELLOW}⚠️  Found $URGENT_COUNT blocked/urgent issues - recommend review${NC}"
  echo "$URGENT" | jq -r '.[] | "  #\(.number): \(.title)"'
  STATS_WARNED=$((STATS_WARNED + URGENT_COUNT))
else
  echo -e "${GREEN}✅ No urgent or blocked issues detected${NC}"
fi
echo ""

# Summary
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✅ Fixed: $STATS_FIXED${NC}"
echo -e "${YELLOW}⚠️  Warned: $STATS_WARNED${NC}"
if [ $STATS_ERROR -gt 0 ]; then
  echo -e "${RED}❌ Errors: $STATS_ERROR${NC}"
fi
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${GREEN}🚀 PMO Enforcer completed successfully at $(date)${NC}"

# Exit with status
if [ $STATS_ERROR -gt 0 ]; then
  exit 1
fi
exit 0
