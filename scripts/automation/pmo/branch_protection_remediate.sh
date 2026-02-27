#!/usr/bin/env bash

set -euo pipefail

REPO="${1:-kushin77/ElevatedIQ-Mono-Repo}"
BRANCH="${2:-main}"
MODE="${3:---apply}"

REQUIRED_CONTEXTS=(
  "Workspace Health Check / commit-hygiene"
  "kms-smoke"
  "rotation-smoke"
)

echo "🛠️ Branch protection remediation"
echo "   repo:   ${REPO}"
echo "   branch: ${BRANCH}"
echo "   mode:   ${MODE}"

if ! command -v gh >/dev/null 2>&1; then
  echo "❌ GitHub CLI (gh) is required."
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "❌ jq is required."
  exit 1
fi

if [[ "$MODE" != "--apply" && "$MODE" != "--dry-run" ]]; then
  echo "❌ Invalid mode: ${MODE}. Use --apply or --dry-run."
  exit 1
fi

PROTECTION_JSON=$(gh api "repos/${REPO}/branches/${BRANCH}/protection")

CURRENT_STRICT=$(printf '%s' "$PROTECTION_JSON" | jq -r '.required_status_checks.strict // false')
CURRENT_CONTEXTS=$(printf '%s' "$PROTECTION_JSON" | jq -r '.required_status_checks.contexts[]?')

MERGED_CONTEXTS_JSON=$( {
  printf '%s\n' "$CURRENT_CONTEXTS"
  printf '%s\n' "${REQUIRED_CONTEXTS[@]}"
} | awk 'NF' | sort -u | jq -R . | jq -s . )

CURRENT_CONTEXTS_JSON=$(printf '%s' "$PROTECTION_JSON" | jq -c '[.required_status_checks.contexts[]?] // []')
UPDATED_CONTEXTS_JSON=$(printf '%s' "$MERGED_CONTEXTS_JSON" | jq -c '.')

if [[ "$CURRENT_STRICT" == "true" && "$CURRENT_CONTEXTS_JSON" == "$UPDATED_CONTEXTS_JSON" ]]; then
  echo "✅ No remediation needed. Required status checks already enforced."
  exit 0
fi

echo "⚠️ Remediation required:"
if [[ "$CURRENT_STRICT" != "true" ]]; then
  echo "   - strict required checks will be set to true"
fi

echo "   - required contexts after remediation:"
printf '%s\n' "$UPDATED_CONTEXTS_JSON" | jq -r '.[]' | sed 's/^/     - /'

PAYLOAD=$(jq -n \
  --argjson strict true \
  --argjson contexts "$UPDATED_CONTEXTS_JSON" \
  '{strict:$strict, contexts:$contexts}')

if [[ "$MODE" == "--dry-run" ]]; then
  echo "🧪 Dry-run only: no changes applied."
  echo "   Command to apply:"
  echo "   gh api -X PATCH repos/${REPO}/branches/${BRANCH}/protection/required_status_checks --input <payload.json>"
  exit 0
fi

tmp_payload=$(mktemp)
trap 'rm -f "$tmp_payload"' EXIT
printf '%s\n' "$PAYLOAD" > "$tmp_payload"

gh api -X PATCH "repos/${REPO}/branches/${BRANCH}/protection/required_status_checks" \
  --input "$tmp_payload" >/tmp/branch_protection_remediate_response.json

echo "✅ Remediation applied successfully."
echo "   Response: /tmp/branch_protection_remediate_response.json"
