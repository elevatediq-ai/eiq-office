#!/usr/bin/env bash
set -euo pipefail
# Auto-close per-run CI issues when their associated run has a successful rerun.
# Usage: scripts/pmo/auto-close-run-issues.sh [owner/repo] [start_issue] [end_issue]

REPO=${1:-}
START=${2:-468}
END=${3:-517}

if [ -z "$REPO" ]; then
  REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null || true)
  if [ -z "$REPO" ]; then
    echo "Repository not provided and could not be detected. Provide owner/repo as first arg." >&2
    exit 2
  fi
fi

echo "Using repo: $REPO"

# Collect successful run ids on main
echo "Fetching successful runs on branch main..."
successes=$(gh run list --repo "$REPO" --branch main --limit 300 --json databaseId,conclusion --jq '.[] | select(.conclusion=="success") | .databaseId' 2>/dev/null || true)

if [ -z "$successes" ]; then
  echo "No successful runs found. Exiting."
  exit 0
fi

echo "Found successful run IDs:"
printf "%s\n" "$successes"

for issue in $(seq "$START" "$END"); do
  echo "Checking issue #$issue..."
  json=$(gh issue view "$issue" --repo "$REPO" --json title,body 2>/dev/null || true)
  if [ -z "$json" ]; then
    echo "  Issue #$issue not found or gh not authenticated; skipping."
    continue
  fi
  runid=$(printf "%s\n" "$json" | grep -oE 'run [0-9]+' | head -n1 | awk '{print $2}' || true)
  if [ -z "$runid" ]; then
    echo "  No run id found in issue #$issue; skipping."
    continue
  fi
  if printf "%s\n" "$successes" | grep -xq "$runid"; then
    echo "  Run $runid succeeded — commenting and closing issue #$issue"
    gh issue comment "$issue" --repo "$REPO" --body "Automated PMO update: rerun for run $runid succeeded after remediation (PR #535). Closing per PMO guidance." >/dev/null 2>&1 || true
    gh issue close "$issue" --repo "$REPO" >/dev/null 2>&1 || true
    echo "  Closed #$issue"
  else
    echo "  Run $runid not in successful runs list; leaving open."
  fi
done

echo "Done."
