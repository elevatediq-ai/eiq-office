#!/bin/bash
################################################################################
# Phase 8.5: Terraform Infrastructure Setup Script
# Automates GCP provisioning for PMO automation credentials
#
# Prerequisites:
# - Terraform >= 1.5.0 installed
# - gcloud CLI authenticated to GCP project
# - GCP project ID (billing-enabled)
# - PR #3327 merged to main
#
# Usage:
#   ./terraform_phase8_5_setup.sh <PROJECT_ID> [ENVIRONMENT] [SECRET_ACCESSOR_EMAIL]
#
# Examples:
#   ./terraform_phase8_5_setup.sh elevated-iq-prod dev
#   ./terraform_phase8_5_setup.sh elevated-iq-prod prod serviceAccount:github-actions@project.iam.gserviceaccount.com
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
ENVIRONMENT="${2:-dev}"
SECRET_ACCESSOR_EMAIL="${3:-}"
REPO_ROOT="${4:-.}"
TF_DIR="$REPO_ROOT/infra/terraform"

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
if [ -z "$PROJECT_ID" ]; then
    log_error "PROJECT_ID is required"
    echo "Usage: $0 <PROJECT_ID> [ENVIRONMENT] [SECRET_ACCESSOR_EMAIL]"
    exit 1
fi

# Pre-flight checks
log_info "Running pre-flight checks..."

if ! command -v terraform &> /dev/null; then
    log_error "Terraform not found. Please install Terraform >= 1.5.0"
    exit 1
fi
log_success "Terraform found: $(terraform version | head -1)"

if ! command -v gcloud &> /dev/null; then
    log_error "gcloud CLI not found. Please install Google Cloud SDK"
    exit 1
fi
log_success "gcloud CLI found"

if ! gcloud auth application-default print-access-token &> /dev/null; then
    log_error "gcloud not authenticated. Run: gcloud auth login"
    exit 1
fi
log_success "gcloud authenticated"

# Verify GCP project exists and is accessible
log_info "Verifying GCP project: $PROJECT_ID"
if ! gcloud projects describe "$PROJECT_ID" --format='value(projectId)' &> /dev/null; then
    log_error "GCP project not accessible: $PROJECT_ID"
    exit 1
fi
log_success "GCP project accessible: $PROJECT_ID"

# Check if Terraform module exists
if [ ! -d "$TF_DIR/modules/pmo-credentials" ]; then
    log_error "Terraform module not found at: $TF_DIR/modules/pmo-credentials"
    log_error "Please ensure PR #3327 is merged to main"
    exit 1
fi
log_success "Terraform module found"

# Create terraform.tfvars
log_info "Creating terraform.tfvars..."
cat > "$TF_DIR/terraform.tfvars" << EOL
gcp_project_id = "$PROJECT_ID"
environment    = "$ENVIRONMENT"

pmo_sa_account_id = "pmo-automation"
secret_id         = "pm-automation-sa-gcp-pmo"

# Principals who can access the SA key from Secret Manager
secret_accessor_members = [${SECRET_ACCESSOR_EMAIL:+\"$SECRET_ACCESSOR_EMAIL\"}]

# IAM roles for the PMO SA (least-privilege)
sa_roles = [
  "roles/viewer",
  "roles/bigquery.dataViewer",
  "roles/secretmanager.secretAccessor"
]
EOL
log_success "terraform.tfvars created"

# Initialize Terraform
cd "$TF_DIR"
log_info "Initializing Terraform..."
terraform init -upgrade
log_success "Terraform initialized"

# Validate configuration
log_info "Validating Terraform configuration..."
terraform validate
log_success "Terraform configuration valid"

# Plan infrastructure
log_info "Planning infrastructure provisioning..."
terraform plan -out=tfplan

# Show summary
log_info ""
log_info "==============================================="
log_info "Terraform plan complete. Review above output."
log_info "==============================================="
log_info ""
log_info "Expected resources to be created:"
log_info "  - 1x Service Account (pmo-automation-$ENVIRONMENT)"
log_info "  - 1x Service Account Key"
log_info "  - 1x Secret Manager Secret"
log_info "  - 3x IAM Bindings (SA roles)"
log_info ""

# Ask for confirmation
read -p "Apply terraform to provision infrastructure? (yes/no) " -r
if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    log_info "Applying Terraform..."
    terraform apply tfplan
    log_success "Infrastructure provisioned!"

    # Capture outputs
    log_info "Capturing Terraform outputs..."
    terraform output -json > /tmp/pmo_terraform_outputs.json
    log_success "Outputs saved to: /tmp/pmo_terraform_outputs.json"

    # Display key outputs
    SA_EMAIL=$(terraform output -raw service_account_email)
    SECRET_NAME=$(terraform output -json secret_name | tr -d '"')

    log_info ""
    log_info "==============================================="
    log_info "Phase 8.5 Infrastructure Provisioned!"
    log_info "==============================================="
    log_info "Service Account Email: $SA_EMAIL"
    log_info "Secret Manager Secret: $SECRET_NAME"
    log_info ""

    # Next steps
    log_info "Next steps:"
    log_info "1. Retrieve SA key from Secret Manager:"
    log_info "   gcloud secrets versions access latest \\"
    log_info "     --secret=$SECRET_NAME \\"
    log_info "     --project=$PROJECT_ID"
    log_info ""
    log_info "2. Encode to base64 and add to GitHub repository secret:"
    log_info "   Go to: Settings → Secrets and variables → Actions"
    log_info "   Add secret: GCP_PMO_SA_KEY"
    log_info ""
    log_info "3. CI workflow becomes active on next commit"
    log_info ""
else
    log_warn "Terraform apply cancelled. Manual apply required:"
    log_warn "  cd $TF_DIR"
    log_warn "  terraform apply tfplan"
fi

exit 0
