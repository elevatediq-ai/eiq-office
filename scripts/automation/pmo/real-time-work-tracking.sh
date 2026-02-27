#!/bin/bash

# 🚀 ElevatedIQ: Enhancement 2 - Real-Time Work Tracking
# Updates GitHub issues automatically on git actions (commits, pushes, etc.)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../" && pwd)"

LOG_FILE="$REPO_ROOT/logs/pmo/work-tracking.log"
mkdir -p "$(dirname "$LOG_FILE")"

# Prefer Go implementation when available
GO_RTWT_BIN="$REPO_ROOT/apps/pmo-go/bin/real-time-work-tracking"
if [ -x "$GO_RTWT_BIN" ]; then
    GO_RTWT_AVAILABLE=1
else
    GO_RTWT_AVAILABLE=0
fi

# Logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Extract issue number from commit message or branch
extract_issue_number() {
    local input="$1"

    # Try pattern: Closes #2791, Refs #2791, issue-2791, feat/issue-2791
    if grep -oP 'Closes #\K[0-9]+|Refs #\K[0-9]+|issue-\K[0-9]+' <<< "$input" | head -1; then
        return 0
    fi

    return 1
}

# Update issue status via GitHub
update_issue_status() {
    local issue_num="$1"
    local status="$2"
    local comment="$3"

    if ! command -v gh &> /dev/null; then
        log "⚠️  GitHub CLI not found. Skipping update."
        return 1
    fi

    # Map status to GitHub labels
    local label
    case "$status" in
        "in-progress") label="status: in-progress" ;;
        "in-review") label="status: in-review" ;;
        "completed") label="status: completed" ;;
        "blocked") label="status: blocked" ;;
        *) label="status: $status" ;;
    esac

    # Add label
    gh issue edit "$issue_num" \
        --repo "kushin77/ElevatedIQ-Mono-Repo" \
        --add-label "$label" 2>/dev/null || true

    # Add comment if provided
    if [ -n "$comment" ]; then
        gh issue comment "$issue_num" \
            --repo "kushin77/ElevatedIQ-Mono-Repo" \
            --body "🤖 **Auto-tracked**: $comment

