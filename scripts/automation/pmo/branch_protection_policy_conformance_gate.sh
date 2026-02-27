#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="${1:-$(pwd)}"
WORKFLOW_DIR="${REPO_ROOT}/.github/workflows"
BASELINE_FILE="${REPO_ROOT}/.pmo/branch_protection_policy_baseline.json"

if [[ ! -d "$WORKFLOW_DIR" ]]; then
  echo "❌ Workflow directory not found: $WORKFLOW_DIR"
  exit 1
fi

if [[ ! -f "$BASELINE_FILE" ]]; then
  echo "❌ Baseline file not found: $BASELINE_FILE"
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "❌ jq is required."
  exit 1
fi

if ! jq -e '.workflows | type == "array" and length > 0' "$BASELINE_FILE" >/dev/null; then
  echo "❌ Invalid baseline format: .workflows must be a non-empty array"
  exit 1
fi

FAILURES=0

echo "🛡️ Branch protection policy conformance gate"
echo "   workflow_dir: $WORKFLOW_DIR"
echo "   baseline: $BASELINE_FILE"

require_workflow_dispatch=$(jq -r '.requiredWorkflowDispatch // true' "$BASELINE_FILE")

while IFS='|' read -r file expected_cron; do
  path="$WORKFLOW_DIR/$file"

  if [[ ! -f "$path" ]]; then
    echo "❌ Missing required workflow: $file"
    FAILURES=$((FAILURES + 1))
    continue
  fi

  if ! grep -Eq '^on:' "$path"; then
    echo "❌ Missing 'on' trigger block in $file"
    FAILURES=$((FAILURES + 1))
  fi

  if [[ "$require_workflow_dispatch" == "true" ]]; then
    if ! grep -Eq 'workflow_dispatch:' "$path"; then
      echo "❌ Missing workflow_dispatch trigger in $file"
      FAILURES=$((FAILURES + 1))
    fi
  fi

  if ! grep -Eq 'schedule:' "$path"; then
    echo "❌ Missing schedule trigger in $file"
    FAILURES=$((FAILURES + 1))
  fi

  if ! grep -Fq "cron: '${expected_cron}'" "$path"; then
    echo "❌ Cron baseline mismatch in $file"
    echo "   expected: ${expected_cron}"
    echo "   actual(s):"
    grep -E "cron:" "$path" | sed 's/^/     /' || true
    FAILURES=$((FAILURES + 1))
  else
    echo "✅ $file cron baseline enforced (${expected_cron})"
  fi
done < <(jq -r '.workflows[] | "\(.file)|\(.cron)"' "$BASELINE_FILE")

if [[ "$FAILURES" -gt 0 ]]; then
  echo "❌ Policy conformance gate failed with ${FAILURES} issue(s)."
  exit 2
fi

echo "✅ Policy conformance gate passed."
