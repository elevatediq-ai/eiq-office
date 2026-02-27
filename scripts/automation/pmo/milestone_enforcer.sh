#!/usr/bin/env bash
##############################################################################
# 🎯 Milestone Enforcer - RUTHLESS 10X QUALITY ENFORCEMENT
# Purpose: Scan ALL issues (open + closed, with or without milestones)
#          Validate topic coherence and aggressively re-organize misaligned issues
# Uses: AI classifier + coherence validator for ruthless quality
# Session: 20260218-10X-MILESTONE-ENFORCER
# Issue: #3459 (Ruthless 10X Enhancement)
# FedRAMP: [NIST-PM-5] Project Management with automated governance
# Usage: ./milestone_enforcer.sh                (all issues, standard validation)
# Usage: ./milestone_enforcer.sh --ruthless       (ruthless re-organization of ALL issues)
# Usage: ./milestone_enforcer.sh --open           (open only)
# Usage: ./milestone_enforcer.sh --coherence      (check coherence only, no changes)
# Env Vars:
#   REPO: GitHub repository (default: kushin77/ElevatedIQ-Mono-Repo)
#   DRY_RUN: Set to "true" to skip applying milestones
#   COHERENCE_THRESHOLD: Minimum score to keep (default: 0.70)
#   RUTHLESS: Set to "true" to force re-evaluation of ALL issues
##############################################################################

set -euo pipefail

# Configuration
REPO="${REPO:-kushin77/ElevatedIQ-Mono-Repo}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_MILESTONE="Project Eta: Backlog"
DEFAULT_MILESTONE_ID="28"
SCOPE="${1:---all}"
DRY_RUN="${DRY_RUN:-false}"
COHERENCE_THRESHOLD="${COHERENCE_THRESHOLD:-0.70}"
COHERENCE_ONLY="${COHERENCE_ONLY:-false}"
RUTHLESS="${RUTHLESS:-false}"

# Phase 6: Aggressive Tuning Configuration
AGGRESSIVE_MODE="${AGGRESSIVE_MODE:-false}"
FORCE_REALIGN="${FORCE_REALIGN:-false}"
AGGRESSIVE_THRESHOLD="${AGGRESSIVE_THRESHOLD:-0.75}"  # Phase 6: Lower from 0.90 to 0.75
REALIGN_OVERRIDE="${REALIGN_OVERRIDE:-0.70}"  # Minimum confidence to force realign

# Source centralized logging lib for consistent helpers
export LOG_FILE="${LOG_FILE:-./scripts/pmo/logs/milestone_enforcer.log}"
if [[ -f "${SCRIPT_DIR}/../lib/logging.sh" ]]; then
    # shellcheck source=/dev/null
    source "${SCRIPT_DIR}/../lib/logging.sh"
else
    # Fallback minimal logger if lib is missing
    log_info() { echo -e "\033[0;32m[INFO]\033[0m $*" >&2; }
    log_warn() { echo -e "\033[1;33m[WARN]\033[0m $*" >&2; }
    log_error() { echo -e "\033[0;31m[ERROR]\033[0m $*" >&2; }
    log_success() { echo -e "\033[0;36m✅ $*\033[0m" >&2; }
    log_header() { echo -e "\n\033[0;34m=== $* ===\033[0m\n" >&2; }
    log_section() { echo -e "\n\033[0;35m--- $* ---\033[0m\n" >&2; }
fi

# Check for mode flags in args
if [[ "$*" == *"--ruthless"* ]]; then
    RUTHLESS="true"
    log_warn "🔥 RUTHLESS MODE ACTIVATED: All issue milestones will be re-evaluated!"
fi

if [[ "$*" == *"--aggressive"* ]]; then
    AGGRESSIVE_MODE="true"
    FORCE_REALIGN="true"
    log_warn "⚡ AGGRESSIVE MODE ACTIVATED: Forced realignment enabled (Phase 6 tuning)!"
    log_warn "   • Auto-assign threshold: $AGGRESSIVE_THRESHOLD (down from 0.90)"
    log_warn "   • Force realign enabled for coherence < $REALIGN_OVERRIDE"
fi

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

