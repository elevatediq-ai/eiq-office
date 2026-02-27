#!/bin/bash
# Consolidated script for Milestone #3443
REPO="kushin77/ElevatedIQ-Mono-Repo"

move_issues() {
    local from=$1
    local to=$2
    echo "Moving issues from milestone $from to $to..."
    issues=$(gh issue list --repo "$REPO" --milestone "$from" --state all --json number --jq '.[].number')
    for num in $issues; do
        echo "  Moving issue #$num..."
        gh issue edit "$num" --repo "$REPO" --milestone "$to"
    done
}

# 1. PMO (32) -> Project Omega (20)
move_issues 32 20

# 2. Security (39) -> Project Delta: Security (5)
move_issues 39 5

# 3. Infrastructure (35) -> Project Gamma: Infrastructure (4)
move_issues 35 4

echo "Consolidation complete."
