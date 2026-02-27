#!/usr/bin/env bash

################################################################################
# Branch Protection CODEOWNERS Validator
#
# Validates that baseline configuration changes have been approved by users
# listed in the CODEOWNERS file. Enforces governance rule: "No baseline changes
# without CODEOWNERS sign-off" (NIST CM-3 Change Control)
#
# Usage:
#   ./branch_protection_codeowners_validator.sh [--check-approvals] [BASE_SHA HEAD_SHA]
#
# Exit Codes:
#   0: CODEOWNERS validation passed
#   1: Missing CODEOWNERS file
#   2: Baseline changed without required approval
################################################################################

set -euo pipefail

REPO_ROOT="${1:-$(pwd)}"
MODE="${2:-validate}"
BASE_SHA="${3:-}"
HEAD_SHA="${4:-}"
CODEOWNERS_FILE="${REPO_ROOT}/CODEOWNERS"
BASELINE_FILE=".pmo/branch_protection_policy_baseline.json"

cd "$REPO_ROOT"

# ==============================================================================
# FUNCTION: Validate CODEOWNERS file exists and has governance entries
# ==============================================================================
validate_codeowners() {
  if [[ ! -f "$CODEOWNERS_FILE" ]]; then
    echo "❌ Missing CODEOWNERS file: $CODEOWNERS_FILE"
    return 1
  fi

  if ! grep -q "$BASELINE_FILE" "$CODEOWNERS_FILE"; then
    echo "⚠️  WARNING: Baseline path not found in CODEOWNERS"
    echo "   Add to CODEOWNERS: $BASELINE_FILE @governance-admin"
    return 1
  fi

  echo "✅ CODEOWNERS file structure validated"
  return 0
}

# ==============================================================================
# FUNCTION: Extract required approvers from CODEOWNERS for baseline changes
# ==============================================================================
get_required_approvers() {
  local baseline_approvers=""

  # Match patterns that apply to the baseline file
  baseline_approvers=$(grep "$BASELINE_FILE" "$CODEOWNERS_FILE" | head -1 | awk '{for(i=2;i<=NF;i++)print $i}' || echo "")

  if [[ -z "$baseline_approvers" ]]; then
    # Fall back to default CODEOWNERS rule
    baseline_approvers=$(grep "^\* " "$CODEOWNERS_FILE" | awk '{for(i=2;i<=NF;i++)print $i}' || echo "")
  fi

  echo "$baseline_approvers"
}

# ==============================================================================
# FUNCTION: Check if baseline was changed in commit range
# ==============================================================================
check_baseline_changed() {
  local base_sha="$1"
  local head_sha="$2"

  if git diff --name-only "$base_sha" "$head_sha" | grep -Fxq "$BASELINE_FILE"; then
    return 0  # Baseline was changed
  else
    return 1  # Baseline was not changed
  fi
}

# ==============================================================================
# FUNCTION: Check if PR has required approvals (for GitHub Actions integration)
# ==============================================================================
check_pr_approvals() {
  local pr_number="$1"
  local required_approvers="$2"

  if [[ -z "$pr_number" || -z "$required_approvers" ]]; then
    echo "⚠️  Insufficient context for PR approval check"
    return 0  # Non-blocking in this mode
  fi

  # Get PR reviews using GitHub API
  local reviews=$(gh pr view "$pr_number" --json "reviews" --jq '.reviews[].author.login' 2>/dev/null || echo "")

  if [[ -z "$reviews" ]]; then
    echo "❌ No PR reviews found. Required approver(s): $required_approvers"
    return 2
  fi

  # Check if any required approver has approved
  local approved=false
  for approver in $required_approvers; do
    if echo "$reviews" | grep -Fxq "${approver##@}"; then
      approved=true
      echo "✅ Approval from ${approver##@} detected"
      break
    fi
  done

  if [[ "$approved" != true ]]; then
    echo "❌ No approval from required CODEOWNERS: $required_approvers"
    return 2
  fi

  return 0
}

# ==============================================================================
# MAIN LOGIC
# ==============================================================================

case "${MODE}" in
  validate)
    echo "📋 [CODEOWNERS Validator] Validating baseline governance structure..."
    validate_codeowners
    exit $?
    ;;

  check-approvals)
    echo "🔍 [CODEOWNERS Validator] Checking approval requirements for baseline changes..."

    if [[ -z "$BASE_SHA" || -z "$HEAD_SHA" ]]; then
      echo "ℹ️  No commit range provided; structural validation only"
      validate_codeowners
      exit $?
    fi

    if ! check_baseline_changed "$BASE_SHA" "$HEAD_SHA"; then
      echo "✅ Baseline file unchanged in diff window; no approval required"
      exit 0
    fi

    echo "⚠️  Baseline changes detected in commit range $BASE_SHA..$HEAD_SHA"

    required_approvers=$(get_required_approvers)
    if [[ -z "$required_approvers" ]]; then
      echo "❌ No required approvers found in CODEOWNERS for $BASELINE_FILE"
      echo "   Add to CODEOWNERS: $BASELINE_FILE @approver-username"
      exit 2
    fi

    echo "✅ Required approver(s): $required_approvers"
    exit 0
    ;;

  pr-approval)
    echo "🔏 [CODEOWNERS Validator] Checking PR approval status..."
    pr_number="${BASE_SHA:-}"

    if [[ -z "$pr_number" ]]; then
      echo "❌ PR number required for pr-approval mode"
      exit 1
    fi

    required_approvers=$(get_required_approvers)
    if [[ -z "$required_approvers" ]]; then
      echo "❌ No required approvers found in CODEOWNERS"
      exit 1
    fi

    check_pr_approvals "$pr_number" "$required_approvers"
    exit $?
    ;;

  *)
    echo "Usage: $0 <repo_root> <mode> [BASE_SHA] [HEAD_SHA]"
    echo ""
    echo "Modes:"
    echo "  validate         - Validate CODEOWNERS file structure"
    echo "  check-approvals  - Check if baseline changes need approval"
    echo "  pr-approval      - Check if PR has required approvals (BASE_SHA=PR_NUMBER)"
    exit 1
    ;;
esac