# Lightweight GH API retry helper (idempotent/backoff)
gh_api_retry() {
    local tries=4
    local wait=2
    local i=0
    local cmd="$*"

    until [ $i -ge $tries ]; do
        if eval "$cmd" 2>/dev/null; then
            return 0
        fi
        i=$((i+1))
        sleep $((wait * i))
    done

    # final attempt (allow error propagation)
    eval "$cmd"
}

log_header "Milestone Enforcement Engine"
log_info "Repository: $REPO"
log_info "Dry Run: $DRY_RUN"

# Determine scope
if [[ "$SCOPE" != "--open" ]]; then
    log_info "Mode: ALL issues (open + closed)"
    STATES=("open" "closed")
else
    log_info "Mode: Open issues only"
    STATES=("open")
fi

TOTAL_REMEDIATED=0
TOTAL_FORCED_REALIGN=0
TOTAL_SCANNED=0

# Metrics tracking
DECISION_LOG="${LOG_FILE%.log}_decisions_$(date +%s).jsonl"

# Process each state
for STATE in "${STATES[@]}"; do
    log_section "Processing $STATE issues (Aggressive: $AGGRESSIVE_MODE, Force Realign: $FORCE_REALIGN)"

    # Get issue details into a temp file for robust processing
    log_info "Fetching $STATE issues details..."
    TMP_JSON=$(mktemp)

    # If ruthless, fetch ALL issues. Else fetch missing/backlog/legacy.
    if [[ "$RUTHLESS" == "true" ]]; then
        QUERY=".[] | {number: .number, title: .title, body: .body, labels: [(.labels[].name // empty)], current_milestone: (.milestone.number // null), current_milestone_title: (.milestone.title // \"\")}"
    else
        QUERY=".[] | select(.milestone == null or .milestone.number == 28 or .milestone.number == 30 or .milestone.number == 32 or .milestone.number == 34) | {number: .number, title: .title, body: .body, labels: [(.labels[].name // empty)], current_milestone: (.milestone.number // null), current_milestone_title: (.milestone.title // \"\")}"
    fi

    # Fetch $STATE issues details with PAGINATION
    gh api --paginate "repos/$REPO/issues?state=$STATE&per_page=100" --jq "$QUERY" \
        | jq -c '.' > "$TMP_JSON" 2>/dev/null || true

    ISSUE_COUNT=$(wc -l < "$TMP_JSON")
    if [[ "$ISSUE_COUNT" -eq 0 ]]; then
        log_success "All $STATE issues in this batch are already optimized"
        rm -f "$TMP_JSON"
        continue
    fi

    log_info "Found $ISSUE_COUNT $STATE issues requiring milestone optimization (missing or in backlog)"

    COUNTER=0
    BATCH_REMEDIATED=0

    # Process issues from the temp file line by line
    while IFS= read -r ISSUE_JSON; do
        [[ -z "$ISSUE_JSON" ]] && continue
        ((COUNTER++)) || true
        ((TOTAL_SCANNED++)) || true

        NUMBER=$(echo "$ISSUE_JSON" | jq -r '.number')
        TITLE=$(echo "$ISSUE_JSON" | jq -r '.title')
        BODY=$(echo "$ISSUE_JSON" | jq -r '.body // ""')
        LABELS=$(echo "$ISSUE_JSON" | jq -r '[.labels[]] | join(",")')
        CURRENT_MILESTONE=$(echo "$ISSUE_JSON" | jq -r '.current_milestone // ""')

        # Use Expert Rules Engine instead of simple classifier
        # The rules engine returns a JSON with actions and confidence
        RE_RESULT=$(echo "$ISSUE_JSON" | python3 "$SCRIPT_DIR/milestone_rules_engine.py" - 2>/dev/null || echo "{}")

        PROPOSED_MILESTONE_ID=$(echo "$RE_RESULT" | jq -r '.milestone_id // empty')
        AUTO_ASSIGN=$(echo "$RE_RESULT" | jq -r '.actions.auto_assign // false')
        CONFIDENCE=$(echo "$RE_RESULT" | jq -r '.confidence // 0')
        PROPOSED_TITLE=$(echo "$RE_RESULT" | jq -r '.milestone_title // "Unknown"')

        # Phase 6: In aggressive mode, use lower threshold
        if [[ "$AGGRESSIVE_MODE" == "true" ]] && (( $(echo "$CONFIDENCE >= $AGGRESSIVE_THRESHOLD" | bc -l) )); then
            AUTO_ASSIGN="true"
        fi

        # If no solid proposal or only backlog, ask AI for a suggested milestone and create one if needed
        if [[ -z "$PROPOSED_MILESTONE_ID" ]] || [[ "$PROPOSED_MILESTONE_ID" == "null" ]] || [[ "$PROPOSED_MILESTONE_ID" == "28" && "$CURRENT_MILESTONE" == "28" ]]; then
            log_info "[$COUNTER/$ISSUE_COUNT] #$NUMBER: No strong proposal (or backlog). Requesting AI suggestion for milestone title..."
            SUGGEST_TITLE=$(python3 "$SCRIPT_DIR/ai_classifier.py" "$TITLE" "$BODY" "$LABELS" suggest 2>/dev/null || echo "")
            SUGGEST_TITLE=$(echo "$SUGGEST_TITLE" | tr -d '\r' | sed -e 's/^\s*//;s/\s*$//')

            if [[ -n "$SUGGEST_TITLE" ]]; then
                # Check existing milestones for this title
                MILESTONE_JSON=$(gh api "repos/$REPO/milestones?state=open&per_page=100" 2>/dev/null || echo "[]")
                EXISTING_ID=$(echo "$MILESTONE_JSON" | jq -r --arg t "$SUGGEST_TITLE" '.[] | select(.title==$t) | .number' | head -n1 || true)
                if [[ -n "$EXISTING_ID" && "$EXISTING_ID" != "null" ]]; then
                    PROPOSED_MILESTONE_ID="$EXISTING_ID"
                    PROPOSED_TITLE="$SUGGEST_TITLE"
                    AUTO_ASSIGN="true"
                    log_info "[$COUNTER/$ISSUE_COUNT] #$NUMBER: Found existing milestone '$SUGGEST_TITLE' (#$EXISTING_ID)"
                else
                    # Create new milestone
                    log_info "[$COUNTER/$ISSUE_COUNT] #$NUMBER: Creating new milestone: $SUGGEST_TITLE"
                    CREATE_RESP=$(gh api -X POST "repos/$REPO/milestones" -f title="$SUGGEST_TITLE" -f description="Auto-created by PMO AI" 2>/dev/null || echo "")
                    NEW_ID=$(echo "$CREATE_RESP" | jq -r '.number' 2>/dev/null || echo "")
                    if [[ -n "$NEW_ID" && "$NEW_ID" != "null" ]]; then
                        PROPOSED_MILESTONE_ID="$NEW_ID"
                        PROPOSED_TITLE="$SUGGEST_TITLE"
                        AUTO_ASSIGN="true"
                        log_info "[$COUNTER/$ISSUE_COUNT] #$NUMBER: Created milestone '$SUGGEST_TITLE' (#$NEW_ID)"
                        echo "{\"timestamp\":\"$(date -u +%FT%T.000Z)\",\"issue\":$NUMBER,\"decision\":\"CREATE_MILESTONE\",\"milestone_title\":\"$SUGGEST_TITLE\",\"milestone_id\":$NEW_ID}" >> "$DECISION_LOG"
                    else
                        log_warn "[$COUNTER/$ISSUE_COUNT] #$NUMBER: AI suggested milestone but creation failed; defaulting to backlog"
                        PROPOSED_MILESTONE_ID=28
                        PROPOSED_TITLE="Project Eta: Backlog"
                    fi
                fi
            else
                log_warn "[$COUNTER/$ISSUE_COUNT] #$NUMBER: AI returned no suggestion; defaulting to backlog"
                PROPOSED_MILESTONE_ID=28
                PROPOSED_TITLE="Project Eta: Backlog"
            fi
        fi

