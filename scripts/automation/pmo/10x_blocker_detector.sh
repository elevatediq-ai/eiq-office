#!/usr/bin/env bash
# ==============================================================================
# 🚀 ElevatedIQ 10X PMO: Real-Time Blocker Detector (Unified)
# ==============================================================================
# Purpose: Detect stale 'in-progress' issues, auto-escalate, and notify.
# Refs: #3448
# ==============================================================================

set -euo pipefail

REPO="kushin77/ElevatedIQ-Mono-Repo"
STALE_THRESHOLD_SECONDS=14400 # 4 hours

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}🔍 [10X] Scanning for blocked/stale issues (>4h inactive)...${NC}"

# Get all issues marked "in-progress" using efficient jq filter
# Logic: Status is 'in-progress' AND hasn't been updated in 4 hours
IN_PROGRESS_ISSUES=$(gh issue list --repo "$REPO" --label "status:in-progress" --state open --json number,updatedAt,title --jq ".[] | select(.updatedAt < now - $STALE_THRESHOLD_SECONDS) | .number")

if [ -z "$IN_PROGRESS_ISSUES" ]; then
    echo -e "${GREEN}✅ No blocked issues detected (All active <4h).${NC}"
    exit 0
fi

for issue_num in $IN_PROGRESS_ISSUES; do
    echo -e "${RED}⛔ Escalating blocker: #$issue_num...${NC}"

    # 1. Add 'status:blocked' label
    gh issue edit "$issue_num" --repo "$REPO" --add-label "status:blocked" --remove-label "status:in-progress" &> /dev/null

    # 2. Add detailed escalation comment
    gh issue comment "$issue_num" --repo "$REPO" --body "🚨 **AUTO-ESCALATION: Blocker Detected**

This issue has been in-progress for **>4 hours** without updates.

**Potential Blockers Identified:**
- ❓ Waiting on dependency?
- ❓ Test failures?
- ❓ Code review stalled?
- ❓ Infrastructure issue?

**Action Required:**
- [ ] **Still Working**: Comment with update & remove 'blocked' label.
- [ ] **Blocked**: Update description with BLOCKER details.
- [ ] **Need Helf**: Tag @kushin77 for escalation.

_Auto-detected by 10X Blocker Detector_" &> /dev/null

    echo "✅ Auto-escalation complete for #$issue_num"
done

echo -e "${GREEN}✅ Blocker detection cycle complete.${NC}"
