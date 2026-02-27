#!/usr/bin/env bash
# ==============================================================================
# 🌏 ElevatedIQ Global PMO Enforcer (10X Edition)
# ==============================================================================
# Purpose: Unified execution of all governance scripts with auto-remediation.
# NIST-800-53: PM-5, CM-3, AC-2 Aligned.
# ==============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONFIG_FILE="${REPO_ROOT}/configs/pmo/governance.json"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'

log() { echo -e "${BLUE}[$(date +%H:%M:%S)]${NC} $1"; }
header() { echo -e "\n${MAGENTA}=== $1 ===${NC}"; }

header "ElevatedIQ Global PMO Enforcement - Phase 10X"

# 1. Label Governance (Crucial for categorization)
log "Running Label Governance Enforcer..."
python3 "${REPO_ROOT}/scripts/pmo/label_governance_enforcer.py"

# 2. Assignee Enforcement (NIST-AC-2)
log "Running Assignee Enforcer (Batch Size 50)..."
DRY_RUN=false BATCH_SIZE=50 "${REPO_ROOT}/scripts/pmo/assignee_enforcer.sh"

# 3. Global Health Recalculation
log "Recalculating Global Workspace Health Score (GWHS)..."
python3 "${REPO_ROOT}/scripts/pmo/global_health_engine.py"

header "Enforcement Cycle Complete"
log "Updated Health Report: docs/management/GLOBAL_HEALTH_REPORT.md"