# TOPIC COHERENCE LAYER (Ruthless & Aggressive Mode)
        if [[ ("$RUTHLESS" == "true" || "$AGGRESSIVE_MODE" == "true") && -n "$CURRENT_MILESTONE" ]]; then
            COHERENCE_RESULT=$(echo "$ISSUE_JSON" | python3 "$SCRIPT_DIR/topic_coherence_validator.py" 2>/dev/null || echo "{\"coherence_score\": 1.0, \"is_coherent\": true}")
            IS_COHERENT=$(echo "$COHERENCE_RESULT" | jq -r '.is_coherent // true')
            SCORE=$(echo "$COHERENCE_RESULT" | jq -r '.coherence_score // 1.0')

            if [[ "$IS_COHERENT" == "true" && "$PROPOSED_MILESTONE_ID" == "$CURRENT_MILESTONE" ]]; then
                log_info "[$COUNTER/$ISSUE_COUNT] #$NUMBER: Coherence verified ($SCORE) in $(echo "$ISSUE_JSON" | jq -r '.current_milestone_title')"
                continue
            fi

            # Phase 6: In aggressive mode, force realignment for low coherence
            if [[ "$AGGRESSIVE_MODE" == "true" && "$FORCE_REALIGN" == "true" ]] && (( $(echo "$SCORE < $REALIGN_OVERRIDE" | bc -l) )); then
                if [[ "$PROPOSED_MILESTONE_ID" != "$CURRENT_MILESTONE" ]]; then
                    log_warn "[$COUNTER/$ISSUE_COUNT] #$NUMBER: FORCED REALIGNMENT! Coherence $SCORE < $REALIGN_OVERRIDE. Moving $CURRENT_MILESTONE → $PROPOSED_TITLE"
                    AUTO_ASSIGN="true"
                    ((TOTAL_FORCED_REALIGN++)) || true

                    # Log decision for NIST-PM-5 audit
                    echo "{\"timestamp\":\"$(date -u +%FT%T.000Z)\",\"issue\":$NUMBER,\"decision\":\"FORCED_REALIGN\",\"old_milestone\":$CURRENT_MILESTONE,\"new_milestone\":$PROPOSED_MILESTONE_ID,\"coherence\":$SCORE,\"reason\":\"Coherence threshold breach\"}" >> "$DECISION_LOG"
                fi
            elif [[ "$PROPOSED_MILESTONE_ID" != "$CURRENT_MILESTONE" ]]; then
                log_warn "[$COUNTER/$ISSUE_COUNT] #$NUMBER: Topic drift detected! Coherence $SCORE. Considering: $PROPOSED_TITLE"
            fi
        fi

        # Skip if already in the proposed milestone (non-ruthless)
        if [[ "$RUTHLESS" == "false" && "$PROPOSED_MILESTONE_ID" == "$CURRENT_MILESTONE" ]]; then
            log_info "[$COUNTER/$ISSUE_COUNT] #$NUMBER: Already correctly assigned to $PROPOSED_TITLE"
            continue
        fi

        # If it's a closed issue and not ruthless, skip if already assigned
        if [[ "$STATE" == "closed" && -n "$CURRENT_MILESTONE" && "$RUTHLESS" == "false" ]]; then
            log_info "[$COUNTER/$ISSUE_COUNT] #$NUMBER: Closed and already has milestone - skipping re-organization (use --ruthless to override)"
            continue
        fi

        # Only auto-assign if confidence is high (95%+ by default in rules)
        # In ruthless aggressive mode, assign if confidence > 0.5, or to backlog if < 0.5
        if [[ "$AUTO_ASSIGN" != "true" && "$RUTHLESS" == "true" && "$AGGRESSIVE_MODE" == "true" ]]; then
            if (( $(echo "$CONFIDENCE >= 0.5" | bc -l) )); then
                log_warn "[$COUNTER/$ISSUE_COUNT] #$NUMBER: Low confidence ($CONFIDENCE) but assigning in ruthless aggressive mode"
                AUTO_ASSIGN="true"
            else
                log_warn "[$COUNTER/$ISSUE_COUNT] #$NUMBER: Very low confidence ($CONFIDENCE), assigning to backlog"
                PROPOSED_MILESTONE_ID=28
                PROPOSED_TITLE="Project Eta: Backlog"
                AUTO_ASSIGN="true"
            fi
        elif [[ "$AUTO_ASSIGN" != "true" ]]; then
            log_warn "[$COUNTER/$ISSUE_COUNT] #$NUMBER: Low confidence ($CONFIDENCE) for $PROPOSED_TITLE - needs manual oversight"

            # If it CURRENTLY has no milestone, force it to Backlog instead of leaving it empty
            if [[ -z "$CURRENT_MILESTONE" || "$CURRENT_MILESTONE" == "null" ]]; then
                log_info "[$COUNTER/$ISSUE_COUNT] #$NUMBER: Forcing assignment to Backlog (#28) to satisfy governance"
                PROPOSED_MILESTONE_ID=28
                PROPOSED_TITLE="Project Eta: Backlog"
            else
                continue
            fi
        fi

        STATE_MSG=""
        [[ "$STATE" == "closed" ]] && STATE_MSG=" (Closed)"

        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[$COUNTER/$ISSUE_COUNT] #$NUMBER$STATE_MSG: [DRY RUN] Would move → $PROPOSED_TITLE (#$PROPOSED_MILESTONE_ID)"
            ((BATCH_REMEDIATED++)) || true
            continue
        fi

        # Apply milestone via REST API
        if gh_api_retry gh api -X PATCH "repos/$REPO/issues/$NUMBER" -f milestone="$PROPOSED_MILESTONE_ID" >/dev/null 2>&1; then
            log_info "[$COUNTER/$ISSUE_COUNT] #$NUMBER$STATE_MSG: Re-organized → $PROPOSED_TITLE (#$PROPOSED_MILESTONE_ID) [Conf: $CONFIDENCE]"
            ((BATCH_REMEDIATED++)) || true
            ((TOTAL_REMEDIATED++)) || true
        else
            log_error "[$COUNTER/$ISSUE_COUNT] #$NUMBER$STATE_MSG: Failed to assign milestone (#$PROPOSED_MILESTONE_ID)"
        fi
    done < "$TMP_JSON"

    rm -f "$TMP_JSON"
    log_success "Completed: $BATCH_REMEDIATED/$ISSUE_COUNT $STATE issues (Forced realignments: $TOTAL_FORCED_REALIGN)"
