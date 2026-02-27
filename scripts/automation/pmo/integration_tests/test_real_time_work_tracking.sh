#!/usr/bin/env bash
set -euo pipefail

# Integration test for scripts/pmo/real-time-work-tracking.sh
# - verifies install + post-commit hook writes to the local log

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RTWT_SCRIPT="$SCRIPT_ROOT/real-time-work-tracking.sh"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
cd "$TMPDIR"

# Create test repo layout
mkdir -p scripts/pmo logs/pmo
cp "$RTWT_SCRIPT" scripts/pmo/
chmod +x scripts/pmo/real-time-work-tracking.sh

git init -q
git config user.email "test@example.org"
git config user.name "Integration Test"

# Run install (should create hooks)
scripts/pmo/real-time-work-tracking.sh install || true

# Make a commit with an issue reference
echo "test" > README.md
git add README.md
git commit -m "feat(test): add README Refs #2794" -q

# Run the post-commit hook handler
scripts/pmo/real-time-work-tracking.sh post-commit

# Assert the log contains the commit hook entry
if grep -q "Commit hook: issue" logs/pmo/work-tracking.log; then
  echo "✅ Integration test passed: post-commit updated local log"
  exit 0
else
  echo "❌ Integration test FAILED: log entry not found"
  echo "---- log contents ----"
  sed -n '1,200p' logs/pmo/work-tracking.log || true
  exit 2
fi
