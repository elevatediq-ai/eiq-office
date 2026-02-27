#!/bin/bash

################################################################################
# 🎯 PRODUCTION: Batch Milestone Assignment - Elite PMO Automation
# Issue: #2830 - Auto-assign milestones & projects to all GitHub issues
# Purpose: 1000X process improvement through intelligent batch automation
# Strategy: Batch 10 (test) → 100 (validate) → 500 (scale) → ALL (complete)
################################################################################

set -eo pipefail

REPO="kushin77/ElevatedIQ-Mono-Repo"
BATCH_SIZE="${1:-10}"
TEMP_DIR="/tmp/pmo_milestone_batch"
PROCESSED_FILE="$TEMP_DIR/processed.txt"
RESULTS_CSV="$TEMP_DIR/results.csv"
LOG_FILE="docs/management/milestone-batch-log.md"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

# Initialize
mkdir -p "$TEMP_DIR"
touch "$PROCESSED_FILE"
> "$RESULTS_CSV"
echo "issue_number,milestone,title,attempt" > "$RESULTS_CSV"

# Stats
TOTAL=0 SUCCESSFUL=0 FAILED=0
M_AI=0 M_INFRA=0 M_SEC=0 M_FINOPS=0

# Milestone title mapping
select_milestone_title() {
    local title="$1"

    if echo "$title" | grep -qi "infrastructure\|terraform\|iac\|deployment\|k8s\|kubernetes\|scaling\|failover\|resilience\|monitoring\|alerting\|observability\|performance\|optimization"; then
        echo "Project Gamma: Infrastructure"
    elif echo "$title" | grep -qi "security\|auth\|encryption\|compliance\|fedramp\|audit\|cve\|threat\|vulnerability\|incident\|response"; then
        echo "Project Delta: Security"
    elif echo "$title" | grep -qi "cost\|finops\|billing\|savings\|budget\|optimization\|expense"; then
        echo "Project Sigma: FinOps"
    else
        echo "Project Beta: AI Intelligence"
    fi
}

