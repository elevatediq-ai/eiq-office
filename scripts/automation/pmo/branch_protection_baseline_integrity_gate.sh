#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="${1:-$(pwd)}"
BASE_SHA="${2:-}"
HEAD_SHA="${3:-}"
BASELINE_FILE=".pmo/branch_protection_policy_baseline.json"
CHANGELOG_FILE="docs/governance/BRANCH_PROTECTION_POLICY_BASELINE_CHANGELOG.md"

cd "$REPO_ROOT"

if [[ ! -f "$CHANGELOG_FILE" ]]; then
  echo "❌ Missing changelog file: $CHANGELOG_FILE"
  exit 2
fi

if ! grep -Eq '^- Signed-off-by: .+ <.+@.+>$' "$CHANGELOG_FILE"; then
  echo "❌ Changelog missing required signed entry format: '- Signed-off-by: Full Name <email@example.com>'"
  exit 2
fi

if [[ -z "$BASE_SHA" || -z "$HEAD_SHA" ]]; then
  echo "✅ Baseline integrity structural check passed (no diff window provided)."
  exit 0
fi

changed_files=$(git diff --name-only "$BASE_SHA" "$HEAD_SHA")
baseline_changed=false
changelog_changed=false

if echo "$changed_files" | grep -Fxq "$BASELINE_FILE"; then
  baseline_changed=true
fi
if echo "$changed_files" | grep -Fxq "$CHANGELOG_FILE"; then
  changelog_changed=true
fi

if [[ "$baseline_changed" != true ]]; then
  echo "✅ Baseline file unchanged in diff window; integrity gate passed."
  exit 0
fi

if [[ "$changelog_changed" != true ]]; then
  echo "❌ Baseline changed without changelog update: $CHANGELOG_FILE"
  exit 2
fi

added_signed_lines=$(git diff --unified=0 "$BASE_SHA" "$HEAD_SHA" -- "$CHANGELOG_FILE" | grep '^+' | grep -v '^+++' | grep -E '^\+\- Signed-off-by: .+ <.+@.+>$' || true)

if [[ -z "$added_signed_lines" ]]; then
  echo "❌ Changelog updated but missing added signed entry line in diff window."
  echo "   Required format in added lines: - Signed-off-by: Full Name <email@example.com>"
  exit 2
fi

echo "✅ Baseline integrity gate passed (signed changelog entry detected)."
