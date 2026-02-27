#!/bin/bash
##############################################################################
# 10X Autonomous Roadmap Projector
# Purpose: Generate live Mermaid roadmaps from GitHub Milestones & Issues
# FedRAMP: [NIST-PM-5] Project Planning & Visualization
##############################################################################

set -euo pipefail

REPO="kushin77/ElevatedIQ-Mono-Repo"

# Colors
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🗺️  ElevatedIQ: Autonomous Roadmap Projector${NC}"
echo "=========================================================="

# Fetch Milestones
milestones=$(gh api "repos/${REPO}/milestones" --jq '.[] | {number, title, open_issues, closed_issues}')

echo "### Live Project Status (Mermaid)"
echo '```mermaid'
echo 'gantt'
echo '    title ElevatedIQ Mono-Repo Roadmap'
echo '    dateFormat  YYYY-MM-DD'
echo '    section Governance'

# Iterate through milestones to build gantt
while IFS= read -r m; do
    title=$(echo "$m" | jq -r '.title')
    open=$(echo "$m" | jq -r '.open_issues')
    closed=$(echo "$m" | jq -r '.closed_issues')
    total=$((open + closed))

    if [[ "$total" -gt 0 ]]; then
        progress=$((closed * 100 / total))
        echo "    $title :active, 2026-02-15, 30d"
    fi
done < <(echo "$milestones" | jq -c '.')

echo '```'

echo -e "\n### Milestone Health Overview"
echo "$milestones" | jq -r '"- \(.title): \(.closed_issues)/\(.open_issues + .closed_issues) tasks completed"'

echo -e "\n${BLUE}💡 Use these metrics for the Executive Dashboard.${NC}"
