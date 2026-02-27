#!/bin/bash

################################################################################
# 🎯 Elite Milestone Assignment - Direct JSON Processing
################################################################################

set -e

REPO="kushin77/ElevatedIQ-Mono-Repo"

echo -e "\n🎯 Fetching all issues..."
gh issue list --repo "$REPO" --state all --json number,title --limit 1000 > /tmp/all_issues.json 2>&1

total=$(jq 'length' /tmp/all_issues.json)
echo -e "📊 Processing $total issues...\n"

successful=0
failed=0

# Process each issue
for i in $(seq 0 $((total - 1))); do
    num=$(jq -r ".[$i].number" /tmp/all_issues.json)
    title=$(jq -r ".[$i].title" /tmp/all_issues.json)

    if [[ -z "$num" ]] || [[ "$num" == "null" ]]; then
        continue
    fi

    # Determine milestone
    milestone="Project Beta: AI Intelligence"

    if echo "$title" | grep -qi "infra\|terraform\|deployment\|k8s\|scaling\|monitor\|performance\|failover\|resilience"; then
        milestone="Project Gamma: Infrastructure"
    elif echo "$title" | grep -qi "secur\|auth\|encrypt\|compli\|fedramp\|audit\|cve\|threat\|incident"; then
        milestone="Project Delta: Security"
    elif echo "$title" | grep -qi "cost\|finops\|billing\|sav\|optim\|budget"; then
        milestone="Project Sigma: FinOps"
    elif echo "$title" | grep -qi "pmo\|milestone\|track\|manag"; then
        milestone="Project Omega: PMO Excellence"
    fi

    # Assign
    if gh issue edit "$num" --repo "$REPO" --milestone "$milestone" 2>/dev/null; then
        echo -n "✅"
        ((successful++))
    else
        echo -n "❌"
        ((failed++))
    fi

    # Rate limit
    sleep 0.15

    # Progress indicator
    if (( (successful + failed) % 20 == 0 )); then
        echo " [$((successful + failed))/$total]"
    fi
done

echo -e "\n\n✅ COMPLETE!"
echo "Successful: $successful"
echo "Failed: $failed"
