#!/usr/bin/env bash
################################################################################
# 🚀 Enhanced Pre-Push Hook with Auto-Sync
# Purpose: Pre-push validation + automatic sync with remote
#
# Enhancement over git-pre-push-enhanced.sh:
# - Automatically fetches and syncs with remote before push
# - Detects divergence and offers rebase/merge
# - Prevents push of stale branches
# - Ensures linear history maintenance
################################################################################

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTO_SYNC_SCRIPT="${SCRIPT_DIR}/git-auto-sync.sh"
ENHANCED_PUSH="${SCRIPT_DIR}/git-pre-push-enhanced.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ️${NC} $1"; }
log_success() { echo -e "${GREEN}✅${NC} $1"; }
log_warn() { echo -e "${YELLOW}⚠️${NC} $1"; }
log_error() { echo -e "${RED}❌${NC} $1"; }

echo ""
log_info "🚀 Pre-Push Hook with Auto-Sync"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Step 1: Run auto-sync (fetch + rebase if needed)
log_info "Phase 1: Synchronizing with remote..."
echo ""

if [ -x "$AUTO_SYNC_SCRIPT" ]; then
    if bash "$AUTO_SYNC_SCRIPT" 2>&1; then
        log_success "Branch synchronized with remote ✓"
    else
        SYNC_EXIT=$?
        if [ $SYNC_EXIT -eq 1 ]; then
            log_error "Sync failed - resolve conflicts before pushing"
            exit 1
        fi
        # Exit code 0 means no sync needed
    fi
else
    log_warn "Auto-sync script not found at $AUTO_SYNC_SCRIPT"
    log_info "Skipping sync validation..."
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Step 2: Run standard pre-push validation
log_info "Phase 2: Running pre-push validation..."
echo ""

if [ -x "$ENHANCED_PUSH" ]; then
    if bash "$ENHANCED_PUSH" 2>&1; then
        log_success "Pre-push validation passed ✓"
    else
        log_error "Pre-push validation failed"
        exit 1
    fi
else
    log_error "Enhanced pre-push script not found at $ENHANCED_PUSH"
    exit 1
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_success "All pre-push checks passed - proceeding with push ✓"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

exit 0
