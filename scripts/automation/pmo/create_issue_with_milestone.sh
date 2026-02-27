#!/usr/bin/env bash
##############################################################################
# create_issue_with_milestone.sh
# 10X Interactive Issue Creator with Mandatory Milestone Alignment
# FedRAMP: [NIST-PM-5] Standardized Project Management
##############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="kushin77/ElevatedIQ-Mono-Repo"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

header() {
    echo -e "${BLUE}🎯 ElevatedIQ: Interactive Issue Creator${NC}"
    echo "=========================================================="
}

main() {
    header

    # 1. Gather Basic Info
    read -p "Issue Title: " TITLE
    if [[ -z "$TITLE" ]]; then echo -e "${RED}Error: Title required${NC}"; exit 1; fi

    read -p "Type (task/bug/epic/security): " TYPE; TYPE=${TYPE:-task}
    read -p "Priority (p0/p1/p2): " PRIORITY; PRIORITY=${PRIORITY:-p1}

    echo "Issue Description (Ctrl+D to finish):"
    BODY="$(cat)" || true

    # 2. Heuristic Alignment
    echo -e "\n${YELLOW}🧠 Calculating Smart Milestone...${NC}"
    MILESTONE_ID=$(bash "$SCRIPT_DIR/smart_milestone_selector.sh" "$TITLE" "$BODY" "[]")

    if [[ -n "$MILESTONE_ID" ]]; then
        echo -e "${GREEN}✅ Alignment Found: ID $MILESTONE_ID${NC}"
    else
        echo -e "${YELLOW}⚠️ No alignment found. Defaulting to Backlog (#28)${NC}"
        MILESTONE_ID="28"
    fi

    # 3. Create using Standard Helper
    source "$SCRIPT_DIR/issue_creation_helper.sh"
    create_issue_standard "$TITLE" "$BODY" "type:$TYPE,priority-$PRIORITY" "$MILESTONE_ID"
    exit 0
}

main "$@"

echo ""
read -p "Labels (comma-separated, e.g., task,priority-p1,phase-1): " LABELS
LABELS=${LABELS:-"$TYPE,priority-$PRIORITY"}

# Step 2: Calculate milestone using smart selector
echo ""
echo -e "${BLUE}🧠 Calculating smart milestone...${NC}"

MILESTONE=$("$SCRIPT_DIR/smart_milestone_selector.sh" "$TITLE" "$BODY" "$LABELS")

if [[ -z "$MILESTONE" ]]; then
  echo -e "${YELLOW}⚠️ Smart selector returned empty, defaulting to 'Project Eta: Backlog'${NC}"
  MILESTONE="Project Eta: Backlog"
fi

echo -e "${GREEN}✅ Selected Milestone: $MILESTONE${NC}"
echo ""

# Step 3: Preview the issue
echo -e "${YELLOW}📋 Issue Preview${NC}"
echo "----------------------------------------"
echo "Title: $TITLE"
echo "Labels: $LABELS"
echo "Milestone: $MILESTONE"
echo "Body:"
echo "$BODY"
echo "----------------------------------------"
echo ""

read -p "Create this issue? (y/n): " CONFIRM

if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
  echo -e "${YELLOW}❌ Issue creation cancelled${NC}"
  exit 0
fi

# Step 4: Create the issue
echo ""
echo -e "${BLUE}🚀 Creating issue...${NC}"

ISSUE_URL=$(gh issue create --repo "$REPO" \
  --title "$TITLE" \
  --label "$LABELS" \
  --milestone "$MILESTONE" \
  --body "$BODY")

if [[ $? -eq 0 ]]; then
  echo -e "${GREEN}✅ Issue created successfully!${NC}"
  echo -e "${GREEN}📎 URL: $ISSUE_URL${NC}"

  # Extract issue number
  ISSUE_NUMBER=$(echo "$ISSUE_URL" | grep -oP '\d+$')
  echo -e "${GREEN}🔢 Issue Number: #$ISSUE_NUMBER${NC}"

  # Log to session tracker if available
  if [[ -x "$SCRIPT_DIR/session_tracker.sh" ]]; then
    "$SCRIPT_DIR/session_tracker.sh" update issue "Created issue #$ISSUE_NUMBER: $TITLE (Milestone: $MILESTONE)" || true
  fi
else
  echo -e "${RED}❌ Failed to create issue${NC}"
  exit 1
fi
