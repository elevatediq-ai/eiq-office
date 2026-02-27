#!/bin/bash

################################################################################
# 🤖 Issue Auto-Categorization Framework
# Purpose: Automatically categorize and label GitHub issues for compliance
# Usage: ./issue_auto_categorizer.sh [--scan-all | --watch | --repo <repo>]
# Refs: #2747 - Issue Auto-Categorization Framework
################################################################################

set -euo pipefail

REPO="${REPO:-kushin77/ElevatedIQ-Mono-Repo}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/auto_categorizer.log"
RULES_FILE="${SCRIPT_DIR}/../config/categorization_rules.json"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

################################################################################
# Logging Functions
################################################################################

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $*" | tee -a "$LOG_FILE"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOG_FILE"
}

################################################################################
# Auto-Categorization Rules
################################################################################

# Infer issue type from title and body
infer_type() {
    local title="$1"
    local body="${2:-}"
    local type=""

    # Pattern matching for common keywords
    if echo "$title" | grep -qEi "(fix|bug|issue|broken|crash|error|regression)"; then
        type="bug"
    elif echo "$title" | grep -qEi "(feat|feature|new|add|implement|capability)"; then
        type="feature"
    elif echo "$title" | grep -qEi "(improve|enhance|optimize|refactor|performance)"; then
        type="enhancement"
    elif echo "$title" | grep -qEi "(security|vulnerability|cve|patch|hardening|threat)"; then
        type="security"
    elif echo "$title" | grep -qEi "(doc|documentation|readme|guide|runbook|wiki)"; then
        type="docs"
    elif echo "$title" | grep -qEi "(terraform|infra|infrastructure|deploy|cloud|kubernetes|k8s)"; then
        type="ops"
    elif echo "$title" | grep -qEi "(outage|incident|sev-1|p0|critical|urgent)"; then
        type="incident"
    elif echo "$title" | grep -qEi "(epic|milestone|phase|roadmap|plan)"; then
        type="epic"
    else
        # Check body for clues
        if echo "$body" | grep -qEi "(acceptance criteria|ac:|must|should)"; then
            type="task"
        else
            type="task"
        fi
    fi

    echo "$type"
}

# Infer priority from title and labels
infer_priority() {
    local title="$1"
    local current_labels="${2:-}"
    local priority=""

    # Check for existing priority labels
    if echo "$current_labels" | grep -q "priority:"; then
        return 0  # Already has priority
    fi

    # Pattern matching
    if echo "$title" | grep -qEi "(blocker|critical|urgent|blocking|must|p0|sev-1)"; then
        priority="priority: P0"
    elif echo "$title" | grep -qEi "(high|important|asap|next|p1)"; then
        priority="priority: P1"
    elif echo "$title" | grep -qEi "(medium|medium|moderate|p2)"; then
        priority="priority: P2"
    else
        priority="priority: P2"  # Default to P2
    fi

    echo "$priority"
}

# Infer phase from title and body
infer_phase() {
    local title="$1"
    local body="${2:-}"
    local phase=""

    if echo "$title" | grep -qEi "(foundation|bootstrap|setup)"; then
        phase="phase: foundation"
    elif echo "$title" | grep -qEi "(pmo|automation|intelligence)"; then
        phase="phase: 2"
    elif echo "$title" | grep -qEi "(fedramp|compliance|control|nist)"; then
        phase="phase: 3"
    elif echo "$title" | grep -qEi "(ai|ml|agent|autonomous)"; then
        phase="phase: 4"
    else
        phase="phase: 2"  # Default to current phase
    fi

    echo "$phase"
}

# Check for NIST control reference
extract_nist_controls() {
    local body="$1"
    local controls=""

    # Find NIST control references (e.g., NIST-AC-2, NIST-SC-7)
    controls=$(echo "$body" | grep -oE '\[?NIST-[A-Z]{2}-[0-9]{1,2}\]?' | sort -u | tr '\n' ' ' || true)

    if [ -z "$controls" ]; then
        controls="NIST-PM-5"  # Default PMO control
    fi

    echo "$controls"
}

################################################################################
# GitHub API Functions
################################################################################

# Get uncategorized issues
get_uncategorized_issues() {
    local limit="${1:-50}"

    log_info "Fetching uncategorized issues (limit: $limit)..."

    # Query for issues missing required labels
    gh issue list \
        --repo "$REPO" \
        --state open \
        --limit "$limit" \
        --json number,title,body,labels \
        --search 'label:"-type:*"' 2>/dev/null || echo "[]"
}

# Categorize a single issue
categorize_issue() {
    local issue_number="$1"
    local title="$2"
    local body="$3"
    local current_labels="$4"

    log_info "Categorizing issue #$issue_number: $title"

    # Infer dimensions
    local inferred_type=$(infer_type "$title" "$body")
    local inferred_priority=$(infer_priority "$title" "$current_labels")
    local inferred_phase=$(infer_phase "$title" "$body")
    local nist_controls=$(extract_nist_controls "$body")

    # Prepare labels
    local labels_to_add=("type: $inferred_type" "$inferred_priority" "$inferred_phase")

    # Add NIST control if needed
    if [ -n "$nist_controls" ]; then
        labels_to_add+=("$nist_controls")
    fi

    # Apply labels via GitHub API
    for label in "${labels_to_add[@]}"; do
        if ! echo "$current_labels" | grep -q "$label"; then
            log_info "  Adding label: $label"
            gh issue edit "$issue_number" \
                --repo "$REPO" \
                --add-label "$label" 2>/dev/null || log_warn "Failed to add label: $label"
        fi
    done

    log_success "Issue #$issue_number categorized"
}

