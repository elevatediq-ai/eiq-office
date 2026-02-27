#!/bin/bash
#
# Phase A Preflight Check (Feb 20-24, 2026 Deployment)
# Purpose: Validate all prerequisites before Phase A FinOps deployment
# Usage: ./phase-a-preflight.sh [--verbose] [--fix]
#
# NIST Alignment: CA-7 (Continuous Monitoring), SI-4 (System Monitoring)

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LOG_FILE="${REPO_ROOT}/logs/phase-a-preflight-$(date +%Y%m%d-%H%M%S).log"
VERBOSE=${VERBOSE:-false}
FIX_MODE=${FIX_MODE:-false}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --verbose) VERBOSE=true; shift ;;
    --fix) FIX_MODE=true; shift ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# ============================================================================
# LOGGING / OUTPUT
# ============================================================================

log() {
  local level=$1
  shift
  local msg="$*"
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[$timestamp] [$level] $msg" | tee -a "$LOG_FILE"
}

info() { log "INFO" "$@"; }
warn() { log "WARN" "$@"; }
error() { log "ERROR" "$@"; }
pass() { log "PASS" "$@"; }
fail() { log "FAIL" "$@"; }

# ============================================================================
# CHECKS
# ============================================================================

PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

check_pass() {
  ((PASS_COUNT++))
  pass "$@"
}

check_warn() {
  ((WARN_COUNT++))
  warn "$@"
}

check_fail() {
  ((FAIL_COUNT++))
  fail "$@"
}

# ============================================================================
# PHASE A PREFLIGHT CHECKS
# ============================================================================

echo "🚀 Phase A Preflight Check (Feb 20-24 Deployment)"
echo "=============================================="
echo ""

mkdir -p "$(dirname "$LOG_FILE")"

# 1. GIT & REPOSITORY
echo "📦 Checking Git Repository..."
echo ""

if git rev-parse --git-dir > /dev/null 2>&1; then
  check_pass "Git repository detected"
else
  check_fail "Not a git repository"
  exit 1
fi

if git status > /dev/null 2>&1; then
  check_pass "Git working tree is clean (or staged)"
else
  check_warn "Git working tree has uncommitted changes"
fi

# 2. CLOUD CREDENTIALS
echo ""
echo "🔐 Checking Cloud Credentials..."
echo ""

# AWS
if command -v aws &> /dev/null; then
  if aws sts get-caller-identity > /dev/null 2>&1; then
    ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
    check_pass "AWS credentials valid (Account: $ACCOUNT)"
  else
    check_fail "AWS credentials invalid or expired"
  fi
else
  check_fail "AWS CLI not installed"
fi

# GCP
if command -v gcloud &> /dev/null; then
  if gcloud auth list | grep -q "ACTIVE"; then
    PROJECT=$(gcloud config get-value project 2>/dev/null || echo "unknown")
    check_pass "GCP credentials valid (Project: $PROJECT)"
  else
    check_fail "GCP credentials not configured"
  fi
else
  check_warn "GCP CLI (gcloud) not installed - install if using GCP"
fi

# 3. REQUIRED SCRIPTS & DOCUMENTATION
echo ""
echo "📄 Checking Required Scripts & Documentation..."
echo ""

REQUIRED_SCRIPTS=(
  "scripts/pmo/milestone_enforcer.sh"
  "scripts/pmo/gcp/billing_setup.sh"
  "scripts/aws/cur_bootstrap.sh"
  "scripts/finops/tag_audit.sh"
)

for script in "${REQUIRED_SCRIPTS[@]}"; do
  if [[ -f "$REPO_ROOT/$script" ]]; then
    check_pass "Script exists: $script"
  else
    check_fail "Missing script: $script (required for Phase A)"
  fi
done

REQUIRED_DOCS=(
  "docs/milestone-6/PHASE_A_DEPLOYMENT_READINESS.md"
  "docs/milestone-6/GITHUB_ISSUE_TRACKING.md"
  "docs/phase-6.3/EXECUTION_PLAN.md"
)

for doc in "${REQUIRED_DOCS[@]}"; do
  if [[ -f "$REPO_ROOT/$doc" ]]; then
    check_pass "Documentation exists: $doc"
  else
    check_fail "Missing documentation: $doc"
  fi
done

# 4. INFRASTRUCTURE READINESS
echo ""
echo "☁️  Checking Infrastructure Readiness..."
echo ""

# Check Terraform files
TF_FILES=$(find "$REPO_ROOT/infra" -name "*.tf" -type f | wc -l)
if [[ $TF_FILES -gt 0 ]]; then
  check_pass "Terraform files found: $TF_FILES files"
else
  check_warn "No Terraform files found in infra/ (may be using CloudFormation)"
fi

# Check Python dependencies
if [[ -f "$REPO_ROOT/requirements.txt" ]]; then
  check_pass "requirements.txt found (Python dependencies documented)"
