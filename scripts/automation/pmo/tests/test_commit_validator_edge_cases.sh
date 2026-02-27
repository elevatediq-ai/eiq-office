#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
VALIDATOR="$REPO_ROOT/scripts/pmo/commit_validator.sh"

if [[ ! -x "$VALIDATOR" ]]; then
  echo "❌ commit validator is missing or not executable: $VALIDATOR"
  exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

write_msg() {
  local file="$1"
  local msg="$2"
  printf '%s\n' "$msg" > "$file"
}

expect_pass() {
  local name="$1"
  local msg="$2"
  local file="$TMP_DIR/${name}.txt"

  write_msg "$file" "$msg"
  if "$VALIDATOR" "$file" >/dev/null 2>&1; then
    echo "[PASS] $name"
  else
    echo "[FAIL] $name expected PASS"
    "$VALIDATOR" "$file" || true
    exit 1
  fi
}

expect_fail() {
  local name="$1"
  local msg="$2"
  local file="$TMP_DIR/${name}.txt"

  write_msg "$file" "$msg"
  if "$VALIDATOR" "$file" >/dev/null 2>&1; then
    echo "[FAIL] $name expected FAIL"
    exit 1
  else
    echo "[PASS] $name"
  fi
}

echo "🔍 Running commit validator edge-case harness"

expect_pass "valid_single_control" "feat(core): [NIST-SC-7] harden ingress routing Refs #5383"
expect_pass "valid_multi_control" "feat(core): [NIST-SC-8/SI-4/CA-7/AU-2] enforce policy telemetry Refs #5383"
expect_pass "valid_no_nist_tag" "docs(readme): update operations runbook Refs #5383"

expect_fail "invalid_missing_issue_ref" "feat(core): [NIST-SC-8/SI-4] enforce policy telemetry"
expect_fail "invalid_malformed_nist_segment" "feat(core): [NIST-SC-8/SI4] enforce policy telemetry Refs #5383"
expect_fail "invalid_bad_issue_token" "fix(core): resolve guard condition Refs 5383"

echo "✅ commit validator edge-case harness passed"
