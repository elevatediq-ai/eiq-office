#!/bin/bash
# ElevatedIQ Failure Escalation Script
# Purpose: Automatically create GitHub issues for critical failures.
# Usage: ./escalate_failure.sh "Issue Title" "Issue Body" "label1,label2"

TITLE="$1"
BODY="$2"
LABELS="${3:-bug,automated-report}"

if [ -z "$TITLE" ]; then
  echo "Usage: $0 \"Title\" \"Body\" [labels]"
  exit 1
fi

echo "🔍 Checking for existing issue with title: '$TITLE'..."
EXISTING_ISSUE=$(gh issue list --search "$TITLE in:title state:open" --json number --jq '.[0].number')

if [ -n "$EXISTING_ISSUE" ]; then
  echo "⚠️  Issue already exists: #$EXISTING_ISSUE. Adding comment..."
  gh issue comment "$EXISTING_ISSUE" --body "⚠️ **Recurrence Detected**\n\n$BODY"
else
  echo "🚨 Creating new issue..."
  NEW_ISSUE=$(gh issue create --title "$TITLE" --body "$BODY" --label "$LABELS" --assignee "@me")
  echo "✅ Issue Created: $NEW_ISSUE"

  # Trigger smart assignee enforcement if available
  if [ -x "./scripts/pmo/assignee_enforcer.sh" ]; then
      ./scripts/pmo/assignee_enforcer.sh
  fi
fi
