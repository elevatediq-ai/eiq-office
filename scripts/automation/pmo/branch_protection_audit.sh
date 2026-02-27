#!/usr/bin/env bash

set -euo pipefail

REPO="${1:-kushin77/ElevatedIQ-Mono-Repo}"
BRANCH="${2:-main}"
REQUIRED_CONTEXTS=(
  "Workspace Health Check / commit-hygiene"
  "kms-smoke"
  "rotation-smoke"
)

echo "🔍 Branch protection audit"
echo "   repo:   ${REPO}"
echo "   branch: ${BRANCH}"

if ! command -v gh >/dev/null 2>&1; then
  echo "❌ GitHub CLI (gh) is required."
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "❌ jq is required."
  exit 1
fi

PROTECTION_JSON=$(gh api "repos/${REPO}/branches/${BRANCH}/protection")

STRICT=$(printf '%s' "$PROTECTION_JSON" | jq -r '.required_status_checks.strict // false')
STATUS_CONTEXTS=$(printf '%s' "$PROTECTION_JSON" | jq -r '.required_status_checks.contexts[]?')
CODEOWNERS_REQUIRED=$(printf '%s' "$PROTECTION_JSON" | jq -r '.required_pull_request_reviews.require_code_owner_reviews // false')
PR_REVIEW_COUNT=$(printf '%s' "$PROTECTION_JSON" | jq -r '.required_pull_request_reviews.required_approving_review_count // 0')
ENFORCE_ADMINS=$(printf '%s' "$PROTECTION_JSON" | jq -r '.enforce_admins.enabled // false')

MISSING_CONTEXTS=()
for required_context in "${REQUIRED_CONTEXTS[@]}"; do
  if ! printf '%s\n' "$STATUS_CONTEXTS" | grep -Fxq "$required_context"; then
    MISSING_CONTEXTS+=("$required_context")
  fi
done

echo "   strict_status_checks: ${STRICT}"
echo "   code_owner_reviews:   ${CODEOWNERS_REQUIRED}"
echo "   required_approvals:   ${PR_REVIEW_COUNT}"
echo "   enforce_admins:       ${ENFORCE_ADMINS}"
echo "   required_contexts:"
for required_context in "${REQUIRED_CONTEXTS[@]}"; do
  if printf '%s\n' "$STATUS_CONTEXTS" | grep -Fxq "$required_context"; then
    echo "     ✅ ${required_context}"
  else
    echo "     ❌ ${required_context}"
  fi
done

if [[ "$CODEOWNERS_REQUIRED" != "true" || "$STRICT" != "true" || ${#MISSING_CONTEXTS[@]} -gt 0 ]]; then
  echo "❌ Governance gap detected on ${REPO}:${BRANCH}."
  if [[ "$CODEOWNERS_REQUIRED" != "true" ]]; then
    echo "   - Code-owner review enforcement is not enabled."
  fi
  if [[ "$STRICT" != "true" ]]; then
    echo "   - Strict required status checks is not enabled."
  fi
  if [[ ${#MISSING_CONTEXTS[@]} -gt 0 ]]; then
    echo "   - Missing required status-check context(s): ${MISSING_CONTEXTS[*]}"
  fi
  echo "   Remediation (requires admin):"
  echo "   gh api -X PATCH repos/${REPO}/branches/${BRANCH}/protection \\
    -H 'Accept: application/vnd.github+json' \\
    -f required_status_checks.strict=true \\
    -F required_status_checks.contexts[]='Workspace Health Check / commit-hygiene' \\
    -F required_status_checks.contexts[]='kms-smoke' \\
    -F required_status_checks.contexts[]='rotation-smoke' \\
    -f enforce_admins=true \\
    -f required_pull_request_reviews.dismiss_stale_reviews=true \\
    -f required_pull_request_reviews.require_code_owner_reviews=true \\
    -f required_pull_request_reviews.required_approving_review_count=1"
  exit 2
fi

echo "✅ Branch protection audit passed: governance-required status checks are enforced."
exit 0
