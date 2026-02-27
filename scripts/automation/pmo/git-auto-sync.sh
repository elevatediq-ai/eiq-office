#!/usr/bin/env bash
################################################################################
# 🔄 Git Auto-Sync with Forced Rebase
# Purpose: Automatically sync with remote and rebase when changes detected
# Requirements: NIST-AU-2 (Audit), NIST-CM-3 (Configuration Management)
#
# Features:
# - Fetches remote changes automatically
# - Detects divergence from remote branch
# - Performs automatic rebase (fast-forward preferred)
# - Handles rebase conflicts with user guidance
# - Logs all sync operations to PMO session
# - Prevents force-push scenarios
# - Maintains linear git history
################################################################################

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
SESSION_LOGS="${REPO_ROOT}/docs/management/SESSION_LOGS.md"
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
REMOTE_NAME="${GIT_REMOTE_NAME:-origin}"
AUTO_REBASE="${GIT_AUTO_REBASE:-true}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ️${NC} $1"; }
log_success() { echo -e "${GREEN}✅${NC} $1"; }
log_warn() { echo -e "${YELLOW}⚠️${NC} $1"; }
log_error() { echo -e "${RED}❌${NC} $1"; }

# Log to PMO session
log_to_pmo() {
    local action="$1"
    local details="$2"
    if [ -f "$SESSION_LOGS" ]; then
        echo "- **[$(date +%H:%M:%S)]** ${action}: ${details}" >> "$SESSION_LOGS"
    fi
}

###############################################################################
# Check if we're in a git repository
###############################################################################

if ! git rev-parse --git-dir > /dev/null 2>&1; then
    log_error "Not in a git repository"
    exit 1
fi

###############################################################################
# Main Auto-Sync Logic
###############################################################################

log_info "🔄 Git Auto-Sync with Rebase"
echo ""

# 1. Check for uncommitted changes
log_info "Step 1: Checking for uncommitted changes..."
if ! git diff-index --quiet HEAD -- 2>/dev/null; then
    log_error "Uncommitted changes detected - commit or stash first"
    echo ""
    echo "Run one of:"
    echo "  git stash"
    echo "  ./scripts/pmo/auto-commit-enforcer.sh"
    exit 1
fi
log_success "Working tree is clean ✓"
echo ""

# 2. Fetch remote changes
log_info "Step 2: Fetching remote changes..."
if git fetch "$REMOTE_NAME" 2>&1 | grep -q "fatal"; then
    log_error "Failed to fetch from remote: $REMOTE_NAME"
    exit 1
fi
log_success "Fetched latest from $REMOTE_NAME ✓"
echo ""

# 3. Check divergence
log_info "Step 3: Checking for divergence from remote..."
REMOTE_BRANCH="${REMOTE_NAME}/${CURRENT_BRANCH}"

# Check if remote branch exists
if ! git show-ref --verify --quiet "refs/remotes/${REMOTE_BRANCH}"; then
    log_warn "Remote branch $REMOTE_BRANCH does not exist"
    echo "This might be a new local branch. Push with: git push -u $REMOTE_NAME $CURRENT_BRANCH"
    exit 0
fi

# Get commit counts
LOCAL_COMMITS=$(git rev-list --count "$REMOTE_BRANCH..HEAD" 2>/dev/null || echo "0")
REMOTE_COMMITS=$(git rev-list --count "HEAD..$REMOTE_BRANCH" 2>/dev/null || echo "0")

echo "  Local branch:  $CURRENT_BRANCH"
echo "  Remote branch: $REMOTE_BRANCH"
echo "  Commits ahead of remote:  $LOCAL_COMMITS"
echo "  Commits behind remote:    $REMOTE_COMMITS"
echo ""

# 4. Determine sync strategy
if [ "$LOCAL_COMMITS" -eq 0 ] && [ "$REMOTE_COMMITS" -eq 0 ]; then
    log_success "Branch is up-to-date with remote ✓"
    exit 0
fi

if [ "$LOCAL_COMMITS" -gt 0 ] && [ "$REMOTE_COMMITS" -eq 0 ]; then
    log_success "Branch is ahead of remote (ready to push) ✓"
    exit 0
