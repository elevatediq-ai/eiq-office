#!/usr/bin/env bash
set -euo pipefail

# Simple smoke test for milestone_enforcer.sh (dry-run)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

export DRY_RUN=true
OUTPUT=$(./milestone_enforcer.sh --open 2>&1 || true)

if ! echo "$OUTPUT" | grep -q "DRY RUN"; then
  echo "[FAIL] milestone_enforcer did not run in dry-run as expected" >&2
  echo "$OUTPUT" >&2
  exit 1
fi

echo "[PASS] milestone_enforcer dry-run smoke test OK"
