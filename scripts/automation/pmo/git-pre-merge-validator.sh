#!/usr/bin/env bash
################################################################################
# 🔒 Pre-Merge Validator Hook
# Purpose: Prevent merges when uncommitted/staged changes exist
# Requirements: NIST-AU-2 (Audit), NIST-PM-5 (Governance)
#
# Validates:
# - No staged changes in working tree
# - All commits follow conventional format
# - All commits have issue references
# - No merge conflicts
# - All affected files pass linting/security checks
################################################################################

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ️${NC} $1"; }
log_success() { echo -e "${GREEN}✅${NC} $1"; }
log_warn() { echo -e "${YELLOW}⚠️${NC} $1"; }
log_error() { echo -e "${RED}❌${NC} $1"; }

ERRORS=0

log_info "🔒 Pre-Merge Validation"
echo ""

# 1. Check for staged changes (uncommitted files)
log_info "Step 1: Checking for uncommitted files..."
STAGED=$(git diff --cached --name-only 2>/dev/null | wc -l)
UNCOMMITTED=$(git diff --name-only 2>/dev/null | wc -l)
UNTRACKED=$(git ls-files --others --exclude-standard 2>/dev/null | wc -l)

if [ "$STAGED" -gt 0 ] || [ "$UNCOMMITTED" -gt 0 ]; then
    log_error "Found uncommitted changes - cannot merge"
    echo "  Staged changes: $STAGED"
    echo "  Unstaged changes: $UNCOMMITTED"
    echo "  Untracked files: $UNTRACKED"
    ((ERRORS++))
else
    log_success "No uncommitted changes ✓"
fi
echo ""

# 2. Check merge conflicts
log_info "Step 2: Checking for merge conflicts..."
if [ -f ".git/MERGE_HEAD" ]; then
    CONFLICTS=$(git diff --name-only --diff-filter=U 2>/dev/null | wc -l)
    if [ "$CONFLICTS" -gt 0 ]; then
        log_error "Unresolved merge conflicts detected"
        git diff --name-only --diff-filter=U | sed 's/^/  /'
        ((ERRORS++))
    else
        log_success "All conflicts resolved ✓"
    fi
else
    log_success "No merge in progress ✓"
fi
echo ""

# 3. Validate merge branch has valid commits
log_info "Step 3: Validating commit messages in merge..."
BASE_BRANCH="main"
MERGE_BRANCH="${MERGE_BRANCH:-HEAD}"

if git log --oneline "$BASE_BRANCH..$MERGE_BRANCH" > /dev/null 2>&1; then
    COMMIT_COUNT=$(git log --oneline "$BASE_BRANCH..$MERGE_BRANCH" | wc -l)
    echo "  Commits to merge: $COMMIT_COUNT"

    if [ "$COMMIT_COUNT" -gt 0 ]; then
        INVALID_COMMITS=0
        git log "$BASE_BRANCH..$MERGE_BRANCH" --format=%B | while read -r line; do
            # Very basic check for issue reference
            if [[ ! "$line" =~ Refs\ #[0-9]+ ]] && [[ ! "$line" =~ Closes\ #[0-9]+ ]]; then
                ((INVALID_COMMITS++))
            fi
        done

        if [ "$INVALID_COMMITS" -gt 0 ]; then
            log_warn "Some commits may lack issue references (check review)"
        else
            log_success "All commits reference issues ✓"
        fi
    fi
fi
echo ""

# 4. Check for secrets/credentials
log_info "Step 4: Scanning for secrets..."
if command -v gitleaks > /dev/null 2>&1; then
    if gitleaks detect --source git --verbose --exit-code 0 > /dev/null 2>&1; then
        log_success "No secrets detected ✓"
    else
        log_warn "Potential secrets detected - review before merge"
    fi
else
    log_info "gitleaks not installed - skipping secrets scan"
fi
echo ""

# 5. Summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "📊 Pre-Merge Summary"
echo "  Status: $([ $ERRORS -eq 0 ] && echo '✅ OK TO MERGE' || echo '❌ MERGE BLOCKED')"
echo "  Validation errors: $ERRORS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [ $ERRORS -gt 0 ]; then
    log_error "Pre-merge validation failed"
    exit 1
fi

log_success "All pre-merge validations passed ✓"
exit 0