fi

if [ "$LOCAL_COMMITS" -eq 0 ] && [ "$REMOTE_COMMITS" -gt 0 ]; then
    log_info "Branch is behind remote - fast-forward merge required"

    if [ "$AUTO_REBASE" = "true" ]; then
        log_info "Performing fast-forward merge..."
        if git merge --ff-only "$REMOTE_BRANCH" 2>&1; then
            log_success "Fast-forward merge successful ✓"
            log_to_pmo "GIT_SYNC" "Fast-forward merge: $CURRENT_BRANCH (+$REMOTE_COMMITS commits)"
            exit 0
        else
            log_error "Fast-forward merge failed"
            exit 1
        fi
    else
        log_warn "Auto-rebase disabled (GIT_AUTO_REBASE=false)"
        echo "Run manually: git merge --ff-only $REMOTE_BRANCH"
        exit 1
    fi
fi

# Both ahead and behind (diverged)
if [ "$LOCAL_COMMITS" -gt 0 ] && [ "$REMOTE_COMMITS" -gt 0 ]; then
    log_warn "Branch has diverged from remote (ahead: $LOCAL_COMMITS, behind: $REMOTE_COMMITS)"
    echo ""

    if [ "$AUTO_REBASE" != "true" ]; then
        log_error "Auto-rebase is disabled. Manual intervention required."
        echo ""
        echo "Options:"
        echo "  1. Rebase:      git rebase $REMOTE_BRANCH"
        echo "  2. Merge:       git merge $REMOTE_BRANCH"
        echo "  3. Reset:       git reset --hard $REMOTE_BRANCH  (⚠️ DESTRUCTIVE)"
        exit 1
    fi

    # Interactive rebase prompt
    echo -e "${YELLOW}Divergence detected. Choose sync strategy:${NC}"
    echo "  1) Rebase (recommended - maintains linear history)"
    echo "  2) Merge (creates merge commit)"
    echo "  3) Abort (handle manually)"
    echo ""
    read -p "Choose option (1-3): " choice

    case "$choice" in
        1)
            log_info "Performing rebase..."
            echo ""

            if git rebase "$REMOTE_BRANCH" 2>&1; then
                log_success "Rebase successful ✓"
                log_to_pmo "GIT_SYNC" "Rebase completed: $CURRENT_BRANCH (resolved divergence)"
                echo ""
                log_success "Branch synchronized with remote"
                exit 0
            else
                log_error "Rebase conflicts detected"
                echo ""
                echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                echo "CONFLICT RESOLUTION REQUIRED"
                echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                echo ""
                echo "Steps to resolve:"
                echo "  1. View conflicts:     git status"
                echo "  2. Edit conflicted files manually"
                echo "  3. Mark as resolved:   git add <file>"
                echo "  4. Continue rebase:    git rebase --continue"
                echo "  5. Or abort:           git rebase --abort"
                echo ""
                log_to_pmo "GIT_SYNC" "Rebase conflict: $CURRENT_BRANCH (manual resolution required)"
                exit 1
            fi
            ;;
        2)
            log_info "Performing merge..."
            echo ""

            if git merge "$REMOTE_BRANCH" -m "chore(git): [NIST-CM-3] merge remote changes from $REMOTE_BRANCH" 2>&1; then
                log_success "Merge successful ✓"
                log_to_pmo "GIT_SYNC" "Merge completed: $CURRENT_BRANCH (resolved divergence)"
                echo ""
                log_success "Branch synchronized with remote"
                exit 0
            else
                log_error "Merge conflicts detected - resolve manually"
                log_to_pmo "GIT_SYNC" "Merge conflict: $CURRENT_BRANCH (manual resolution required)"
                exit 1
            fi
            ;;
        3)
            log_warn "Sync aborted by user"
            exit 1
            ;;
        *)
            log_error "Invalid choice"
            exit 1
            ;;
    esac
fi

# Should not reach here
log_error "Unexpected state encountered"
exit 1
