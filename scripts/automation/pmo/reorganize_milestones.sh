#!/bin/bash
set -euo pipefail

# ElevatedIQ Canonical Milestone Migration Agent
# Purpose: Consolidate ad-hoc milestones into a canonical set of <20.
# Author: GitHub Copilot (Gemini 3 Flash)

REPO="kushin77/ElevatedIQ-Mono-Repo"
CANONICAL_MILESTONES=(
  "Documentation"
  "Security"
  "CI/CD"
  "Infrastructure"
  "Monitoring"
  "Portal"
  "OpenStack"
  "AWS"
  "GCP"
  "Azure"
  "AI-ML"
  "Edge-Inference"
  "FedRAMP"
  "Database"
  "Observability"
  "Testing"
  "Governance"
  "Maintenance"
)

echo "🚀 Starting Milestone Migration for $REPO..."

# 1. Ensure canonical milestones exist and map titles to numbers
declare -A M_NUM
echo "Checking existing milestones (including closed)..."
# Important: Fetch ALL milestones (open and closed) to avoid creating duplicates
EXISTING_JSON=$(gh api --paginate "repos/${REPO}/milestones?state=all")

for title in "${CANONICAL_MILESTONES[@]}"; do
  num=$(echo "$EXISTING_JSON" | jq -r ".[] | select(.title == \"$title\") | .number" | head -n 1)
  if [[ -z "$num" ]]; then
    echo "Creating milestone: $title"
    num=$(gh api "repos/${REPO}/milestones" -f title="$title" -q '.number')
  else
    echo "Found existing milestone $title -> #$num"
    # Ensure it is open
    gh api -X PATCH "repos/${REPO}/milestones/$num" -f state=open > /dev/null
  fi
  M_NUM["$title"]=$num
done

# 2. Map Keywords Logic
map_keyword() {
  local text="$1"
  if echo "$text" | grep -qiE "doc|README|PHASE_.*_SUMMARY|documentation"; then echo "Documentation"
  elif echo "$text" | grep -qiE "security|vuln|nist|cve|audit|encrypt|secret|barbican|auth|identity"; then echo "Security"
  elif echo "$text" | grep -qiE "ci|cd|workflow|gh-action|pipeline|github-action|automation"; then echo "CI/CD"
  elif echo "$text" | grep -qiE "infra|terra|iac|provision|host|cluster|systemd"; then echo "Infrastructure"
  elif echo "$text" | grep -qiE "monitor|alert|grafana|prometheus|dash|log|observ|health|telemetry"; then echo "Monitoring"
  elif echo "$text" | grep -qiE "portal|frontend|ui|web|apps/portal|react|dashboard"; then echo "Portal"
  elif echo "$text" | grep -qiE "openstack|nova|keystone|glance|neutron|cinder|heat"; then echo "OpenStack"
  elif echo "$text" | grep -qiE "aws|s3|ec2|rds|lambda|lambda_ws3_ws4"; then echo "AWS"
  elif echo "$text" | grep -qiE "gcp|google|bigquery|cloudbuild|gsm_auth"; then echo "GCP"
  elif echo "$text" | grep -qiE "azure|blob|aks"; then echo "Azure"
  elif echo "$text" | grep -qiE "ai|ml|llama|ollama|inference|gpu|rag|embedding|agent-framework|phase9"; then echo "AI-ML"
  elif echo "$text" | grep -qiE "edge|federated|iot|latency"; then echo "Edge-Inference"
  elif echo "$text" | grep -qiE "fedramp|compliance|nist-800-53|nist-sc-7|ac-2|au-2"; then echo "FedRAMP"
  elif echo "$text" | grep -qiE "db|database|sql|postgres|sqlite|redis|chroma|citus"; then echo "Database"
  elif echo "$text" | grep -qiE "observ|otel|trace|metric"; then echo "Observability"
  elif echo "$text" | grep -qiE "test|pytest|bench|unit|smoke|chaos"; then echo "Testing"
  elif echo "$text" | grep -qiE "gov|policy|license|codeowners|pmo"; then echo "Governance"
  else echo "Maintenance"; fi
}

# 3. Fetch all issues (Open and Closed)
echo "Fetching all repository issues... This may take a moment."
# Flatten pages into one array
gh api --paginate "repos/${REPO}/issues?state=all&per_page=100" | jq -s 'add' > /tmp/eiq_all_issues.json

# 4. Process remapping
echo "Processing $(jq '. | length' /tmp/eiq_all_issues.json) issues..."
jq -c '.[] | {number: .number, title: .title, body: (.body // ""), labels: [.labels[].name]}' /tmp/eiq_all_issues.json | while read -r issue; do
  num=$(echo "$issue" | jq -r '.number')
  title=$(echo "$issue" | jq -r '.title')
  body=$(echo "$issue" | jq -r '.body')
  labels=$(echo "$issue" | jq -r '.labels | join(" ")')

  combined="$title $body $labels"
  target=$(map_keyword "$combined")

  if [[ -v M_NUM["$target"] ]]; then
    milestone_num=${M_NUM["$target"]}
    # echo "Mapping Issue #$num -> $target (#$milestone_num)"
    gh api -X PATCH "repos/${REPO}/issues/${num}" -f milestone=$milestone_num > /dev/null
  else
    echo "⚠️ Warning: No milestone ID for $target (Issue #$num)"
  fi
done

# 5. Cleanup: Delete non-canonical milestones
echo "Cleaning up non-canonical milestones..."
ALL_MILESTONES=$(gh api --paginate "repos/${REPO}/milestones?state=all")
echo "$ALL_MILESTONES" | jq -r '.[] | "\(.title)|\(.number)"' | while IFS="|" read -r m_title m_num; do
  is_canonical=false
  for c in "${CANONICAL_MILESTONES[@]}"; do
    if [[ "$c" == "$m_title" ]]; then is_canonical=true; break; fi
  done

  if [ "$is_canonical" = false ]; then
    echo "Deleting legacy milestone: $m_title (#$m_num)"
    gh api -X DELETE "repos/${REPO}/milestones/${m_num}"
  fi
done

echo "✅ Milestone migration complete!"