**Timestamp**: $(date '+%Y-%m-%d %H:%M:%S')
**Commit**: \`$(git rev-parse --short HEAD)\`" 2>/dev/null || true
    fi

    log "✅ Updated issue #$issue_num: status=$status"
}

# Post-commit hook: Update issue on commit
hook_post_commit() {
    local commit_msg=$(git log -1 --format=%B)
    local issue_num

    # Extract issue number
    issue_num=$(extract_issue_number "$commit_msg")
    if [ -z "$issue_num" ]; then
        return 0
    fi

    log "📝 Commit hook: issue #$issue_num"

    # Determine if this is first commit (in-progress) or update
    local commit_count=$(git rev-list --count $issue_num..HEAD 2>/dev/null || echo "1")
    local status="in-progress"

    if [ "$commit_count" -eq 1 ]; then
        status="in-progress"
        update_issue_status "$issue_num" "$status" "Work started: $commit_msg"
    else
        update_issue_status "$issue_num" "in-progress" "Progress update: $commit_msg"
    fi
}

# Post-push hook: Create PR if needed
hook_post_push() {
    local branch=$(git rev-parse --abbrev-ref HEAD)
    local remote_branch="${1:-origin}"

    # Only create PR for feature branches
    if ! echo "$branch" | grep -E "^feat|^fix|^issue-" > /dev/null; then
        return 0
    fi

    local issue_num
    issue_num=$(extract_issue_number "$branch")
    if [ -z "$issue_num" ]; then
        return 0
    fi

    log "🔄 Push hook: creating PR for branch $branch (issue #$issue_num)"

    # Check if PR already exists
    if gh pr list --repo "kushin77/ElevatedIQ-Mono-Repo" \
        --head "$branch" --state open 2>/dev/null | grep -q .; then
        log "⏭️  PR already exists for $branch"
        return 0
    fi

    # Get commit message as PR description
    local pr_desc=$(git log -1 --format=%B | head -5)
    local pr_title="[PR] Issue #$issue_num"

    # Create PR
    if gh pr create --repo "kushin77/ElevatedIQ-Mono-Repo" \
        --title "$pr_title" \
        --body "**Closes**: #$issue_num

$pr_desc

---
Auto-created PR from git push hook" \
        --head "$branch" \
        --base main 2>/dev/null > /tmp/pr_out.txt; then

        local pr_num=$(grep -oP '#\K[0-9]+' /tmp/pr_out.txt | head -1)
        log "✅ Created PR #$pr_num for issue #$issue_num"
        update_issue_status "$issue_num" "in-progress" "PR created: #$pr_num"
    fi
}

# Pre-push hook: Validate commits before push
hook_pre_push() {
    local refused=0

    log "🔍 Pre-push validation..."

    # Get commits to be pushed
    local commits=$(git rev-list origin/HEAD..HEAD)

    for commit in $commits; do
        local msg=$(git log -1 --format=%B "$commit")

        # Check: Signed commit
        if ! git log -1 --pretty='%G?' "$commit" | grep -q "[SG]"; then
            log "❌ Unsigned commit: $commit"
            log "   Use: git commit -S (signed) or git config user.signingkey <key>"
            refused=1
        fi

        # Check: Has issue reference
        if ! echo "$msg" | grep -E "Closes #|Refs #" > /dev/null; then
            log "⚠️  Warning: Commit lacks issue reference: $commit"
            # Don't refuse, just warn
        fi

        # Check: Message format
        if ! echo "$msg" | grep -E "^(feat|fix|refactor|docs|style|test|chore)" > /dev/null; then
            log "⚠️  Warning: Commit lacks conventional format: $commit"
        fi
    done

    if [ "$refused" -eq 1 ]; then
        log "❌ Push blocked due to validation errors"
        return 1
    fi

    return 0
}

# Merge hook: Update issue on merge
hook_post_merge() {
    local merge_msg=$(git log -1 --format=%B)
    local issue_num

    issue_num=$(extract_issue_number "$merge_msg")
    if [ -z "$issue_num" ]; then
        return 0
    fi

    log "✅ Merge hook: issue #$issue_num"
    update_issue_status "$issue_num" "completed" "Merged to main: $merge_msg"
}

# Install hooks
install_hooks() {
    log "📝 Installing git hooks..."

    local hooks_dir="$REPO_ROOT/.git/hooks"
    mkdir -p "$hooks_dir"

    # Create post-commit hook
    cat > "$hooks_dir/post-commit" << 'HOOK'
#!/bin/bash
# Prefer Go binary if available for install/status; otherwise use shell functions
if [ -x "$(git rev-parse --show-toplevel 2>/dev/null)/apps/pmo-go/bin/real-time-work-tracking" ]; then
  $(git rev-parse --show-toplevel)/apps/pmo-go/bin/real-time-work-tracking post-commit || true
else
  source $(dirname "$0")/../../scripts/pmo/real-time-work-tracking.sh
  hook_post_commit
fi
HOOK
    chmod +x "$hooks_dir/post-commit"

    # Create post-push hook
    cat > "$hooks_dir/post-push" << 'HOOK'
#!/bin/bash
if [ -x "$(git rev-parse --show-toplevel 2>/dev/null)/apps/pmo-go/bin/real-time-work-tracking" ]; then
  $(git rev-parse --show-toplevel)/apps/pmo-go/bin/real-time-work-tracking post-push "$@" || true
else
  source $(dirname "$0")/../../scripts/pmo/real-time-work-tracking.sh
  hook_post_push "$@"
fi
HOOK
    chmod +x "$hooks_dir/post-push"

    # Create pre-push hook
    cat > "$hooks_dir/pre-push" << 'HOOK'
#!/bin/bash
if [ -x "$(git rev-parse --show-toplevel 2>/dev/null)/apps/pmo-go/bin/real-time-work-tracking" ]; then
  $(git rev-parse --show-toplevel)/apps/pmo-go/bin/real-time-work-tracking pre-push || true
else
  source $(dirname "$0")/../../scripts/pmo/real-time-work-tracking.sh
  hook_pre_push
fi
HOOK
    chmod +x "$hooks_dir/pre-push"

    log "✅ Hooks installed (Go adapter enabled if available)"
}

# Main entry point
case "${1:-}" in
    "install")
        if [ "$GO_RTWT_AVAILABLE" -eq 1 ]; then
            "$GO_RTWT_BIN" install || install_hooks
        else
            install_hooks
        fi
        ;;
    "status")
        if [ "$GO_RTWT_AVAILABLE" -eq 1 ]; then
            "$GO_RTWT_BIN" status
        else
            # Fallback status
            echo "Branch: $(git rev-parse --abbrev-ref HEAD)"
            echo "Commits ahead: $(git rev-list --count origin/HEAD..HEAD 2>/dev/null || echo 0)"
            git status --short
        fi
        ;;
    "post-commit")
        hook_post_commit
        ;;
    "post-push")
        hook_post_push
        ;;
    "pre-push")
        hook_pre_push
        ;;
    "post-merge")
        hook_post_merge
        ;;
    *)
        cat << 'USAGE'
🚀 ElevatedIQ: Real-Time Work Tracking

Automatically updates GitHub issues on git actions.

Usage:
  install                Install git hooks
  status                 Show local tracking status (delegates to Go binary if available)
  post-commit            Called after commit (auto)
  post-push              Called after push (auto)
  pre-push               Called before push (auto)
  post-merge             Called after merge (auto)

Features:
  ✓ Updates issue status on commit (in-progress)
  ✓ Creates PR on push (if branch matches pattern)
  ✓ Validates commits before push (signing, format)
  ✓ Marks issue complete on merge

Setup:
  ./scripts/pmo/real-time-work-tracking.sh install

  Hooks are auto-enabled when commits reference issues:
  - git commit -S -m "feat(core): [NIST-AC-3] description Refs #2791"
USAGE
        ;;
esac