################################################################################
# Compliance Checking
################################################################################

# Validate issue compliance with taxonomy
validate_issue_compliance() {
    local issue_number="$1"
    local labels="$2"
    local title="$3"

    local has_type=false
    local has_priority=false
    local has_phase=false
    local violations=()

    # Check required labels
    if echo "$labels" | grep -q "type:"; then
        has_type=true
    else
        violations+=("Missing 'type:*' label")
    fi

    if echo "$labels" | grep -q "priority:"; then
        has_priority=true
    else
        violations+=("Missing 'priority:*' label")
    fi

    if echo "$labels" | grep -q "phase:"; then
        has_phase=true
    else
        violations+=("Missing 'phase:*' label")
    fi

    # Report violations
    if [ ${#violations[@]} -gt 0 ]; then
        log_warn "Issue #$issue_number VIOLATIONS:"
        for violation in "${violations[@]}"; do
            echo "    - $violation" | tee -a "$LOG_FILE"
        done
        return 1
    else
        log_success "Issue #$issue_number compliant"
        return 0
    fi
}

################################################################################
# Main Operations
################################################################################

# Scan and categorize all open issues
scan_all_issues() {
    log_info "🔍 Starting full issue scan..."

    local total_scanned=0
    local total_categorized=0
    local total_violations=0

    # Get all open issues in batches
    local cursor=""
    while true; do
        log_info "Fetching batch (cursor: ${cursor:0:20}...)..."

        # Fetch batch of issues
        local batch=$(gh issue list \
            --repo "$REPO" \
            --state open \
            --limit 100 \
            --json number,title,body,labels \
            2>/dev/null || echo "[]")

        if [ "$(echo "$batch" | jq 'length')" -eq 0 ]; then
            break
        fi

        # Process each issue
        echo "$batch" | jq -r '.[] | "\(.number)|\(.title)|\(.body)|\(.labels | map(.name) | join(","))"' | while IFS='|' read -r number title body labels; do
            ((total_scanned++))

            # Check if already categorized
            if echo "$labels" | grep -q "type:"; then
                validate_issue_compliance "$number" "$labels" "$title"
            else
                categorize_issue "$number" "$title" "$body" "$labels"
                ((total_categorized++))
            fi
        done

        # Check for more pages
        break  # Simplified - just process one batch
    done

    log_info "📊 Scan complete: $total_scanned scanned, $total_categorized categorized"
}

# Watch and auto-categorize newly created issues
watch_issues() {
    log_info "👁️  Watching for new issues (watching mode)..."
    log_info "Press Ctrl+C to stop watching"

    # Poll every 30 seconds
    while true; do
        log_info "Polling for new uncategorized issues..."

        gh issue list \
            --repo "$REPO" \
            --state open \
            --limit 10 \
            --json number,title,body,labels \
            --search '-label:"type:*"' 2>/dev/null | \
        jq -r '.[] | "\(.number)|\(.title)|\(.body)|\(.labels | map(.name) | join(","))"' | \
        while IFS='|' read -r number title body labels; do
            if [ -n "$number" ]; then
                categorize_issue "$number" "$title" "$body" "$labels"
            fi
        done

        log_info "Next poll in 30 seconds..."
        sleep 30
    done
}

# Generate compliance report
generate_compliance_report() {
    log_info "📋 Generating compliance report..."

    local total_issues=$(gh issue list --repo "$REPO" --state open --json number --jq 'length')
    local compliant_issues=0
    local non_compliant_issues=0

    # Sample first 100 issues
    gh issue list \
        --repo "$REPO" \
        --state open \
        --limit 100 \
        --json number,title,labels 2>/dev/null | \
    jq -r '.[] | "\(.number)|\(.labels | map(.name) | join(","))"' | \
    while IFS='|' read -r number labels; do
        if validate_issue_compliance "$number" "$labels" "" > /dev/null 2>&1; then
            ((compliant_issues++))
        else
            ((non_compliant_issues++))
        fi
    done

    local compliance_rate=$((compliant_issues * 100 / (compliant_issues + non_compliant_issues)))

    cat <<EOF | tee -a "$LOG_FILE"

## 📋 Issue Compliance Report

| Metric | Value |
|--------|-------|
| **Total Open Issues** | $total_issues |
| **Sampled Issues** | $((compliant_issues + non_compliant_issues)) |
| **Compliant Issues** | $compliant_issues |
| **Non-Compliant Issues** | $non_compliant_issues |
| **Compliance Rate** | $compliance_rate% |

### Compliance Status
$([ "$compliance_rate" -ge 90 ] && echo "✅ **COMPLIANT** (≥90%)" || echo "⚠️  **NEEDS ENFORCEMENT** (<90%)")

EOF
}

################################################################################
# Main Entry Point
################################################################################

main() {
    log_info "🤖 Issue Auto-Categorizer Framework v1.0"
    log_info "Repository: $REPO"

    case "${1:-scan-all}" in
        scan-all)
            scan_all_issues
            generate_compliance_report
            ;;
        watch)
            watch_issues
            ;;
        report)
            generate_compliance_report
            ;;
        *)
            echo "Usage: $0 [scan-all | watch | report]"
            echo ""
            echo "Commands:"
            echo "  scan-all   - Scan and categorize all uncategorized issues"
            echo "  watch      - Watch for new issues and auto-categorize them"
            echo "  report     - Generate compliance report"
            exit 1
            ;;
    esac

    log_success "Operation complete"
}

# Run main
main "$@"
