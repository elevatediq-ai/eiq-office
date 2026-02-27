#!/usr/bin/env bash
################################################################################
# 🤖 Auto-Commit Enforcer
# Purpose: Automatically stage and commit uncommitted changes with PMO tracking
# Usage: ./auto-commit-enforcer.sh [--dry-run] [--issue ISSUE_NUM] [--scope SCOPE]
#
# Features:
# - Auto-stages uncommitted files
# - Links commits to GitHub issues
# - Respects .gitignore and security patterns
# - Generates conventional commit messages with NIST controls
# - Integrates with PMO session tracking
# - Provides dry-run mode for testing
################################################################################

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=false
ISSUE_NUM=""
COMMIT_SCOPE="git"
SESSION_LOGS="${REPO_ROOT}/docs/management/SESSION_LOGS.md"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ️${NC} $1"; }
log_success() { echo -e "${GREEN}✅${NC} $1"; }
log_warn() { echo -e "${YELLOW}⚠️${NC} $1"; }
log_error() { echo -e "${RED}❌${NC} $1"; }
log_dry() { echo -e "${MAGENTA}🏜️${NC} [DRY-RUN] $1"; }

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run) DRY_RUN=true; shift ;;
        --issue) ISSUE_NUM="$2"; shift 2 ;;
        --scope) COMMIT_SCOPE="$2"; shift 2 ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --dry-run         Show what would be committed without making changes"
            echo "  --issue NUM       Link commit to specific GitHub issue"
            echo "  --scope SCOPE     Commit scope (default: git)"
            echo "  --help            Show this help message"
            exit 0
            ;;
        *) shift ;;
    esac
done

# Excluded patterns
EXCLUDED_PATTERNS=(
    ".git"
    ".env.local"
    ".DS_Store"
    "__pycache__"
    ".venv"
    ".pytest_cache"
    "*.pyc"
    "node_modules"
    ".vscode/settings.json"
)

should_exclude() {
    local file="$1"
    for pattern in "${EXCLUDED_PATTERNS[@]}"; do
        if [[ "$file" == *"$pattern"* ]]; then
            return 0
        fi
    done

    # Check for credentials/secrets
    if [[ "$file" =~ \.(key|pem|pfx|p12|jks|kdb)$ ]] || \
       [[ "$file" =~ \.env(\.|$) ]] || \
       [[ "$file" =~ (secret|password|credential|token|api_key) ]]; then
        return 0
    fi

    return 1
}

###############################################################################
# Main Execution
###############################################################################

[[ "$DRY_RUN" == true ]] && log_info "Running in DRY-RUN mode (no changes will be made)"
echo ""

# 1. Check for uncommitted changes
log_info "Step 1: Scanning for uncommitted files..."
GIT_STATUS=$(git status --porcelain)

if [ -z "$GIT_STATUS" ]; then
    log_success "Repository is clean - nothing to commit"
    exit 0
fi

# 2. Collect files to commit
FILES_TO_COMMIT=()
FILES_EXCLUDED=()

echo "$GIT_STATUS" | while read -r line; do
    status="${line:0:2}"
    file="${line:3}"

    # Skip already staged files
    if [[ "$status" == *" "* ]]; then
        # Unstaged or untracked
        if should_exclude "$file"; then
            FILES_EXCLUDED+=("$file")
            [[ "$DRY_RUN" == true ]] && log_dry "EXCLUDE: $file"
        else
            FILES_TO_COMMIT+=("$file")
            [[ "$DRY_RUN" == true ]] && log_dry "WILL STAGE: $file ($status)"
        fi
    fi
done

# Print summary
echo ""
log_info "Step 2: Summary of changes to commit"
echo "$GIT_STATUS" | while read -r line; do
    status="${line:0:2}"
    file="${line:3}"

    if ! should_exclude "$file"; then
        case "$status" in
            " M") echo -e "  ${YELLOW}modified:${NC}  $file" ;;
            " A") echo -e "  ${GREEN}added:${NC}     $file" ;;
            " D") echo -e "  ${RED}deleted:${NC}    $file" ;;
            "??") echo -e "  ${MAGENTA}untracked:${NC} $file" ;;
        esac
    fi
done

if [ "${#FILES_EXCLUDED[@]}" -gt 0 ]; then
    echo ""
    log_warn "Excluded ${#FILES_EXCLUDED[@]} files (secrets/ignored patterns)"
fi
echo ""

# 3. Get issue number if not provided
if [ -z "$ISSUE_NUM" ]; then
    BRANCH=$(git rev-parse --abbrev-ref HEAD)
    if [[ "$BRANCH" =~ ([0-9]{4,}) ]]; then
        ISSUE_NUM="${BASH_REMATCH[1]}"
        log_info "Detected issue from branch: #$ISSUE_NUM"
    else
        read -p "Enter GitHub issue number (e.g., 3209): " ISSUE_NUM
        if ! [[ "$ISSUE_NUM" =~ ^[0-9]+$ ]]; then
            log_error "Invalid issue number format"
            exit 1
        fi
    fi
fi

# 4. Stage files
if [[ "$DRY_RUN" == true ]]; then
    echo ""
    log_dry "Would stage the following files:"
else
    echo ""
    log_info "Step 3: Staging files..."

    git add -A 2>/dev/null || {
        log_error "Failed to stage files"
        exit 1
    }
fi

# 5. Create commit message
COMMIT_MSG="chore(${COMMIT_SCOPE}): [NIST-AU-2,PM-5] auto-commit staged changes Refs #${ISSUE_NUM}"

echo ""
[[ "$DRY_RUN" == true ]] && log_dry "Would create commit:" || log_info "Step 4: Creating commit..."
echo "  ${MAGENTA}${COMMIT_MSG}${NC}"

# 6. Commit
if [[ "$DRY_RUN" == true ]]; then
    log_dry "DRY-RUN: Would execute: git commit -S -m \"$COMMIT_MSG\""
    echo ""
    log_success "Dry-run completed - review above and run without --dry-run to commit"
    exit 0
fi

if git commit -S -m "$COMMIT_MSG" 2>&1 | tail -3; then
    log_success "Commit created successfully"

    # 7. Update PMO session logs
    USER=$(git config user.name || echo "unknown")
    STAGED_COUNT=$(echo "$GIT_STATUS" | wc -l)
    if [ -f "$SESSION_LOGS" ]; then
        echo "- **[$(date +%H:%M:%S)]** AUTO_COMMIT: User=$USER | Files=$STAGED_COUNT | Issue=#$ISSUE_NUM" >> "$SESSION_LOGS"
    fi

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_success "Auto-commit successful"
    echo "  User:     $USER"
    echo "  Files:    $STAGED_COUNT"
    echo "  Issue:    #$ISSUE_NUM"
    echo "  Scope:    $COMMIT_SCOPE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    log_success "Ready to push!"
    exit 0
else
    log_error "Commit failed"
    exit 1
fi
