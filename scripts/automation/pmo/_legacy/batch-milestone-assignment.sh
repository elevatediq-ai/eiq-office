#!/bin/bash

################################################################################
# 🎯 Elite PMO: Batch Milestone & Project Assignment (PRODUCTION)
# Purpose: Intelligently assign milestones & projects to all GitHub issues
# Usage: ./batch-milestone-assignment.sh [batch_size]
# Batch Sizes: 10 (test), 100 (validate), 500 (scale), all (complete)
################################################################################

set -eo pipefail

REPO="kushin77/ElevatedIQ-Mono-Repo"
BATCH_SIZE="${1:-10}"
TEMP_DIR="/tmp/milestone_batch"
PROCESSED_FILE="$TEMP_DIR/processed.txt"
RESULTS_CSV="$TEMP_DIR/results.csv"
LOG_FILE="docs/management/batch-assignment-log.md"
ALL_ISSUES_FILE="$TEMP_DIR/all_issues.json"

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
echo "issue_number,milestone,title" > "$RESULTS_CSV"

# Stats
TOTAL=0 SUCCESSFUL=0 FAILED=0
M3=0 M4=0 M5=0 M6=0

# Select milestone based on title (RETURNS TITLE NOT NUMBER!)
select_milestone() {
    local title="$1"
    if echo "$title" | grep -qi "infrastructure\|terraform\|iac\|deployment\|k8s\|scaling\|failover\|resilience\|monitoring\|performance"; then
        echo "Project Gamma: Infrastructure"  # Use title
    elif echo "$title" | grep -qi "security\|auth\|encryption\|compliance\|fedramp\|audit\|cve\|threat"; then
        echo "Project Delta: Security"  # Use title
    elif echo "$title" | grep -qi "cost\|finops\|billing\|savings\|optimization\|budget"; then
        echo "Project Sigma: FinOps"  # Use title
    else
        echo "Project Beta: AI Intelligence"  # Default to title
    fi

# Assign milestone
assign_milestone() {
    local issue_num=$1 milestone=$2
    gh issue edit "$issue_num" --repo "$REPO" --milestone "$milestone" 2>/dev/null
}

# Fetch all issues once (no pagination issues)
fetch_all_issues() {
    echo -e "${BLUE}📥 Fetching all issues from repository...${NC}"
    gh issue list --repo "$REPO" --state all --json number,title --limit 1000 2>/dev/null > "$ALL_ISSUES_FILE" || {
        echo -e "${RED}Failed to fetch issues${NC}"
        return 1
    }
    local count=$(jq 'length' "$ALL_ISSUES_FILE")
    echo -e "${GREEN}✅ Fetched $count issues${NC}\n"
}

# Main processing
process_batch() {
    local batch_num=$1
    local start_idx=$(( (batch_num - 1) * BATCH_SIZE ))
    local end_idx=$(( start_idx + BATCH_SIZE ))

    echo -e "\n${CYAN}───────────────────────────────────────────${NC}"
    echo -e "${YELLOW}🚀 Batch #$batch_num (Issues $start_idx to $((end_idx-1)))${NC}"
    echo -e "${CYAN}───────────────────────────────────────────${NC}\n"

    # Get total count
    local total=$(jq 'length' "$ALL_ISSUES_FILE")

    if [[ $start_idx -ge $total ]]; then
        echo -e "${YELLOW}⚠️  No more issues to process${NC}"
        return 1
    fi

    # Adjust end_idx if it exceeds total
    if [[ $end_idx -gt $total ]]; then
        end_idx=$total
    fi

    local count=$(( end_idx - start_idx ))
    echo -e "${BLUE}Processing $count issues...${NC}\n"

    # Process each issue in this batch
    for i in $(seq $start_idx $(( end_idx - 1 ))); do
        local num=$(jq -r ".[$i].number" "$ALL_ISSUES_FILE")
        local title=$(jq -r ".[$i].title" "$ALL_ISSUES_FILE")

        if [[ -z "$num" ]] || [[ "$num" == "null" ]]; then
            continue
        fi

        ((TOTAL++))

        # Skip if already processed
        if grep -q "^$num$" "$PROCESSED_FILE"; then
            echo -e "⏭️  #$num - Already processed"
            continue
        fi

        # Get milestone
        local milestone=$(select_milestone "$title")

        # Assign (using milestone title)
        if assign_milestone "$num" "$milestone"; then
            echo -e "${GREEN}✅${NC} #$num → $milestone: ${title:0:50}"
            echo "$num" >> "$PROCESSED_FILE"
            echo "$num,$milestone,${title:0:80}" >> "$RESULTS_CSV"
            ((SUCCESSFUL++))
            # Track by milestone selected
            if echo "$milestone" | grep -q "Infrastructure"; then
                ((M4++))
            elif echo "$milestone" | grep -q "Security"; then
                ((M5++))
            elif echo "$milestone" | grep -q "FinOps"; then
                ((M6++))
            else
                ((M3++))
            fi
        else
            echo -e "${RED}❌${NC} #$num → Failed: ${title:0:50}"
            ((FAILED++))
        fi

        sleep 0.4  # Rate limit
    done

    return 0
}

# Main
main() {
    echo -e "${BLUE}╔─────────────────────────────────────────────────────────╗${NC}"
    echo -e "${BLUE}║  🎯 Batch Milestone & Project Assignment                ║${NC}"
    echo -e "${BLUE}║  Batch Size: $BATCH_SIZE                                          ║${NC}"
    echo -e "${BLUE}╚─────────────────────────────────────────────────────────╝${NC}\n"

    # Show milestones
    echo -e "${CYAN}Available Milestones:${NC}"
    gh api repos/$REPO/milestones --paginate 2>/dev/null | jq -r '.[] | "  [\(.number)] \(.title)"' | head -10
    echo ""

    # Fetch all issues
    if ! fetch_all_issues; then
        return 1
    fi

    # Get total
    local total_issues=$(jq 'length' "$ALL_ISSUES_FILE")

    # Initialize log
    echo "# 🎯 Batch Assignment Log" > "$LOG_FILE"
    echo "Started: $(date)" >> "$LOG_FILE"
    echo "Total Issues: $total_issues" >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"

    # Determine max batches
    local max_batches=1
    if [[ "$BATCH_SIZE" == "all" ]]; then
        BATCH_SIZE=10
        ((max_batches = (total_issues / BATCH_SIZE) + (total_issues % BATCH_SIZE > 0 ? 1 : 0)))
        echo -e "${YELLOW}Processing $total_issues issues in batches of 10 (~$max_batches batches)...${NC}\n"
    elif [[ "$BATCH_SIZE" == "100" ]]; then
        max_batches=$(( (total_issues / 100) + 1 ))
    elif [[ "$BATCH_SIZE" == "500" ]]; then
        max_batches=$(( (total_issues / 500) + 1 ))
    fi

    # Process batches
    for batch in $(seq 1 $max_batches); do
        if ! process_batch "$batch"; then
            break
        fi
        if [[ $batch -lt $max_batches ]]; then
            echo -e "${YELLOW}⏳ Pausing before next batch...${NC}"
            sleep 2
        fi
    done

    # Summary
    echo -e "\n${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}✅ COMPLETE${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}\n"

    local percent=0
    if [[ $TOTAL -gt 0 ]]; then
        percent=$(( (SUCCESSFUL * 100) / TOTAL ))
    fi

    echo -e "${YELLOW}📊 Statistics:${NC}"
    echo -e "  Total:      ${CYAN}$TOTAL${NC}"
    echo -e "  Successful: ${GREEN}$SUCCESSFUL${NC} ($percent%)"
    echo -e "  Failed:     ${RED}$FAILED${NC}"
    echo ""

    echo -e "${YELLOW}🎯 Milestone Breakdown:${NC}"
    echo -e "  [3] AI Intelligence: ${CYAN}$M3${NC} issues"
    echo -e "  [4] Infrastructure:  ${CYAN}$M4${NC} issues"
    echo -e "  [5] Security:        ${CYAN}$M5${NC} issues"
    echo -e "  [6] FinOps:          ${CYAN}$M6${NC} issues"
    echo ""

    echo -e "${YELLOW}📁 Results:${NC}"
    echo -e "  CSV: $RESULTS_CSV"
    echo -e "  Log: $LOG_FILE"
    echo -e "  Processed: $(wc -l < "$PROCESSED_FILE") unique issues"

    # Log results
    cat >> "$LOG_FILE" <<EOF

## Batch Summary
Batch Size: $BATCH_SIZE
Total Processed: $TOTAL
Successful: $SUCCESSFUL ($percent%)
Failed: $FAILED

## Milestone Distribution
- [3] AI Intelligence: $M3
- [4] Infrastructure: $M4
- [5] Security: $M5
- [6] FinOps: $M6

Completed: $(date)
EOF

    # Update session
    if [[ -f ./scripts/pmo/session_tracker.sh ]]; then
        ./scripts/pmo/session_tracker.sh update issue "✅ Batch milestone assignment complete: $SUCCESSFUL/$TOTAL" 2>/dev/null || true
    fi

    # Clean up temp files
    rm -f "$ALL_ISSUES_FILE"
}

main "$@"