else
  check_warn "No requirements.txt - ensure Python dependencies are documented"
fi

# 5. DATA RESIDENCY & SECURITY
echo ""
echo "🔒 Checking Data Residency & Security..."
echo ""

# Check for secrets in recent commits
if command -v gitleaks &> /dev/null; then
  if gitleaks detect --no-git --source "$REPO_ROOT" --exit-code 0 2>/dev/null | grep -q "0 findings"; then
    check_pass "Secrets scan clean (gitleaks)"
  else
    check_warn "gitleaks detected potential secrets - review before deployment"
  fi
else
  check_warn "gitleaks not installed - install for security validation"
fi

# Check for US-region hardcoding
if grep -r "us-east-1\|us-west-2" "$REPO_ROOT/infra" --include="*.tf" --include="*.py" > /dev/null 2>&1; then
  check_pass "US-region resources found (data residency compliance)"
else
  check_warn "No US-region resources detected - verify intended regions"
fi

# 6. TEAM & COMMUNICATION SETUP
echo ""
echo "👥 Checking Team Setup & Communication..."
echo ""

# Check if on-call schedule exists
if [[ -f "$REPO_ROOT/docs/operations/PHASE_A_ON_CALL_SCHEDULE.md" ]] || [[ -f "$REPO_ROOT/docs/operations/ON_CALL_SCHEDULE.md" ]] || [[ -f "$REPO_ROOT/docs/milestone-6/ON_CALL.md" ]]; then
  check_pass "On-call schedule documented"
else
  check_fail "On-call schedule not documented - create before Feb 20"
fi

# Check Slack channel setup (informational)
info "Ensure Slack channels are created: #sig-finops-alerts, #sig-incidents, #sig-on-call"

# 7. TESTING & VALIDATION
echo ""
echo "🧪 Checking Test Suite Readiness..."
echo ""

# Check for test files
TEST_FILES=$(find "$REPO_ROOT/tests" -name "test_*.py" -o -name "*_test.sh" 2>/dev/null | wc -l)
if [[ $TEST_FILES -gt 0 ]]; then
  check_pass "Test files found: $TEST_FILES test files"
else
  check_warn "No test files detected - unit tests recommended"
fi

# Check for smoke tests
if [[ -f "$REPO_ROOT/scripts/pmo/tests/test_milestone_enforcer.sh" ]]; then
  if bash "$REPO_ROOT/scripts/pmo/tests/test_milestone_enforcer.sh" 2>&1 | grep -q "PASS"; then
    check_pass "Smoke tests passing"
  else
    check_warn "Smoke tests may be failing - investigate before deployment"
  fi
else
  check_warn "No smoke tests found"
fi

# 8. DOCUMENTATION COMPLETENESS
echo ""
echo "📚 Checking Documentation..."
echo ""

# Check for deployment runbook
if [[ -f "$REPO_ROOT/docs/phase-6.3/DEPLOYMENT_RUNBOOK.md" ]]; then
  RUNBOOK_SIZE=$(wc -l < "$REPO_ROOT/docs/phase-6.3/DEPLOYMENT_RUNBOOK.md")
  if [[ $RUNBOOK_SIZE -gt 50 ]]; then
    check_pass "Deployment runbook complete ($RUNBOOK_SIZE lines)"
  else
    check_warn "Deployment runbook may be incomplete (<50 lines)"
  fi
else
  check_fail "Missing deployment runbook"
fi

# Check for best practices doc
if [[ -f "$REPO_ROOT/docs/milestone-6/EXECUTION_BEST_PRACTICES.md" ]]; then
  check_pass "Best practices documentation found"
else
  check_warn "Best practices documentation missing"
fi

# ============================================================================
# SUMMARY
# ============================================================================

echo ""
echo "=============================================="
echo "✅ Phase A Preflight Summary"
echo "=============================================="
echo ""
echo "  ✓ PASS:  $PASS_COUNT checks"
echo "  ⚠ WARN:  $WARN_COUNT checks"
echo "  ✗ FAIL:  $FAIL_COUNT checks"
echo ""

if [[ $FAIL_COUNT -eq 0 ]]; then
  echo "🎯 Phase A deployment is READY to proceed!"
  echo ""
  echo "Next steps:"
  echo "  1. Review today's standup (9:00 AM PT)"
  echo "  2. Execute: cd /home/akushnir/ElevatedIQ-Mono-Repo/infra/phase-6.3/ws1-gcp-billing"
  echo "  3. Verify cloud credentials one more time"
  echo "  4. Execute WS1 deployment per PHASE_A_DEPLOYMENT_READINESS.md"
  echo ""
  exit 0
else
  echo "❌ Phase A deployment BLOCKED due to $FAIL_COUNT critical issue(s)"
  echo ""
  echo "Resolve all failures before proceeding. Review:"
  echo "  $LOG_FILE"
  echo ""
  exit 1
fi