done

log_header "Enforcement Complete"
log_success "Total Issues Scanned: $TOTAL_SCANNED"
log_success "Total Issues Remediated: $TOTAL_REMEDIATED"
if [[ "$AGGRESSIVE_MODE" == "true" ]]; then
    log_success "Forced Realignments (Phase 6): $TOTAL_FORCED_REALIGN"
    log_info "Decision audit log: $DECISION_LOG"
fi

# Final verification
log_info "Running final verification..."
OPEN_REMAINING=$(gh issue list --repo "$REPO" --state open --limit 100 --json "number,milestone" \
    | jq '[.[] | select(.milestone == null)] | length' 2>/dev/null || echo "?")
CLOSED_REMAINING=$(gh issue list --repo "$REPO" --state closed --limit 100 --json "number,milestone" \
    | jq '[.[] | select(.milestone == null)] | length' 2>/dev/null || echo "?")

log_info "Open issues without milestones remaining: $OPEN_REMAINING"
log_info "Closed issues without milestones remaining: $CLOSED_REMAINING"

if [[ "$OPEN_REMAINING" == "0" ]] && [[ "$CLOSED_REMAINING" == "0" ]]; then
    log_success "PERFECT - ALL ISSUES HAVE MILESTONES!"
else
    log_warn "Some issues still lack milestones ($OPEN_REMAINING open, $CLOSED_REMAINING closed)"
fi

# Phase 6: Summary statistics
if [[ "$AGGRESSIVE_MODE" == "true" ]] && [[ -f "$DECISION_LOG" ]]; then
    REMEDIATION_RATIO=$(( (TOTAL_REMEDIATED + TOTAL_FORCED_REALIGN) * 100 / TOTAL_SCANNED ))
    log_success ""
    log_success "Phase 6 Aggressive Mode Summary"
    log_info "  Total Scanned: $TOTAL_SCANNED"
    log_info "  Auto-Assigned: $TOTAL_REMEDIATED"
    log_info "  Forced Realignments: $TOTAL_FORCED_REALIGN"
    log_info "  Remediation Rate: ${REMEDIATION_RATIO}%"
    log_info "  Decision Log: $DECISION_LOG"
fi

exit 0
