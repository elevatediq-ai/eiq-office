#!/bin/bash
################################################################################
# Phase 6.3 GCP → GitHub Actions Secrets Setup
# Purpose: Retrieve GCP credentials from Secret Manager and configure GitHub
# Status: Production-Grade Automation (NIST-AC-2, NIST-IA-2)
# Author: Copilot Agent (GitHub)
# Date: 2026-02-17
################################################################################

set -euo pipefail
IFS=$'\n\t'

# ============================================================================
# CONFIGURATION
# ============================================================================

GCP_PROJECT="${GCP_PROJECT:-elevatediq-prod}"
GCP_SECRET_ID="${GCP_SECRET_ID:-terraform-provisioner-key}"
GITHUB_REPO="${GITHUB_REPO:-kushin77/ElevatedIQ-Mono-Repo}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/logs/setup_gcp_github_secrets_$(date +%Y%m%d-%H%M%S).log"

# Ensure log directory
mkdir -p "$(dirname "$LOG_FILE")"

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

log() {
  local level="$1"
  shift
  local msg="$*"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $msg" | tee -a "$LOG_FILE"
}

log_info() { log "INFO" "$@"; }
log_success() { log "✅ SUCCESS" "$@"; }
log_error() { log "❌ ERROR" "$@"; }
log_warning() { log "⚠️  WARNING" "$@"; }

# ============================================================================
# PREREQUISITE CHECKS
# ============================================================================

check_prerequisites() {
  log_info "Checking prerequisites..."

  # Check gh CLI
  if ! command -v gh &>/dev/null; then
    log_error "GitHub CLI (gh) not found. Please install: https://cli.github.com"
    return 1
  fi

  # Check gh auth
  if ! gh auth status >/dev/null 2>&1; then
    log_error "Not authenticated to GitHub. Run: gh auth login"
    return 1
  fi

  log_success "Prerequisites met (gh CLI ready)"
  return 0
}

# ============================================================================
# MAIN: Setup GCP Credentials
# ============================================================================

main() {
  log_info "======================================================================"
  log_info "Phase 6.3: GCP → GitHub Actions Secrets Setup"
  log_info "======================================================================"
  log_info "Project: $GCP_PROJECT"
  log_info "Secret ID: $GCP_SECRET_ID"
  log_info "Repository: $GITHUB_REPO"
  log_info ""

  # Step 1: Prerequisites
  if ! check_prerequisites; then
    log_error "Prerequisites check failed"
    return 1
  fi

  # Step 2: Retrieve GCP credentials
  log_info "Retrieving GCP credentials from Secret Manager..."
  log_info "  Command: gcloud secrets versions access latest --secret=$GCP_SECRET_ID --project=$GCP_PROJECT"

  local gcp_sa_key
  if gcp_sa_key=$(gcloud secrets versions access latest --secret="$GCP_SECRET_ID" --project="$GCP_PROJECT" 2>/dev/null); then
    log_success "Retrieved GCP service account credentials"
  else
    log_error "Failed to retrieve GCP credentials from Secret Manager"
    log_warning "Ensure you have gcloud CLI authenticated and permissions to access GSM"
    log_warning "Run: gcloud auth application-default login"
    return 1
  fi

  # Step 3: Validate JSON format
  log_info "Validating credential JSON format..."
  if echo "$gcp_sa_key" | python3 -m json.tool >/dev/null 2>&1; then
    log_success "Credentials are valid JSON"
  else
    log_error "Retrieved credentials are not valid JSON"
    return 1
  fi

  # Step 4: Extract key metadata
  local project_id service_account
  project_id=$(echo "$gcp_sa_key" | python3 -c "import sys, json; print(json.load(sys.stdin).get('project_id', 'UNKNOWN'))")
  service_account=$(echo "$gcp_sa_key" | python3 -c "import sys, json; print(json.load(sys.stdin).get('client_email', 'UNKNOWN'))")

  log_info "Credentials info:"
  log_info "  Project ID: $project_id"
  log_info "  Service Account: $service_account"

  # Step 5: Add to GitHub secrets
  log_info ""
  log_info "Adding credentials to GitHub repository secrets..."

  if gh secret set GCP_SA_KEY --repo="$GITHUB_REPO" --body "$gcp_sa_key" 2>&1 | tee -a "$LOG_FILE"; then
    log_success "GitHub secret GCP_SA_KEY updated"
  else
    log_error "Failed to set GitHub secret GCP_SA_KEY"
    return 1
  fi

  # Step 6: Add project ID
  log_info "Adding GCP project ID to GitHub secrets..."
  if gh secret set GCP_PROJECT --repo="$GITHUB_REPO" --body "$project_id" 2>&1 | tee -a "$LOG_FILE"; then
    log_success "GitHub secret GCP_PROJECT updated"
  else
    log_error "Failed to set GitHub secret GCP_PROJECT"
    return 1
  fi

  # Step 7: Verify secrets
  log_info ""
  log_info "Verifying GitHub secrets..."
  if gh secret list --repo="$GITHUB_REPO" | grep -E "GCP_SA_KEY|GCP_PROJECT" >/dev/null; then
    log_success "GitHub secrets verified"
    gh secret list --repo="$GITHUB_REPO" | grep -E "GCP_SA_KEY|GCP_PROJECT" | tee -a "$LOG_FILE"
  else
    log_error "Failed to verify GitHub secrets"
    return 1
  fi

  # Step 8: Summary
  log_info ""
  log_info "======================================================================"
  log_success "✅ Phase 6.3 GCP Setup Complete!"
  log_info "======================================================================"
  log_info ""
  log_info "📋 Next Steps:"
  log_info "  1. Trigger Phase 6.3 deployment workflow:"
  log_info "     gh workflow run 'Phase 6.3 - Deploy (GCP)' -f apply_confirm=false"
  log_info ""
  log_info "  2. Monitor workflow execution:"
  log_info "     gh run list --workflow 'phase-6-3-deploy-gcp.yml' --limit 5"
  log_info ""
  log_info "  3. Review Terraform plan artifacts (once available)"
  log_info ""
  log_info "📊 Log file: $LOG_FILE"

  return 0
}

# ============================================================================
# EXECUTE
# ============================================================================

if main "$@"; then
  exit 0
else
  log_error "Setup failed. Check log: $LOG_FILE"
  exit 1
fi
