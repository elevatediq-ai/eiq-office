#!/usr/bin/env bash
# Compare GCP Secret Manager secrets vs GitHub repo secrets for migration audit
# Usage: ./scripts/security/secret_audit_gsm_vs_github.sh <GCP_PROJECT> <GITHUB_REPO>
# Example: ./scripts/security/secret_audit_gsm_vs_github.sh my-project kushin77/OfficeIQ

set -euo pipefail

GCP_PROJECT=${1:-""}
GITHUB_REPO=${2:-"kushin77/OfficeIQ"}
OUTFILE=${3:-"/tmp/secret_audit.csv"}

if [[ -z "$GCP_PROJECT" ]]; then
  echo "Usage: $0 <GCP_PROJECT> [GITHUB_REPO] [OUTFILE]"
  exit 1
fi

# Ensure dependencies
command -v gcloud >/dev/null 2>&1 || { echo "gcloud required"; exit 1; }
command -v gh >/dev/null 2>&1 || { echo "gh CLI required"; exit 1; }

# List GSM secrets
echo "gcp_secret_name,gcp_secret_create_time" > "$OUTFILE"
while IFS= read -r line; do
  if [[ -n "$line" ]]; then
    name=$(echo "$line" | awk '{print $1}')
    # describe to get creationTime
    ts=$(gcloud secrets describe "$name" --project="$GCP_PROJECT" --format='value(createTime)' 2>/dev/null || echo "")
    echo "$name,$ts" >> "$OUTFILE"
  fi
done < <(gcloud secrets list --project="$GCP_PROJECT" --format='value(name)')

# Append GitHub repo secrets
echo "\n# GitHub repo secrets" >> "$OUTFILE"
echo "gh_secret_name,visibility" >> "$OUTFILE"
for s in $(gh secret list -R "$GITHUB_REPO" --limit 1000 -q ".[] | .name" 2>/dev/null || true); do
  vis=$(gh secret list -R "$GITHUB_REPO" --limit 1000 --json name,visibility -q ".[] | select(.name==\"$s\") | .visibility" 2>/dev/null || echo "")
  echo "$s,$vis" >> "$OUTFILE"
done

echo "Audit written to: $OUTFILE"
