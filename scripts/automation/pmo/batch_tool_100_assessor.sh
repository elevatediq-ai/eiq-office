#!/usr/bin/env bash
#
# Batch Tool-100 Assessor & Issue Updater
# Processes all Tool-100 EPIC issues and posts assessment results
#
# NIST Alignment: CM-8 (Component Inventory), PM-5 (System Inventory)
# Refs: #5264

set -euo pipefail

REPO="kushin77/ElevatedIQ-Mono-Repo"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ASSESSOR="$SCRIPT_DIR/tool_100_assessor.py"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"
}

success() {
    echo -e "${GREEN}✅ $*${NC}"
}

warn() {
    echo -e "${YELLOW}⚠️  $*${NC}"
}

error() {
    echo -e "${RED}❌ $*${NC}"
}

# Tool mapping from issue title to inventory data
# Format: "issue_number|tool_id|tool_name|score|repo_path"
declare -a TOOL_MAP=(
    "5265|ai-embedding-server|AI Embedding Server|88|apps/ai-embedding-server"
    "5266|ai-inference-server|AI Inference Server|92|apps/ai-inference-server"
    "5267|aiops-engine|AIOps Engine|85|apps/aiops-engine"
    "5268|agent-cicd|Agent CI/CD|84|apps/agent-cicd"
    "5269|alert-router|Alert Router|89|apps/alert-router"
    "5270|anomaly-engine|Anomaly Engine|82|apps/anomaly-engine"
    "5271|audit-logger|Audit Logger|96|apps/audit-logger"
    "5272|audit-trail-integrity|Audit Trail Integrity|88|apps/audit-trail-integrity"
    "5273|autonomous-ops|Autonomous Ops Control Plane|79|apps/autonomous-ops"
    "5274|chaos-orchestrator|Chaos Orchestrator|77|apps/chaos-orchestrator"
    "5275|cloud-analytics-bridge|Cloud Analytics Bridge|79|apps/cloud-analytics-bridge"
    "5276|compliance-monitor|Compliance Monitor|94|apps/compliance-monitor"
    "5277|cost-framework|Cost Framework|85|apps/cost-framework"
    "5278|cost-optimizer-lambda|Cost Optimizer Lambda|82|apps/cost-optimizer-lambda"
    "5279|data-sovereignty-gateway|Data Sovereignty Gateway|78|apps/data-sovereignty-gateway"
    "5280|deployment-agent|Deployment Agent|84|apps/deployment-agent"
    "5281|disaster-recovery-orchestrator|Disaster Recovery Orchestrator|86|apps/disaster-recovery-orchestrator"
    "5282|drift-dashboard|Drift Dashboard|83|apps/drift-dashboard"
    "5283|eiq-cli|EIQ CLI|90|apps/eiq-cli"
    "5284|edge-integrator-agent|Edge Integrator Agent|68|apps/edge-integrator-agent"
    "5285|portal|ElevatedIQ Portal|95|apps/portal"
    "5286|embedding-service|Embedding Service (Core Lib)|80|libs/embedding-service"
    "5287|executive-dashboards|Executive Dashboards|83|apps/executive-dashboards"
    "5288|failover-simulator|Failover Simulator|75|apps/failover-simulator"
    "5290|finops-controller|FinOps Controller|91|apps/finops-controller"
    "5291|finetuning-service|Fine-tuning Service|72|apps/finetuning-service"
    "5292|intelligence-api|Intelligence API|90|apps/intelligence_api"
    "5293|landing-zone-factory|Landing Zone Factory|93|apps/landing-zone-factory"
    "5294|m1-dqn-agent|M1 DQN Reinforcement Agent|70|apps/m1-dqn-agent"
    "5295|metrics-aggregator|Metrics Aggregator|87|apps/metrics-aggregator"
    "5297|observability-dashboard|Observability Dashboard|80|apps/observability-dashboard"
    "5298|observability|Observability Platform|90|apps/observability"
    "5299|pmo-health-monitor|PMO Health Monitor|82|apps/pmo-health-monitor"
    "5300|pmo-orchestrator|PMO Orchestrator|87|apps/pmo-orchestrator"
    "5304|resilience-agent|Resilience Agent|80|apps/resilience-agent"
    "5305|runtime-threat-detection|Runtime Threat Detection|84|apps/runtime-threat-detection"
    "5307|terraform-generator-api|Terraform Generator API|81|apps/terraform-generator-api"
    "5309|pmo-vscode-plugin|VS Code PMO Plugin|78|apps/pmo-vscode-plugin"
)

assess_and_update_issue() {
    local issue_number="$1"
    local tool_id="$2"
    local tool_name="$3"
    local score="$4"
    local repo_path="$5"

    log "Processing #${issue_number}: ${tool_name} (${tool_id})"

    # Run assessment (allow non-zero exit as gaps are expected)
    "$ASSESSOR" "$tool_id" "$tool_name" "$score" "$repo_path" || warn "Assessment found gaps for ${tool_id}"

    # Read generated comment
    local comment_file="$REPO_ROOT/reports/tool-assessments/${tool_id}-assessment.md"
    if [[ ! -f "$comment_file" ]]; then
        error "Assessment report not found: $comment_file"
        return 1
    fi

    # Post comment to GitHub issue
    log "Posting assessment to issue #${issue_number}..."
    if gh issue comment "$issue_number" --repo "$REPO" --body-file "$comment_file"; then
        success "Updated issue #${issue_number}"
    else
        error "Failed to update issue #${issue_number}"
        return 1
    fi

    echo ""
}

main() {
    log "🚀 Starting batch Tool-100 assessment..."
    log "Repository: $REPO"
    log "Tools to assess: ${#TOOL_MAP[@]}"
    echo ""

    local success_count=0
    local fail_count=0

    for tool_entry in "${TOOL_MAP[@]}"; do
        IFS='|' read -r issue_number tool_id tool_name score repo_path <<< "$tool_entry"

        if assess_and_update_issue "$issue_number" "$tool_id" "$tool_name" "$score" "$repo_path"; then
            ((success_count++))
        else
            ((fail_count++))
        fi

        # Rate limiting: pause between issues
        sleep 2
    done

    echo ""
    log "📊 Batch Assessment Complete"
    success "Successfully processed: $success_count"
    if [[ $fail_count -gt 0 ]]; then
        warn "Failed: $fail_count"
    fi

    # Generate summary report
    log "Generating summary report..."
    cat > "$REPO_ROOT/reports/tool-assessments/SUMMARY.md" <<EOF
# Tool-100 Batch Assessment Summary

**Date:** $(date -u '+%Y-%m-%d %H:%M UTC')
**Total Tools Assessed:** ${#TOOL_MAP[@]}
**Successful:** $success_count
**Failed:** $fail_count

##Individual Reports

\`\`\`bash
ls -1 reports/tool-assessments/*-assessment.md
\`\`\`

## Next Steps

1. Review individual tool reports in \`reports/tool-assessments/\`
2. Address identified gaps in priority order (lowest score first)
3. Re-run assessments as improvements are made
4. Update scores in \`apps/portal/src/data/toolsInventory.ts\`
5. Close Tool-100 EPIC issues when tools reach 100%

---
_Generated by \`scripts/pmo/batch_tool_100_assessor.sh\`_
EOF

    success "Summary report: reports/tool-assessments/SUMMARY.md"
}

main "$@"
