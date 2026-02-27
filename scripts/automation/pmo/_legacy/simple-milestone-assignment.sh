#!/bin/bash

################################################################################
# 🎯 Simple Milestone Assignment - Direct Approach
################################################################################

REPO="kushin77/ElevatedIQ-Mono-Repo"

echo "🎯 Fetching all issues..."
gh issue list --repo "$REPO" --state all --json number,title --limit 1000 > /tmp/all_issues.json

echo "📊 Processing issues and assigning milestones..."

jq -r '.[] | "\(.number)|\(.title)"' /tmp/all_issues.json 2>/dev/null | while IFS='|' read -r num title; do
    if [[ -z "$num" ]]; then continue; fi

    # Select milestone based on keywords
    local milestone="Project Beta: AI Intelligence"

    if echo "$title" | grep -qi "infra\|terraform\|deployment\|k8s\|scaling\|monitor\|performance\|failover"; then
        milestone="Project Gamma: Infrastructure"
    elif echo "$title" | grep -qi "secur\|auth\|encrypt\|compli\|fedramp\|audit\|cve\|threat"; then
        milestone="Project Delta: Security"
    elif echo "$title" | grep -qi "cost\|finops\|billing\|sav\|optim\|budget"; then
        milestone="Project Sigma: FinOps"
    elif echo "$title" | grep -qi "pmo\|milestone\|track\|manag"; then
        milestone="Project Omega: PMO Excellence"
    fi

    # Assign milestone
    if gh issue edit "$num" --repo "$REPO" --milestone "$milestone" 2>/dev/null; then
        echo -ne "✅"
    else
        echo -ne "❌"
    fi

    sleep 0.2
done

echo -e "\n✅ Complete!"
