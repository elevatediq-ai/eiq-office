#!/usr/bin/env bash
# ==============================================================================
# Elite PMO Velocity Calculator - Sprint Metrics & Forecasting
# ==============================================================================
# Purpose: Calculate team velocity and forecast sprint capacity
# FedRAMP: PM-5 (Project Management), PM-9 (Risk Management)
# ==============================================================================

set -euo pipefail

# Prefer Go implementation for 50x speedup
GO_VELOCITY_BIN="./apps/pmo-go/bin/velocity-dashboard"
if [ -x "$GO_VELOCITY_BIN" ]; then
    "$GO_VELOCITY_BIN" update
    exit 0
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}📊 Elite Velocity Calculator${NC}"
echo ""

# ==============================================================================
# Calculate Git-based Velocity
# ==============================================================================

echo -e "${CYAN}Git Metrics:${NC}"
echo "  Last 7 days:  $(git -C "$REPO_ROOT" rev-list --since="7 days ago" --count HEAD 2>/dev/null || echo "0") commits"
echo "  Last 30 days: $(git -C "$REPO_ROOT" rev-list --since="30 days ago" --count HEAD 2>/dev/null || echo "0") commits"
echo "  Last 90 days: $(git -C "$REPO_ROOT" rev-list --since="90 days ago" --count HEAD 2>/dev/null || echo "0") commits"

COMMITS_7D=$(git -C "$REPO_ROOT" rev-list --since="7 days ago" --count HEAD 2>/dev/null || echo "0")
COMMITS_30D=$(git -C "$REPO_ROOT" rev-list --since="30 days ago" --count HEAD 2>/dev/null || echo "0")

if [[ $COMMITS_7D -gt 0 ]]; then
    VELOCITY_DAILY=$(echo "scale=2; $COMMITS_7D / 7" | bc)
else
    VELOCITY_DAILY="0.00"
fi

if [[ $COMMITS_30D -gt 0 ]]; then
    VELOCITY_WEEKLY=$(echo "scale=1; $COMMITS_30D / 4.3" | bc)
else
    VELOCITY_WEEKLY="0.0"
fi

echo ""
echo -e "${GREEN}Calculated Velocity:${NC}"
echo "  Daily:  ${VELOCITY_DAILY} commits/day"
echo "  Weekly: ${VELOCITY_WEEKLY} commits/week"

# ==============================================================================
# Forecast Next Sprint
# ==============================================================================

if [[ $(echo "$VELOCITY_DAILY > 0" | bc) -eq 1 ]]; then
    FORECAST_WEEK1=$(echo "scale=0; $VELOCITY_DAILY * 7" | bc)
    FORECAST_WEEK2=$(echo "scale=0; $VELOCITY_DAILY * 6" | bc)  # Slight decrease

    echo ""
    echo -e "${CYAN}Velocity Forecast (Next 2 Weeks):${NC}"
    echo "  Week 1: ~${FORECAST_WEEK1} commits (high confidence)"
    echo "  Week 2: ~${FORECAST_WEEK2} commits (medium confidence)"
else
    echo ""
    echo -e "${YELLOW}⚠ Insufficient data for forecasting${NC}"
fi

# ==============================================================================
# Issue Velocity (if GitHub CLI available)
# ==============================================================================

if command -v gh &> /dev/null; then
    echo ""
    echo -e "${CYAN}GitHub Issue Metrics:${NC}"

    REPO="kushin77/ElevatedIQ-Mono-Repo"

    # Count issues (requires gh CLI and auth)
    ISSUES_OPEN=$(gh issue list --repo "$REPO" --state open --json number --jq '. | length' 2>/dev/null || echo "N/A")
    ISSUES_CLOSED=$(gh issue list --repo "$REPO" --state closed --limit 100 --json number --jq '. | length' 2>/dev/null || echo "N/A")

    echo "  Open Issues:   $ISSUES_OPEN"
    echo "  Closed (last): $ISSUES_CLOSED"

    if [[ "$ISSUES_OPEN" != "N/A" && "$ISSUES_CLOSED" != "N/A" ]]; then
        echo "  Completion Rate: $(echo "scale=1; $ISSUES_CLOSED * 100 / ($ISSUES_OPEN + $ISSUES_CLOSED)" | bc)%"
    fi
else
    echo ""
    echo -e "${YELLOW}⚠ GitHub CLI not available for issue metrics${NC}"
    echo "  Install: https://cli.github.com/"
fi

echo ""
echo -e "${GREEN}✓ Velocity calculation complete${NC}"