# Assign milestone by TITLE
assign_milestone() {
    local issue_num=$1
    local milestone_title="$2"

    if gh issue edit "$issue_num" --repo "$REPO" --milestone "$milestone_title" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Process single batch
process_batch() {
    local batch_num=$1
    local all_issues_file=$2

    local start_idx=$(( (batch_num - 1) * BATCH_SIZE ))
    local end_idx=$(( start_idx + BATCH_SIZE ))

    echo -e "\n${CYAN}┌─────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│${NC} ${YELLOW}Batch #$batch_num${NC} (Issues #$start_idx to #$((end_idx-1)))${CYAN} │${NC}"
    echo -e "${CYAN}└─────────────────────────────────────────────────────┘${NC}\n"

    local total=$(jq 'length' "$all_issues_file")

    if [[ $start_idx -ge $total ]]; then
        return 1
    fi

    [[ $end_idx -gt $total ]] && end_idx=$total

    local count=$(( end_idx - start_idx ))
    local batch_successful=0
    local batch_failed=0

    echo -e "${BLUE}Processing $count issues...${NC}\n"

    for i in $(seq $start_idx $(( end_idx - 1 ))); do
        local issue_num=$(jq -r ".[$i].number" "$all_issues_file")
        local issue_title=$(jq -r ".[$i].title" "$all_issues_file")

        if [[ -z "$issue_num" ]] || [[ "$issue_num" == "null" ]]; then
            continue
        fi

        ((TOTAL++))

        if grep -q "^$issue_num," "$PROCESSED_FILE" 2>/dev/null; then
            continue
        fi

        local milestone_title=$(select_milestone_title "$issue_title")

        if assign_milestone "$issue_num" "$milestone_title"; then
            echo -e "${GREEN}✅${NC} #$issue_num → $(echo "$milestone_title" | cut -d: -f1)"
            echo "$issue_num,$milestone_title,${issue_title:0:80},success" >> "$PROCESSED_FILE"
            ((SUCCESSFUL++))
            ((batch_successful++))

            # Track distribution
            if echo "$milestone_title" | grep -q "AI"; then ((M_AI++)); fi
            if echo "$milestone_title" | grep -q "Infrastructure"; then ((M_INFRA++)); fi
            if echo "$milestone_title" | grep -q "Security"; then ((M_SEC++)); fi
            if echo "$milestone_title" | grep -q "FinOps"; then ((M_FINOPS++)); fi
        else
            echo -e "${RED}❌${NC} #$issue_num → Failed"
            echo "$issue_num,$milestone_title,${issue_title:0:80},failed" >> "$PROCESSED_FILE"
            ((FAILED++))
            ((batch_failed++))
        fi

        sleep 0.3
    done

    echo ""
    echo -e "${CYAN}Batch Summary: ${GREEN}$batch_successful successful${NC}, ${RED}$batch_failed failed${NC}"
    return 0
}

# Main
main() {
    echo -e "${BLUE}╔═════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  🎯 Elite PMO: Batch Milestone Assignment                  ║${NC}"
    echo -e "${BLUE}║  Issue #2830: Auto-assign milestones to ALL issues        ║${NC}"
    echo -e "${BLUE}║  Strategy: 10 → 100 → 500 → ALL                           ║${NC}"
    echo -e "${BLUE}║  Batch Size: $BATCH_SIZE                                            ║${NC}"
    echo -e "${BLUE}╚═════════════════════════════════════════════════════════════╝${NC}\n"

    echo -e "${CYAN}Available Milestones:${NC}"
    gh api repos/$REPO/milestones 2>/dev/null | jq -r '.[] | select(.state=="open") | "  • \(.title)"' | head -5
    echo ""

    # Fetch all issues
    local all_issues_file="$TEMP_DIR/all_issues.json"
    echo -e "${BLUE}📥 Fetching all issues from repository...${NC}"

    if ! gh issue list --repo "$REPO" --state all --json number,title --limit 1000 2>/dev/null > "$all_issues_file"; then
        echo -e "${RED}Failed to fetch issues${NC}"
        return 1
    fi

    local total_issues=$(jq 'length' "$all_issues_file")
    echo -e "${GREEN}✅ Fetched $total_issues issues${NC}\n"

    echo "# 🎯 Milestone Batch Assignment Log" > "$LOG_FILE"
    echo "**Issue**: #2830" >> "$LOG_FILE"
    echo "**Started**: $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$LOG_FILE"
    echo "**Total Issues**: $total_issues" >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"

    local max_batches=1
    if [[ "$BATCH_SIZE" == "all" ]]; then
        BATCH_SIZE=10
        ((max_batches = (total_issues / BATCH_SIZE) + (total_issues % BATCH_SIZE > 0 ? 1 : 0)))
        echo -e "${YELLOW}🚀 Processing ALL $total_issues issues (~$max_batches batches)${NC}\n"
    elif [[ "$BATCH_SIZE" == "100" ]]; then
        ((max_batches = (total_issues / 100) + 1))
    elif [[ "$BATCH_SIZE" == "500" ]]; then
        ((max_batches = (total_issues / 500) + 1))
    fi

    for batch in $(seq 1 $max_batches); do
        if ! process_batch "$batch" "$all_issues_file"; then
            break
        fi
        [[ $batch -lt $max_batches ]] && sleep 3
    done

    echo -e "\n${BLUE}═════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}✅ BATCH PROCESSING COMPLETE${NC}"
    echo -e "${BLUE}═════════════════════════════════════════════════════════════${NC}\n"

    local percent=0
    [[ $TOTAL -gt 0 ]] && percent=$(( (SUCCESSFUL * 100) / TOTAL ))

    echo -e "${YELLOW}📊 STATISTICS: Total=$TOTAL | Success=$SUCCESSFUL ($percent%) | Failed=$FAILED${NC}\n"
    echo -e "${YELLOW}🎯 DISTRIBUTION: AI=$M_AI | Infra=$M_INFRA | Security=$M_SEC | FinOps=$M_FINOPS${NC}\n"

    cat >> "$LOG_FILE" <<EOF

## Results
- Total Processed: $TOTAL
- Successful: $SUCCESSFUL ($percent%)
- Failed: $FAILED
- AI: $M_AI | Infrastructure: $M_INFRA | Security: $M_SEC | FinOps: $M_FINOPS
- Completed: $(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

    [[ -f ./scripts/pmo/session_tracker.sh ]] && ./scripts/pmo/session_tracker.sh update issue "✅ Milestone batch: $SUCCESSFUL/$TOTAL assigned" 2>/dev/null || true

    # Clean up AFTER all processing done
    rm -f "$all_issues_file"

    echo -e "${YELLOW}📁 Log: $LOG_FILE${NC}"
    echo -e "${YELLOW}📁 CSV: $RESULTS_CSV${NC}"
}

main "$@"
