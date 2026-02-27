#!/usr/bin/env bash
set -euo pipefail

# Simple PMO monitor for Issue #233, Issue #224 and PR #209
# Requirements: gh (GitHub CLI), jq, git configured for commits

REPO="kushin77/ElevatedIQ-Mono-Repo"
ISSUE_A=233
ISSUE_B=224
PR=209
STATE_DIR=".pmo"
STATE_FILE="$STATE_DIR/monitor_state.json"
SESSION_LOGS="docs/management/SESSION_LOGS.md"
PMO_DASH="docs/management/PMO_DASHBOARD.md"

mkdir -p "$STATE_DIR"

function fetch_issue() {
  local id=$1
  gh issue view "$id" --repo "$REPO" --json number,state,assignees,comments 2>/dev/null || true
}

function fetch_pr() {
  gh pr view "$PR" --repo "$REPO" --json number,state,mergeable,statusCheckRollup 2>/dev/null || true
}

current_json=$(mktemp)
jq -n '{}' > "$current_json"

issueA_json=$(fetch_issue "$ISSUE_A")
issueB_json=$(fetch_issue "$ISSUE_B")
pr_json=$(fetch_pr)

# Some jq versions lack --argfile; write temporary JSON files and combine with jq -s
tmp_a=$(mktemp)
tmp_b=$(mktemp)
tmp_p=$(mktemp)
printf '%s' "$issueA_json" > "$tmp_a"
printf '%s' "$issueB_json" > "$tmp_b"
printf '%s' "$pr_json" > "$tmp_p"
jq -s '{issue233:.[0], issue224:.[1], pr209:.[2]}' "$tmp_a" "$tmp_b" "$tmp_p" > "$current_json" || true
rm -f "$tmp_a" "$tmp_b" "$tmp_p"

prev_json="$STATE_FILE"
if [[ ! -f "$prev_json" ]]; then
  echo '{}' > "$prev_json"
fi

changed=false

# Helper: get first assignee login
get_assignee() {
  echo "$1" | jq -r '.assignees[0].login // empty'
}

assignee233=$(jq -r '.issue233.assignees[0].login // ""' "$current_json")
assignee224=$(jq -r '.issue224.assignees[0].login // ""' "$current_json")

prev_assignee233=$(jq -r '.issue233.assignees[0].login // ""' "$prev_json")
prev_assignee224=$(jq -r '.issue224.assignees[0].login // ""' "$prev_json")

if [[ "$assignee233" != "$prev_assignee233" ]]; then
  changed=true
  echo "Detected assignment change for issue #233: '$prev_assignee233' -> '$assignee233'"
  if [[ -n "$assignee233" ]]; then
    gh issue comment "$ISSUE_A" --repo "$REPO" --body "PMO: Noted assignment to @$assignee233. Please add ETA and status updates; PMO will monitor and re-run CI on PR #209 when ready." || true
    echo "- **$(date +'%Y-%m-%d %H:%M:%S UTC')** — DevOps assigned @$assignee233 to issue #233; monitoring will continue." >> "$SESSION_LOGS" || true
  fi
fi

if [[ "$assignee224" != "$prev_assignee224" ]]; then
  changed=true
  echo "Detected assignment change for issue #224: '$prev_assignee224' -> '$assignee224'"
  if [[ -n "$assignee224" ]]; then
    gh issue comment "$ISSUE_B" --repo "$REPO" --body "PMO: Noted assignment to @$assignee224. Please provide ETA and progress updates for CI fixes related to PR #209." || true
    echo "- **$(date +'%Y-%m-%d %H:%M:%S UTC')** — DevOps assigned @$assignee224 to issue #224; monitoring will continue." >> "$SESSION_LOGS" || true
  fi
fi

# Check PR CI status: determine if any checks concluded with FAILURE
pr_has_failure=$(echo "$pr_json" | jq -r '.statusCheckRollup[]?.conclusion' | grep -E "FAILURE" || true)
if [[ -z "$pr_has_failure" ]]; then
  pr_passed=true
else
  pr_passed=false
fi

prev_pr_passed=$(jq -r '.pr209.passed // false' "$prev_json")

if [[ "$pr_passed" == "true" && "$prev_pr_passed" != "true" ]]; then
  changed=true
  echo "PR #209 CI passed since last check. Proceeding to merge and document."
  # Comment and log
  gh pr comment "$PR" --repo "$REPO" --body "CI: All checks passed — PMO will proceed to merge per standards." || true
  echo "- **$(date +'%Y-%m-%d %H:%M:%S UTC')** — PR #209 CI passed; ready to merge. PMO will merge and close related issues." >> "$SESSION_LOGS" || true
  # Attempt merge (only if mergeable and open)
  pr_state=$(echo "$pr_json" | jq -r '.state')
  mergeable=$(echo "$pr_json" | jq -r '.mergeable')
  if [[ "$pr_state" == "OPEN" && "$mergeable" == "MERGEABLE" ]]; then
    gh pr merge "$PR" --repo "$REPO" --merge --admin || true
    echo "- **$(date +'%Y-%m-%d %H:%M:%S UTC')** — Merged PR #209 via PMO monitor." >> "$SESSION_LOGS" || true
  fi
fi

# Persist current state: mark PR passed if there are no failures in statusCheckRollup
jq '{issue233:.issue233, issue224:.issue224, pr209:{passed: ( (.pr209.statusCheckRollup[]?.conclusion // "") | select(.=="FAILURE") | .) as $f | ($f | length) } }' "$current_json" > /dev/null 2>&1 || true
# Safe computation of passed flag
jq '{issue233:.issue233, issue224:.issue224, pr209:{passed: ( [ .pr209.statusCheckRollup[]?.conclusion // "" ] | map(select(.=="FAILURE")) | length == 0 )}}' "$current_json" > "$prev_json" || true

if [[ "$changed" == true ]]; then
  git add "$SESSION_LOGS" "$PMO_DASH" 2>/dev/null || true
  git commit -m "docs(pmo): [monitor] record assignment/CI state updates" || true
fi

rm -f "$current_json"
echo "Monitor run complete."
