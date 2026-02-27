#!/usr/bin/env bash
set -euo pipefail

# E2E test: post-push -> PR creation -> issue update (uses a fake gh CLI)
SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RTWT_SCRIPT="$SCRIPT_ROOT/real-time-work-tracking.sh"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
cd "$TMPDIR"

# Create test repo layout
mkdir -p scripts/pmo logs/pmo
cp "$RTWT_SCRIPT" scripts/pmo/
chmod +x scripts/pmo/real-time-work-tracking.sh

# Create fake gh in PATH that simulates GitHub CLI behavior
FAKE_BIN_DIR="$TMPDIR/bin"
mkdir -p "$FAKE_BIN_DIR"
cat > "$FAKE_BIN_DIR/gh" <<'GH'
#!/usr/bin/env bash
# Minimal fake gh for testing: handles 'pr create', 'issue edit', 'issue comment'
cmd="$1"
shift
case "$cmd" in
  pr)
    sub="$1"; shift
    if [ "$sub" = "create" ]; then
      # Simulate PR creation output
      echo "https://github.com/kushin77/ElevatedIQ-Mono-Repo/pull/123"
      exit 0
    fi
    ;;
  issue)
    sub="$1"; shift
    if [ "$sub" = "edit" ]; then
      # simulate edit
      exit 0
    fi
    if [ "$sub" = "comment" ]; then
      echo "commented"
      exit 0
    fi
    ;;
  *)
    # For other commands, return harmless success
    exit 0
    ;;
esac
GH
chmod +x "$FAKE_BIN_DIR/gh"
export PATH="$FAKE_BIN_DIR:$PATH"

# Init git repo and configure user
git init -q
git config user.email "test@example.org"
git config user.name "Integration Test"

# Create a branch with an issue reference
branch="feat/issue-5555"
git checkout -b "$branch"

echo "hello" > README.md
git add README.md
git commit -m "feat(test): add README Refs #5555" -q

# Install hooks (will prefer Go adapter if present, but it won't be)
scripts/pmo/real-time-work-tracking.sh install || true

# Simulate post-push (normally run by git push)
scripts/pmo/real-time-work-tracking.sh post-push origin

# Verify log for PR creation and issue update
if grep -q "PR created" logs/pmo/work-tracking.log || grep -q "Created PR" logs/pmo/work-tracking.log; then
  echo "✅ E2E: PR creation logged"
else
  echo "❌ E2E FAILED: PR creation not logged"
  sed -n '1,200p' logs/pmo/work-tracking.log || true
  exit 2
fi

if grep -q "Updated issue #5555" logs/pmo/work-tracking.log || grep -q "issue #5555" logs/pmo/work-tracking.log; then
  echo "✅ E2E: Issue updated"
  exit 0
else
  echo "❌ E2E FAILED: Issue not updated"
  sed -n '1,200p' logs/pmo/work-tracking.log || true
  exit 3
fi
