#!/usr/bin/env bash
##############################################################################
# 🚀 ElevatedIQ: Unified Issue Engine (UIE) v1.0
# Purpose: Single Point of Truth for ALL GitHub Issue Creation.
# Features: REST-Resilient, Mandatory Metadata, AI-Optimized.
# FedRAMP: [NIST-PM-5] Standardized Project Management Enforcement.
##############################################################################

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================
REPO="kushin77/ElevatedIQ-Mono-Repo"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================================================
# LOGGING
# ============================================================================
log_info() { echo -e "${BLUE}[UIE-INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[UIE-PASS]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[UIE-WARN]${NC} $*"; }
log_error() { echo -e "${RED}[UIE-FAIL]${NC} $*"; }

# ============================================================================
# USAGE
# ============================================================================
usage() {
    echo "Usage: $0 --title \"Title\" --body \"Body\" [--type \"task|bug|epic\"] [--priority \"p0|p1|p2\"] [--milestone \"ID\"]"
    exit 1
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

TITLE=""
BODY=""
TYPE="task"
PRIORITY="p2"
MILESTONE_ID=""
LABELS=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --title) TITLE="$2"; shift 2 ;;
        --body) BODY="$2"; shift 2 ;;
        --type) TYPE="$2"; shift 2 ;;
        --priority) PRIORITY="$2"; shift 2 ;;
        --milestone) MILESTONE_ID="$2"; shift 2 ;;
        --labels) LABELS="$2"; shift 2 ;;
        *) log_error "Unknown argument: $1"; usage ;;
    esac
done

if [[ -z "$TITLE" || -z "$BODY" ]]; then
    log_warn "Missing title or body. Attempting to read from stdin..."
    if [[ -z "$TITLE" ]]; then read -p "Enter Title: " TITLE; fi
    if [[ -z "$BODY" ]]; then echo "Enter Body (Ctrl+D to end):"; BODY=$(cat); fi
fi

# 1. Smart Metadata Enrichment
log_info "Enriching metadata for: $TITLE"

# Auto-Labels
[[ -z "$LABELS" ]] && LABELS="type:$TYPE,priority-$PRIORITY"

# 2. Mandatory Milestone Alignment (The 10X Guardrail)
if [[ -z "$MILESTONE_ID" ]]; then
    log_info "Calculating heuristic milestone..."
    MILESTONE_ID=$(bash "$SCRIPT_DIR/smart_milestone_selector.sh" "$TITLE" "$BODY" "$LABELS")
    log_info "Automated alignment: Milestone ID $MILESTONE_ID"
fi

# 3. REST-API Resilient Creation (Bypassing GraphQL rate limits)
log_info "Executing resilient creation via REST API..."

# Prepare JSON (milestone will be applied separately)
LABELS_JSON=$(echo "$LABELS" | tr ',' '\n' | jq -R . | jq -s -c .)

PAYLOAD=$(jq -n \
    --arg title "$TITLE" \
    --arg body "$BODY" \
    --argjson labels "$LABELS_JSON" \
    '{title: $title, body: $body, labels: $labels}')

RESPONSE=$(echo "$PAYLOAD" | gh api -X POST "repos/${REPO}/issues" --input - 2>&1)

if echo "$RESPONSE" | grep -q "html_url"; then
    ISSUE_URL=$(echo "$RESPONSE" | jq -r '.html_url')
    ISSUE_NUMBER=$(echo "$RESPONSE" | jq -r '.number')
    log_success "Created Issue #$ISSUE_NUMBER: $ISSUE_URL"

    # Apply milestone AFTER creation (GitHub API limitation)
    if [[ -n "$MILESTONE_ID" && "$MILESTONE_ID" != "null" ]]; then
        MILESTONE_TITLE=$(python3 -c "
import json
MILESTONE_MAP = {
    '3': 'Project Beta: AI Intelligence',
    '4': 'Project Gamma: Infrastructure',
    '5': 'Project Delta: Security',
    '6': 'Project Sigma: FinOps',
    '27': 'Project Zeta: Observability',
    '20': 'Project Omega',
    '9': 'Phase 6: Advanced Features',
    '28': 'Project Eta: Backlog'
}
print(MILESTONE_MAP.get('$MILESTONE_ID', 'Project Eta: Backlog'))
" 2>/dev/null || echo "Project Eta: Backlog")
        log_info "Applying milestone: $MILESTONE_TITLE (#$MILESTONE_ID)"
        gh issue edit "$ISSUE_NUMBER" --repo "$REPO" --milestone "$MILESTONE_TITLE" 2>&1 || log_warn "Could not apply milestone"
    fi

    # Optional: Log to Session
    if [[ -x "$SCRIPT_DIR/session_tracker.sh" ]]; then
        "$SCRIPT_DIR/session_tracker.sh" update issue "Created #$ISSUE_NUMBER: $TITLE" || true
    fi

    echo "$ISSUE_URL"
else
    log_error "Creation Failed. Analysis below:"
    echo "$RESPONSE" | jq . || echo "$RESPONSE"
    exit 1
fi
