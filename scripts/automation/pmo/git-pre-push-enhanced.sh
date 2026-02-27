#!/usr/bin/env bash
################################################################################
# 🚀 Enhanced Git Pre-Push Hook with Auto-Commit Enforcement
# Purpose: Validate and enforce commits before push, integrate with PMO tracking
# Requirements: NIST-AU-2 (Audit & Accountability), NIST-PM-5 (Governance)
#
# Features:
# - Detects uncommitted/unstaged files
# - Auto-stages and commits with conventional format + NIST controls
# - Links commits to GitHub issues
# - Tracks in PMO session logs
# - Multi-user awareness and logging
# - Prevents push if validation fails
################################################################################

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMIT_VALIDATOR="${SCRIPT_DIR}/commit_validator.sh"
SESSION_LOGS="${REPO_ROOT}/docs/management/SESSION_LOGS.md"
GIT_EXCLUDED_PATTERNS=(".git" ".env.local" ".DS_Store" "__pycache__" ".venv" ".pytest_cache" "*.pyc" "node_modules")

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Stats
UNCOMMITTED_COUNT=0
STAGED_COUNT=0
AUTO_COMMITTED=0
ERRORS=0

###############################################################################
# Utility Functions
###############################################################################

log_info() { echo -e "${BLUE}ℹ️${NC} $1"; }
log_success() { echo -e "${GREEN}✅${NC} $1"; }
log_warn() { echo -e "${YELLOW}⚠️${NC} $1"; }
log_error() { echo -e "${RED}❌${NC} $1"; }

# Pattern to exclude from auto-commit
should_exclude_file() {
    local file="$1"
    for pattern in "${GIT_EXCLUDED_PATTERNS[@]}"; do
        if [[ "$file" == *"$pattern"* ]]; then
            return 0  # Exclude (match)
        fi
    done
    # Additional security checks
    if [[ "$file" =~ \.(key|pem|pfx|p12|jks|kdb)$ ]] || \
       [[ "$file" =~ \.env(\.|$) ]] || \
       [[ "$file" =~ (secret|password|credential|token|api_key).*\.(json|yaml|txt|md)$ ]]; then
        return 0  # Exclude (credentials)
    fi
    return 1  # Include
}

# Get issue number from branch name or prompt user
get_issue_number() {
    local branch=$(git rev-parse --abbrev-ref HEAD)
    # Try to extract issue from branch name (e.g., "fix/3209-commit-push")
    if [[ "$branch" =~ ([0-9]{4,}) ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi
    # Fallback: ask user
    echo -n "Enter GitHub issue number (e.g., 3209): "
    read -r issue_num
    if [[ "$issue_num" =~ ^[0-9]+$ ]]; then
        echo "$issue_num"
        return 0
    fi
    return 1
}

# Generate commit message following conventional commits format
generate_commit_message() {
    local type="${1:-chore}"
    local scope="${2:-pmo}"
    local description="${3:-auto-commit staged changes}"
    local issue="${4:-}"

    local msg="${type}(${scope}): [NIST-AU-2,PM-5] ${description}"
    if [ -n "$issue" ]; then
        msg+=" Refs #${issue}"
    fi
    echo "$msg"
}

# Log to PMO session
log_to_pmo() {
    local action="$1"
    local details="$2"
    if [ -f "$SESSION_LOGS" ]; then
        echo "- **[$(date +%H:%M:%S)]** ${action}: ${details}" >> "$SESSION_LOGS"
    fi
}

###############################################################################
# PRE-PUSH VALIDATION
###############################################################################

log_info "🔍 Pre-Push Validation (Enhanced)"
echo ""

# 1. Check for uncommitted/unstaged files
log_info "Step 1: Checking for staged/unstaged changes..."
GIT_STATUS=$(git status --porcelain)

if [ -z "$GIT_STATUS" ]; then
    log_success "No uncommitted files detected ✓"
    echo ""
else
    echo "$GIT_STATUS" | while read -r line; do
        status="${line:0:2}"
        file="${line:3}"

        # Skip excluded files
        if should_exclude_file "$file"; then
            echo -e "  ${YELLOW}⊘${NC} ${file} (excluded)"
            continue
        fi

        case "$status" in
            "M ")  ((STAGED_COUNT++)); echo -e "  ${BLUE}M${NC} ${file} (modified, staged)" ;;
            " M")  ((UNCOMMITTED_COUNT++)); echo -e "  ${MAGENTA}M${NC} ${file} (modified, unstaged)" ;;
            "A ")  ((STAGED_COUNT++)); echo -e "  ${BLUE}A${NC} ${file} (added, staged)" ;;
            " A")  ((UNCOMMITTED_COUNT++)); echo -e "  ${MAGENTA}A${NC} ${file} (added, unstaged)" ;;
            "D ")  ((STAGED_COUNT++)); echo -e "  ${BLUE}D${NC} ${file} (deleted, staged)" ;;
            " D")  ((UNCOMMITTED_COUNT++)); echo -e "  ${MAGENTA}D${NC} ${file} (deleted, unstaged)" ;;
            "??") ((UNCOMMITTED_COUNT++)); echo -e "  ${RED}?${NC} ${file} (untracked)" ;;
            *)    echo -e "  ${YELLOW}?${NC} ${file} (unknown status: $status)" ;;
        esac
    done
