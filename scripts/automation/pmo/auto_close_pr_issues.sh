#!/usr/bin/env bash
# Auto-close GitHub issues when their corresponding PRs are merged.
# Usage: scripts/pmo/auto_close_pr_issues.sh

set -euo pipefail

REPO_OWNER="kushin77"
REPO="ElevatedIQ-Mono-Repo"

# Map PR -> issue
declare -A MAP
MAP[650]=647
MAP[652]=648
MAP[653]=649

for pr in "${!MAP[@]}"; do
  issue=${MAP[$pr]}
  echo "Checking PR #$pr -> Issue #$issue..."
  merged=$(gh pr view "$pr" --repo "$REPO_OWNER/$REPO" --json merged --jq '.merged') || merged=false
  if [ "$merged" = "true" ]; then
    echo "PR #$pr is merged. Ensuring issue #$issue is closed..."
    # Check issue state
    state=$(gh issue view "$issue" --repo "$REPO_OWNER/$REPO" --json state --jq '.state') || state="closed"
    if [ "$state" != "closed" ]; then
      gh issue comment "$issue" --repo "$REPO_OWNER/$REPO" --body "Closing issue after PR #$pr merged (automated by PMO script)."
      gh issue close "$issue" --repo "$REPO_OWNER/$REPO" --reason completed
      echo "Closed issue #$issue"
    else
      echo "Issue #$issue already closed."
    fi
  else
    echo "PR #$pr not merged yet (merged=${merged}). Skipping."
  fi
done

echo "Done."
