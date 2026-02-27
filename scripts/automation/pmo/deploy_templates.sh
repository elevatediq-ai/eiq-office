#!/bin/bash

# Repo-Hygiene Template Deployment Script
# Deploys Dockerfile, Makefile, and .env.example templates across apps/
# References: Issue #3251 - Repo-Hygiene Compliance
# Author: GitHub Copilot
# Date: 2026-02-03

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEMPLATES_DIR="$SCRIPT_DIR/templates"
APPS_DIR="$REPO_ROOT/apps"

# Color codes for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo "🧹 Repo-Hygiene Template Deployment"
echo "=================================="
echo "Templates dir: $TEMPLATES_DIR"
echo "Apps dir: $APPS_DIR"
echo ""

# Verify templates exist
if [[ ! -f "$TEMPLATES_DIR/Dockerfile.tpl" ]] || [[ ! -f "$TEMPLATES_DIR/Makefile.tpl" ]] || [[ ! -f "$TEMPLATES_DIR/.env.example.tpl" ]]; then
    echo -e "${RED}❌ Templates not found in $TEMPLATES_DIR${NC}"
    echo "Expected files:"
    echo "  - Dockerfile.tpl"
    echo "  - Makefile.tpl"
    echo "  - .env.example.tpl"
    exit 1
fi

echo -e "${GREEN}✅ Templates verified${NC}"
echo ""

# Counter for tracking deployments
DEPLOYED=0
SKIPPED=0
FAILED=0

# List of apps to process (from issue #3251)
APPS_TO_PROCESS=(
    "aiops-engine"
    "alert-router"
    "anomaly-engine"
    "audit-logger"
    "audit-trail-integrity"
    "autonomous-ops-control-plane"
    "cache-pruner"
    "cache-service"
    "chaos-orchestrator"
    "compliance-monitor"
    "control-plane"
    "cost-framework"
    "cost-optimizer-lambda"
    "cost-remediation-worker"
    "cross-region-sync"
    "data-residency-service"
    "data-sovereignty-gateway"
    "disaster-recovery-orchestrator"
    "eiq-cli"
    "embedding-service"
    "executive-api"
    "executive-dashboards"
    "failover-simulator"
    "fedramp-boundary-automation"
    "finetuning-service"
    "finops-controller"
    "finops-dashboard-api"
    "frontend"
    "hub-core"
    "intelligence-api"
    "landing-zone-factory"
    "lsp-throttle-controller"
    "metrics-aggregator"
    "observability-dashboard"
    "pmo-extension"
    "pmo-orchestrator"
    "portal-api-gateway"
    "predictive-scaling-orchestrator"
    "rca-graph-service"
    "resilience-agent"
    "runtime-threat-detection"
    "scaling-agent"
)

# Process each app
for app in "${APPS_TO_PROCESS[@]}"; do
    app_dir="$APPS_DIR/$app"

    if [[ ! -d "$app_dir" ]]; then
        echo -e "${YELLOW}⊘ $app: directory not found${NC}"
        ((SKIPPED++))
        continue
    fi

    echo "📦 Processing: $app"

    # Deploy Dockerfile if it doesn't exist
    if [[ ! -f "$app_dir/Dockerfile" ]]; then
        cp "$TEMPLATES_DIR/Dockerfile.tpl" "$app_dir/Dockerfile"
        echo -e "  ${GREEN}✓${NC} Dockerfile deployed"
        ((DEPLOYED++))
    else
        echo "  ⊘ Dockerfile already exists"
    fi

    # Deploy Makefile if it doesn't exist
    if [[ ! -f "$app_dir/Makefile" ]]; then
        cp "$TEMPLATES_DIR/Makefile.tpl" "$app_dir/Makefile"
        echo -e "  ${GREEN}✓${NC} Makefile deployed"
        ((DEPLOYED++))
    else
        echo "  ⊘ Makefile already exists"
    fi

    # Deploy .env.example if it doesn't exist
    if [[ ! -f "$app_dir/.env.example" ]]; then
        cp "$TEMPLATES_DIR/.env.example.tpl" "$app_dir/.env.example"
        echo -e "  ${GREEN}✓${NC} .env.example deployed"
        ((DEPLOYED++))
    else
        echo "  ⊘ .env.example already exists"
    fi

    echo ""
done

echo "=================================="
echo -e "${GREEN}✅ Deployment Summary${NC}"
echo "  Files deployed: $DEPLOYED"
echo "  Apps skipped:   $SKIPPED"
echo ""
echo "🎯 Next steps:"
echo "  1. Review the deployed files in apps/"
echo "  2. Customize Dockerfile/Makefile per service requirements"
echo "  3. Commit changes with: git add apps/ && git commit -S -m 'chore(repo): [NIST-PM-5] deploy repo-hygiene templates Refs #3251'"
echo "  4. Push branch and create PR"
