#!/bin/bash

################################################################################
# 🎯 Auto-Assign Issues to GitHub Projects v2
################################################################################

set -e

REPO="kushin77/ElevatedIQ-Mono-Repo"
OWNER="kushin77"

# Get project IDs
declare -A project_ids

echo "🎯 Fetching project IDs..."
while IFS= read -r line; do
    title=$(echo "$line" | jq -r '.title')
    id=$(echo "$line" | jq -r '.id')
    project_ids["$title"]="$id"
done < <(gh project list --owner "$OWNER" --format json | jq -c '.[]')

echo "📊 Found projects:"
for title in "${!project_ids[@]}"; do
    echo "  $title: ${project_ids[$title]}"
done

echo -e "\n🎯 Fetching all issues..."
gh issue list --repo "$REPO" --state all --json number,title,url --limit 1000 > /tmp/all_issues.json 2>&1

total=$(jq 'length' /tmp/all_issues.json)
echo -e "📊 Processing $total issues...\n"

successful=0
failed=0

# Process each issue
for i in $(seq 0 $((total - 1))); do
    num=$(jq -r ".[$i].number" /tmp/all_issues.json)
    title=$(jq -r ".[$i].title" /tmp/all_issues.json)
    url=$(jq -r ".[$i].url" /tmp/all_issues.json)

    if [[ -z "$num" ]] || [[ "$num" == "null" ]]; then
        continue
    fi

    # Determine project
    project_title="Project Beta: AI Intelligence"

    if echo "$title" | grep -qi "infra\|terraform\|deployment\|k8s\|scaling\|monitor\|performance\|failover\|resilience"; then
        project_title="Project Gamma: Infrastructure"
    elif echo "$title" | grep -qi "secur\|auth\|encrypt\|compli\|fedramp\|audit\|cve\|threat\|incident"; then
        project_title="Project Delta: Security"
    elif echo "$title" | grep -qi "cost\|finops\|billing\|sav\|optim\|budget"; then
        project_title="Project Sigma: FinOps"
    elif echo "$title" | grep -qi "pmo\|milestone\|track\|manag"; then
        project_title="Project Omega: PMO Excellence"
    fi

    project_id="${project_ids[$project_title]}"

    if [[ -z "$project_id" ]]; then
        echo "❌ Project '$project_title' not found"
        ((failed++))
        continue
    fi

    # Assign to project
    if gh project item-add "$project_id" --url "$url" 2>/dev/null; then
        echo -n "✅"
        ((successful++))
    else
        echo -n "❌"
        ((failed++))
    fi

    # Rate limit
    sleep 0.5

    # Progress
    if (( (successful + failed) % 20 == 0 )); then
        echo " [$((successful + failed))/$total]"
    fi
done

echo -e "\n\n✅ COMPLETE!"
echo "Successful: $successful"
echo "Failed: $failed"
