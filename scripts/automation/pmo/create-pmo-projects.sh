#!/bin/bash

################################################################################
# 🎯 Create GitHub Projects v2 for PMO Categories
################################################################################

set -e

OWNER="kushin77"

# Project definitions
declare -A projects=(
    ["Project Beta: AI Intelligence"]="AI, LLM, embedding, inference, models"
    ["Project Gamma: Infrastructure"]="Terraform, K8s, deployment, scaling, monitoring"
    ["Project Delta: Security"]="Auth, compliance, FEDRAMP, audit, incident response"
    ["Project Sigma: FinOps"]="Cost optimization, savings, billing, budget"
    ["Project Omega: PMO Excellence"]="Tracking, management, automation, milestones"
)

echo "🎯 Creating GitHub Projects v2..."

for title in "${!projects[@]}"; do
    description="${projects[$title]}"

    # Check if project exists
    if gh project list --owner "$OWNER" --format json | jq -r '.[] | select(.title == "'"$title"'") | .id' > /dev/null 2>&1; then
        echo "✅ Project '$title' already exists"
        continue
    fi

    # Create project
    project_id=$(gh project create --owner "$OWNER" --title "$title" --format json | jq -r '.id')

    echo "✅ Created project '$title' (ID: $project_id)"

    # Add standard fields if needed
    # For now, basic project
done

echo "🎉 All projects created!"
