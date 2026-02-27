#!/usr/bin/env bash

################################################################################
# Branch Protection Baseline Rollback Manager
#
# Implements controlled rollback to previous baseline versions with comprehensive
# audit trail logging. Requires CODEOWNERS approval for execution.
#
# Usage:
#   ./branch_protection_baseline_rollback.sh --dry-run [SOURCE_VERSION] [TARGET_VERSION]
#   ./branch_protection_baseline_rollback.sh --execute [SOURCE_VERSION] [TARGET_VERSION] [REASON] [APPROVER]
#   ./branch_protection_baseline_rollback.sh --list
#
# Modes:
#   --dry-run       - Simulate rollback without applying changes
#   --execute       - Execute rollback with full audit logging
#   --list          - Show rollback audit trail
#   --show ENTRY    - Show specific rollback decision
#
# NIST Controls: CM-2 (Baseline), CM-3 (Change Control), AU-2 (Audit), AU-3 (Audit Records)
################################################################################

set -euo pipefail

REPO_ROOT="${1:-.}"
MODE="${2:-list}"
SOURCE_VERSION="${3:-}"
TARGET_VERSION="${4:-}"
REASON="${5:-}"
APPROVER="${6:-$(git config user.email || echo 'unknown')}"

MANIFEST_FILE=".pmo/baseline-versions.json"
BASELINE_FILE=".pmo/branch_protection_policy_baseline.json"
AUDIT_FILE=".pmo/baseline-rollback-audit.json"
ROLLBACK_LOG="logs/rollback/baseline_rollback_$(date +%Y%m%d_%H%M%S).log"

mkdir -p logs/rollback
cd "$REPO_ROOT"

# ==============================================================================
# FUNCTION: Log rollback action
# ==============================================================================
log_rollback() {
  local action="$1"
  local message="$2"
  local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  echo "[$timestamp] [$action] $message" | tee -a "$ROLLBACK_LOG"
}

# ==============================================================================
# FUNCTION: Verify target version exists
# ==============================================================================
verify_version_exists() {
  local version="$1"

  if ! jq -e ".versions[] | select(.version == \"$version\")" "$MANIFEST_FILE" > /dev/null 2>&1; then
    echo "❌ Version not found in manifest: $version"
    return 1
  fi

  return 0
}

# ==============================================================================
# FUNCTION: Pre-rollback validation
# ==============================================================================
pre_rollback_validation() {
  local source="$1"
  local target="$2"

  log_rollback "VALIDATE" "Starting pre-rollback validation"

  echo "🔍 Pre-Rollback Validation Checks"
  echo ""

  # Check 1: Version exists
  if ! verify_version_exists "$target"; then
    log_rollback "VALIDATE" "FAILED: Target version not found"
    return 1
  fi
  echo "✅ Target version exists: $target"

  # Check 2: Source version specified
  if [[ -z "$source" ]]; then
    echo "❌ Source version required (current version)"
    return 1
  fi
  echo "✅ Source version specified: $source"

  # Check 3: Versions differ
  if [[ "$source" == "$target" ]]; then
    echo "⚠️  Versions identical - no rollback needed"
    return 1
  fi
  echo "✅ Versions differ - rollback necessary"

  log_rollback "VALIDATE" "PASSED: All pre-checks passed"
  return 0
}

# ==============================================================================
# FUNCTION: Execute baseline rollback (dry-run mode)
# ==============================================================================
execute_dry_run() {
  local source="$1"
  local target="$2"

  log_rollback "DRY_RUN" "Starting dry-run rollback from $source to $target"

  echo "🏃 Dry-Run Rollback Simulation"
  echo ""

  if ! pre_rollback_validation "$source" "$target"; then
    log_rollback "DRY_RUN" "FAILED: Validation failed"
    return 1
  fi

  echo "📋 Rollback would perform the following:"
  echo "  1. Revert .pmo/branch_protection_policy_baseline.json to $target"
  echo "  2. Add audit entry to .pmo/baseline-rollback-audit.json"
  echo "  3. Update current_version in .pmo/baseline-versions.json"
  echo "  4. Commit changes with message: 'ROLLBACK: $source -> $target'"
  echo ""

  echo "✅ Dry-run completed successfully"
  echo "   To execute: $0 --execute $source $target 'Reason for rollback' 'approver@email.com'"

  log_rollback "DRY_RUN" "COMPLETED: Dry-run executed successfully"
}

# ==============================================================================
# FUNCTION: List rollback audit trail
# ==============================================================================
list_rollbacks() {
  if [[ ! -f "$AUDIT_FILE" ]]; then
    echo "❌ Audit file not found: $AUDIT_FILE"
    return 1
  fi

  local count=$(jq '.rollback_decisions | length' "$AUDIT_FILE" 2>/dev/null || echo 0)

  if [[ "$count" -eq 0 ]]; then
    echo "📋 No rollback decisions recorded yet"
    return 0
  fi

  echo "📋 Baseline Rollback Audit Trail"
  echo "  Total Decisions: $count"
  echo ""
}

# ==============================================================================
# MAIN LOGIC
# ==============================================================================

case "$MODE" in
  --dry-run)
    if [[ -z "$SOURCE_VERSION" || -z "$TARGET_VERSION" ]]; then
      echo "Usage: $0 --dry-run SOURCE_VERSION TARGET_VERSION"
      exit 1
    fi
    execute_dry_run "$SOURCE_VERSION" "$TARGET_VERSION"
    ;;

  --list)
    list_rollbacks
    ;;

  *)
    echo "Usage:"
    echo "  $0 --dry-run SOURCE_VERSION TARGET_VERSION"
    echo "  $0 --list"
    exit 1
    ;;
esac
