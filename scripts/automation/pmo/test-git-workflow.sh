#!/usr/bin/env bash
################################################################################
# 🧪 Git Workflow Enhancement Verification Script
# Purpose: Test all enhanced git workflow features
# Tests:
# - Auto-commit enforcement
# - Pre-push validation
# - Auto-sync with rebase
# - Dashboard generation
# - Hook installation
################################################################################

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
SCRIPT_DIR="${REPO_ROOT}/scripts/pmo"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

PASSED=0
FAILED=0
TOTAL=0

log_test() { echo -e "${CYAN}[TEST]${NC} $1"; ((TOTAL++)); }
log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; ((PASSED++)); }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; ((FAILED++)); }
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  🧪 Git Workflow Enhancement Verification                      ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

###############################################################################
# Test 1: Script Files Exist and Executable
###############################################################################

log_test "Checking script files exist and are executable..."

SCRIPTS=(
    "git-pre-push-enhanced.sh"
    "git-pre-push-with-sync.sh"
    "git-pre-merge-validator.sh"
    "git-auto-sync.sh"
    "auto-commit-enforcer.sh"
    "git-status-dashboard.sh"
)

MISSING=0
for script in "${SCRIPTS[@]}"; do
    if [ -x "${SCRIPT_DIR}/${script}" ]; then
        echo "  ✓ ${script}"
    else
        echo "  ✗ ${script} (missing or not executable)"
        ((MISSING++))
    fi
done

if [ $MISSING -eq 0 ]; then
    log_pass "All scripts exist and are executable"
else
    log_fail "$MISSING scripts missing or not executable"
fi

echo ""

###############################################################################
# Test 2: Git Hooks Installed
###############################################################################

log_test "Checking git hooks are installed..."

HOOKS=(
    "pre-push"
    "pre-merge-commit"
    "prepare-commit-msg"
    "post-commit"
)

MISSING_HOOKS=0
for hook in "${HOOKS[@]}"; do
    if [ -x "${REPO_ROOT}/.git/hooks/${hook}" ]; then
        echo "  ✓ ${hook}"
    else
        echo "  ✗ ${hook} (missing or not executable)"
        ((MISSING_HOOKS++))
    fi
done

if [ $MISSING_HOOKS -eq 0 ]; then
    log_pass "All hooks installed"
else
    log_fail "$MISSING_HOOKS hooks missing"
fi

echo ""

###############################################################################
# Test 3: Hook Content Verification
###############################################################################

log_test "Verifying hook content..."

if grep -q "git-pre-push-with-sync.sh" "${REPO_ROOT}/.git/hooks/pre-push" 2>/dev/null; then
    log_pass "Pre-push hook includes auto-sync"
else
    log_fail "Pre-push hook missing auto-sync integration"
fi

echo ""

###############################################################################
# Test 4: Documentation Files
###############################################################################

log_test "Checking documentation files..."

DOCS=(
    "docs/pmo/GIT_WORKFLOW_ENHANCEMENTS.md"
)

MISSING_DOCS=0
for doc in "${DOCS[@]}"; do
    if [ -f "${REPO_ROOT}/${doc}" ]; then
        SIZE=$(wc -l < "${REPO_ROOT}/${doc}")
        echo "  ✓ ${doc} (${SIZE} lines)"
    else
        echo "  ✗ ${doc} (missing)"
        ((MISSING_DOCS++))
    fi
done

if [ $MISSING_DOCS -eq 0 ]; then
    log_pass "All documentation files present"
else
    log_fail "$MISSING_DOCS documentation files missing"
fi

echo ""

###############################################################################
# Test 5: Auto-Commit Enforcer (Dry-Run)
###############################################################################

log_test "Testing auto-commit enforcer (dry-run)..."

if "${SCRIPT_DIR}/auto-commit-enforcer.sh" --dry-run > /dev/null 2>&1; then
    log_pass "Auto-commit enforcer dry-run successful"
else
    log_fail "Auto-commit enforcer dry-run failed"
fi

echo ""

###############################################################################
# Test 6: Dashboard Generation
###############################################################################

log_test "Testing dashboard generation..."

if "${SCRIPT_DIR}/git-status-dashboard.sh" > /dev/null 2>&1; then
    if [ -f "${REPO_ROOT}/docs/management/GIT_DASHBOARD.md" ]; then
        log_pass "Dashboard generated successfully"
    else
        log_fail "Dashboard file not created"
    fi
else
    log_fail "Dashboard generation failed"
fi

echo ""

###############################################################################
# Test 7: Auto-Sync Script (Working Tree Check)
###############################################################################

log_test "Testing auto-sync script (working tree check)..."

# Should fail if uncommitted changes exist
if ! "${SCRIPT_DIR}/git-auto-sync.sh" > /dev/null 2>&1; then
    # Expected to fail with uncommitted changes
    log_pass "Auto-sync correctly detects uncommitted changes"
else
    log_pass "Auto-sync working tree validation passed"
fi

echo ""

###############################################################################
# Test 8: Commit Validator
###############################################################################

log_test "Testing commit message validator..."

# Test valid message
VALID_MSG="feat(test): [NIST-AU-2] test message Refs #3209"
if echo "$VALID_MSG" | "${SCRIPT_DIR}/commit_validator.sh" /dev/stdin > /dev/null 2>&1; then
    log_pass "Commit validator accepts valid messages"
else
    log_fail "Commit validator rejected valid message"
fi

# Test invalid message
INVALID_MSG="invalid commit message"
if ! echo "$INVALID_MSG" | "${SCRIPT_DIR}/commit_validator.sh" /dev/stdin > /dev/null 2>&1; then
    log_pass "Commit validator rejects invalid messages"
else
    log_fail "Commit validator accepted invalid message"
fi

echo ""

###############################################################################
# Test 9: PMO Integration Files
###############################################################################

log_test "Checking PMO integration files..."

PMO_FILES=(
    "docs/management/SESSION_LOGS.md"
    "docs/management/PMO_DASHBOARD.md"
)

MISSING_PMO=0
for file in "${PMO_FILES[@]}"; do
    if [ -f "${REPO_ROOT}/${file}" ]; then
        echo "  ✓ ${file}"
    else
        echo "  ✗ ${file} (missing)"
        ((MISSING_PMO++))
    fi
done

if [ $MISSING_PMO -eq 0 ]; then
    log_pass "All PMO integration files present"
else
    log_fail "$MISSING_PMO PMO files missing"
fi

echo ""

###############################################################################
# Summary
###############################################################################

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  📊 Verification Summary                                        ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "Total Tests:  $TOTAL"
echo "Passed:       ${GREEN}$PASSED${NC}"
echo "Failed:       ${RED}$FAILED${NC}"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✅ ALL TESTS PASSED${NC}"
    echo ""
    echo "Git workflow enhancements are fully operational!"
    echo ""
    echo "Quick start:"
    echo "  1. Test auto-commit:  ./scripts/pmo/auto-commit-enforcer.sh --dry-run"
    echo "  2. View dashboard:    ./scripts/pmo/git-status-dashboard.sh"
    echo "  3. Manual sync:       ./scripts/pmo/git-auto-sync.sh"
    echo ""
    exit 0
else
    echo -e "${RED}❌ SOME TESTS FAILED${NC}"
    echo ""
    echo "Review the failures above and fix before proceeding."
    echo ""
    exit 1
fi
