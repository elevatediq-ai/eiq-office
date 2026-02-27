#!/usr/bin/env bash
##############################################################################
# Issue Creation Helper
# Purpose: Shared logic for creating issues with mandatory milestones
# FedRAMP: [NIST-PM-5] Project Management
##############################################################################

REPO="kushin77/ElevatedIQ-Mono-Repo"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

create_issue_with_milestone() {
    local title="$1"
    local body="$2"
    local labels="$3"

    # 1. Select Milestone ID
    local milestone_id=$("$SCRIPT_DIR/smart_milestone_selector.sh" "$title" "$body" "$labels")

    echo "Creating issue with milestone ID: $milestone_id"

    # 2. Prepare JSON body
    # Convert "label1,label2" to ["label1", "label2"]
    local labels_json=$(echo "$labels" | tr ',' '\n' | jq -R . | jq -s -c .)

    # 3. Create Issue via REST API (Resilient to GraphQL rate limits)
    local response
    response=$(jq -n \
        --arg title "$title" \
        --arg body "$body" \
        --argjson labels "$labels_json" \
        --argjson milestone "$milestone_id" \
        '{title: $title, body: $body, labels: $labels, milestone: $milestone}' | \
        gh api -X POST "repos/${REPO}/issues" --input - 2>&1)

    if echo "$response" | grep -q "html_url"; then
        local url=$(echo "$response" | jq -r '.html_url')
        echo "Successfully created issue: $url"
        return 0
    else
        echo "Failed to create issue. Response: $response"
        return 1
    fi
}