fi

TOTAL_CHANGES=$((STAGED_COUNT + UNCOMMITTED_COUNT))
echo ""

if [ $TOTAL_CHANGES -eq 0 ]; then
    log_success "Repository is clean, proceeding with push validation"
    echo ""
else
    log_warn "Found $TOTAL_CHANGES uncommitted/unstaged files"
    echo "  - Staged: $STAGED_COUNT"
    echo "  - Unstaged: $UNCOMMITTED_COUNT"
    echo ""
fi

# 2. Prompt for action if uncommitted changes exist
if [ $UNCOMMITTED_COUNT -gt 0 ]; then
    log_warn "Unstaged changes detected - auto-staging enabled"
    echo ""
    echo -e "  ${YELLOW}Options:${NC}"
    echo "    1) Auto-stage and commit all unstaged changes (recommended)"
    echo "    2) Manual staging - I'll handle it"
    echo "    3) Abort push"
    echo ""

    read -p "  Choose option (1-3): " choice

    case "$choice" in
        1)
            log_info "Auto-staging all modified files..."

            # Get issue number for commit
            ISSUE_NUM=$(get_issue_number) || {
                log_error "Failed to get issue number"
                ((ERRORS++))
            }

            # Stage all uncommitted changes (excluding sensitive files)
            git status --porcelain | while read -r line; do
                file="${line:3}"
                if ! should_exclude_file "$file"; then
                    git add "$file" 2>/dev/null || true
                    echo -e "  ${GREEN}+${NC} Staged: $file"
                fi
            done

            # Generate and execute commit
            COMMIT_MSG=$(generate_commit_message "chore" "git" "auto-commit uncommitted changes" "$ISSUE_NUM")

            if git commit -S -m "$COMMIT_MSG" 2>/dev/null; then
                ((AUTO_COMMITTED++))
                log_success "Auto-committed staged changes"
                log_to_pmo "AUTO_COMMIT" "Successfully auto-committed $UNCOMMITTED_COUNT files (Issue #$ISSUE_NUM)"
            else
                log_error "Failed to auto-commit changes"
                ((ERRORS++))
            fi
            ;;
        2)
            log_info "Manual staging mode - stage your files and re-run push"
            exit 1
            ;;
        3)
            log_warn "Push aborted by user"
            exit 1
            ;;
        *)
            log_error "Invalid choice. Aborting push."
            exit 1
            ;;
    esac
    echo ""
fi

# 3. Run PMO Health Check (Milestone Enforcement)
log_info "Step 2: Running PMO Health Check (Milestone Enforcement)..."
if bash "${SCRIPT_DIR}/milestone_enforcer.sh" 2>&1 | tail -5; then
    log_success "PMO Health Check passed ✓"
else
    log_error "PMO Health Check failed"
    ((ERRORS++))
fi
echo ""

# 4. Validate commit messages for all unpushed commits
log_info "Step 3: Validating commit messages..."
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
REMOTE_COMMITS=$(git log origin/main..HEAD --oneline 2>/dev/null | wc -l)

if [ "$REMOTE_COMMITS" -gt 0 ]; then
    echo "  Found $REMOTE_COMMITS unpushed commits"

    FAILED_VALIDATION=0
    git log origin/main..HEAD --format=%B | while read -r line; do
        if [ -n "$line" ]; then
            if ! ${COMMIT_VALIDATOR} /dev/stdin <<< "$line" 2>/dev/null; then
                ((FAILED_VALIDATION++))
            fi
        fi
    done

    if [ "$FAILED_VALIDATION" -eq 0 ]; then
        log_success "All commit messages are valid ✓"
    else
        log_error "$FAILED_VALIDATION commits have invalid messages"
        ((ERRORS++))
    fi
else
    log_info "No unpushed commits detected"
fi
echo ""

# 5. Check for merge conflicts
log_info "Step 4: Checking for merge conflicts..."
if [ -f ".git/MERGE_HEAD" ]; then
    log_error "Merge conflict detected - resolve before pushing"
    ((ERRORS++))
else
    log_success "No merge conflicts detected ✓"
fi
echo ""

# 6. Final summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "📊 Pre-Push Summary"
echo "  Staged changes:      $STAGED_COUNT"
echo "  Uncommitted changes: $UNCOMMITTED_COUNT"
echo "  Auto-committed:      $AUTO_COMMITTED"
echo "  Validation errors:   $ERRORS"
echo "  Branch:              $CURRENT_BRANCH"
echo "  Status:              $([ $ERRORS -eq 0 ] && echo '✅ READY TO PUSH' || echo '❌ VALIDATION FAILED')"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Log to PMO
USER=$(git config user.name || echo "unknown")
log_to_pmo "PRE_PUSH_CHECK" "User: $USER | Branch: $CURRENT_BRANCH | Status: $([ $ERRORS -eq 0 ] && echo 'PASS' || echo 'FAIL')"

# Exit with appropriate code
if [ $ERRORS -gt 0 ]; then
    log_error "Pre-push validation failed. Fix issues before pushing."
    exit 1
fi

log_success "All validations passed - proceeding with push ✓"
exit 0
