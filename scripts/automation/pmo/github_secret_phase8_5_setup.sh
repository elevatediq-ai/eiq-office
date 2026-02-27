#!/bin/bash
################################################################################
# Phase 8.5: GitHub Secret Provisioning Script
# Retrieves PMO SA key from GCP Secret Manager and adds to GitHub repository
#
# Prerequisites:
# - Terraform apply completed (creates Secret Manager secret)
# - gcloud CLI authenticated to GCP project
# - gh CLI authenticated to GitHub
# - GCP project ID
#
# Usage:
#   ./github_secret_phase8_5_setup.sh <PROJECT_ID> <GITHUB_REPO>
#
# Example:
#   ./github_secret_phase8_5_setup.sh elevated-iq-prod kushin77/ElevatedIQ-Mono-Repo
################################################################################

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
PROJECT_ID="${1:-}"
GITHUB_REPO="${2:-}"
SECRET_NAME="pm-automation-sa-gcp-pmo"
GITHUB_SECRET_NAME="GCP_PMO_SA_KEY"

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Validation
if [ -z "$PROJECT_ID" ] || [ -z "$GITHUB_REPO" ]; then
    log_error "Both PROJECT_ID and GITHUB_REPO are required"
    echo "Usage: $0 <PROJECT_ID> <GITHUB_REPO>"
    echo "Example: $0 elevated-iq-prod kushin77/ElevatedIQ-Mono-Repo"
    exit 1
fi

# Pre-flight checks
log_info "Running pre-flight checks..."

if ! command -v gcloud &> /dev/null; then
    log_error "gcloud CLI not found"
    exit 1
fi
log_success "gcloud CLI found"

if ! command -v gh &> /dev/null; then
    log_error "gh CLI not found. Install with: brew install gh"
    exit 1
fi
log_success "gh CLI found"

# Verify GCP authentication
log_info "Verifying GCP access..."
if ! gcloud projects describe "$PROJECT_ID" --format='value(projectId)' &> /dev/null; then
    log_error "Cannot access GCP project: $PROJECT_ID"
    exit 1
fi
log_success "GCP project accessible"

# Verify Secret Manager secret exists
log_info "Verifying Secret Manager secret exists..."
if ! gcloud secrets describe "$SECRET_NAME" --project="$PROJECT_ID" &> /dev/null; then
    log_error "Secret not found in Secret Manager: $SECRET_NAME"
    log_error "Run terraform apply first to create the secret"
    exit 1
fi
log_success "Secret Manager secret found: $SECRET_NAME"

# Verify GitHub authentication
log_info "Verifying GitHub access..."
if ! gh auth status &> /dev/null; then
    log_error "gh CLI not authenticated. Run: gh auth login"
    exit 1
fi
log_success "GitHub authenticated"

# Retrieve SA key from Secret Manager
log_info "Retrieving SA key from Secret Manager..."
SA_KEY=$(gcloud secrets versions access latest \
    --secret="$SECRET_NAME" \
    --project="$PROJECT_ID")

if [ -z "$SA_KEY" ]; then
    log_error "Failed to retrieve SA key from Secret Manager"
    exit 1
fi
log_success "SA key retrieved (length: ${#SA_KEY} bytes)"

# Verify SA key is valid JSON
log_info "Validating SA key JSON format..."
if ! echo "$SA_KEY" | python3 -m json.tool > /dev/null 2>&1; then
    log_error "SA key is not valid JSON"
    exit 1
fi
log_success "SA key is valid JSON"

# Encode to base64
log_info "Encoding SA key to base64..."
SA_KEY_B64=$(echo "$SA_KEY" | base64 -w0)
log_success "SA key encoded (base64 length: ${#SA_KEY_B64} bytes)"

# Add to GitHub repository secret
log_info "Adding to GitHub repository secret: $GITHUB_SECRET_NAME"
echo "$SA_KEY_B64" | gh secret set "$GITHUB_SECRET_NAME" \
    --repo="$GITHUB_REPO" \
    --body-file="-"

log_success "GitHub repository secret added: $GITHUB_SECRET_NAME"

# Verify secret was added
log_info "Verifying GitHub secret..."
if gh secret list --repo="$GITHUB_REPO" | grep -q "$GITHUB_SECRET_NAME"; then
    log_success "GitHub secret verified"
else
    log_warn "Could not verify GitHub secret (may require permissions)"
fi

# Check if GCP_PROJECT_ID secret exists
log_info "Checking if GCP_PROJECT_ID secret exists..."
if ! gh secret list --repo="$GITHUB_REPO" 2>/dev/null | grep -q "GCP_PROJECT_ID"; then
    log_warn "GCP_PROJECT_ID secret not found. Adding..."
    echo "$PROJECT_ID" | gh secret set "GCP_PROJECT_ID" \
        --repo="$GITHUB_REPO" \
        --body-file="-"
    log_success "GCP_PROJECT_ID secret added"
else
    log_success "GCP_PROJECT_ID secret already exists"
fi

# Summary
log_info ""
log_info "==============================================="
log_info "GitHub Secrets Provisioned!"
log_info "==============================================="
log_info "Repository: $GITHUB_REPO"
log_info "Secrets Added:"
log_info "  - $GITHUB_SECRET_NAME (SA key)"
log_info "  - GCP_PROJECT_ID (project ID)"
log_info ""
log_info "Next Steps:"
log_info "1. Verify workflow configuration in .github/workflows/phase8.5-pmo-ci.yml"
log_info "2. Trigger workflow on next commit to monitored branches"
log_info "3. CI validates on: main, develop, feat/* branches"
log_info ""
log_info "Workflow will:"
log_info "  - Decode GCP_PMO_SA_KEY from repository secret"
log_info "  - Authenticate to GCP using SA credentials"
log_info "  - Run PMO GCP inventory smoke test"
log_info "  - Validate services.json output"
log_info ""

exit 0
