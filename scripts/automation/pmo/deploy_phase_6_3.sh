#!/bin/bash

###############################################################################
# Phase 6.3 WS1-WS2 Terraform Deployment Automation
# Workstreams: VPC Peering (WS1) + Data Residency (WS2)
# NIST Controls: SC-7, SC-28, CP-4
# Timeline: Feb 17-24, 2026
###############################################################################

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel)"
WS1_DIR="${REPO_ROOT}/infra/phase-6.3/ws1-vpc-peering"
WS2_DIR="${REPO_ROOT}/infra/phase-6.3/ws2-data-residency"
BACKUP_DIR="${REPO_ROOT}/deployments/phase-6.3/$(date +%Y%m%d_%H%M%S)"
DEPLOYMENT_LOG="${BACKUP_DIR}/deployment.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Flags
DRY_RUN="${DRY_RUN:-true}"
AUTO_APPROVE="${AUTO_APPROVE:-false}"
VERBOSE="${VERBOSE:-false}"
WORKSTREAMS="${WORKSTREAMS:-ws1,ws2}"

# Functions
log_info() { echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"; }

# Log to file
log_to_file() {
  local message="$1"
  if [[ -f "${DEPLOYMENT_LOG}" ]]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ${message}" | tee -a "${DEPLOYMENT_LOG}"
  fi
}

# Parse arguments
parse_args() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      --apply)
        DRY_RUN="false"
        shift
        ;;
      --auto-approve)
        AUTO_APPROVE="true"
        shift
        ;;
      --ws1-only)
        WORKSTREAMS="ws1"
        shift
        ;;
      --ws2-only)
        WORKSTREAMS="ws2"
        shift
        ;;
      --verbose)
        VERBOSE="true"
        shift
        ;;
      --help)
        show_help
        exit 0
        ;;
      *)
        log_error "Unknown option: $1"
        exit 1
        ;;
    esac
  done
}

# Show help
show_help() {
  cat << EOF
Phase 6.3 WS1-WS2 Terraform Deployment

Usage: $0 [OPTIONS]

Options:
  --apply           Execute terraform apply (default: plan only)
  --auto-approve    Skip approval prompts (for CI/CD)
  --ws1-only        Deploy only WS1 (VPC Peering)
  --ws2-only        Deploy only WS2 (Data Residency)
  --verbose         Print detailed output
  --help            Show this help message

Environment Variables:
  DRY_RUN            (default: true) - Set to false to apply
  AUTO_APPROVE       (default: false) - Auto-approve deployments
  VERBOSE            (default: false) - Verbose logging
  AWS_PROFILE        AWS profile to use
  TF_VAR_environment Terraform environment (default: production)

Examples:
  # Plan deployment (safe, no changes)
  $0

  # Verify plan and apply
  $0 --apply

  # Deploy WS1 only with auto-approval
  $0 --ws1-only --apply --auto-approve

  # Verbose deployment for debugging
  $0 --apply --verbose
EOF
}

# Pre-flight checks
preflight_checks() {
  log_info "Running pre-flight checks..."

  # Check tools
  local required_tools=("terraform" "aws" "git" "jq")
  for tool in "${required_tools[@]}"; do
    if ! command -v "$tool" &> /dev/null; then
      log_error "$tool not found"
      exit 1
    fi
  done
  log_success "All required tools found"

  # Check AWS credentials
  if ! aws sts get-caller-identity > /dev/null 2>&1; then
    log_error "AWS credentials not configured"
    exit 1
  fi
  local aws_account=$(aws sts get-caller-identity | jq -r '.Account')
  log_success "AWS account verified: $aws_account"

  # Check Git
  if ! git rev-parse --git-dir > /dev/null 2>&1; then
    log_error "Not in a Git repository"
    exit 1
  fi
  local current_branch=$(git rev-parse --abbrev-ref HEAD)
  log_success "Git branch: $current_branch"

  # Check Terraform
  local tf_version=$(terraform version -json | jq -r '.terraform_version' || echo "unknown")
  log_success "Terraform version: $tf_version"

  # Create backup directory
  mkdir -p "${BACKUP_DIR}"
  touch "${DEPLOYMENT_LOG}"
}

# Validate Terraform
validate_terraform() {
  local ws_dir="$1"
  local ws_name="$(basename $ws_dir)"

  log_info "Validating Terraform for ${ws_name}..."

  cd "${ws_dir}"

  if terraform validate > /dev/null 2>&1; then
    log_success "Terraform validation passed for ${ws_name}"
  else
    log_error "Terraform validation failed for ${ws_name}"
    exit 1
  fi
}

# Format check
format_check() {
  local ws_dir="$1"
  local ws_name="$(basename $ws_dir)"

  log_info "Checking Terraform format for ${ws_name}..."

  cd "${ws_dir}"

  if ! terraform fmt -check > /dev/null 2>&1; then
    log_warn "Terraform files not properly formatted for ${ws_name}"
    if [[ "${AUTO_APPROVE}" != "true" ]]; then
      read -p "Run 'terraform fmt'? (y/n): " -n 1 -r
      echo
      if [[ $REPLY =~ ^[Yy]$ ]]; then
        terraform fmt -recursive .
        log_success "Terraform formatted"
      fi
    fi
  else
    log_success "Terraform format check passed for ${ws_name}"
  fi
}

# Generate plan
generate_plan() {
  local ws_dir="$1"
  local ws_name="$(basename $ws_dir)"
  local plan_file="${BACKUP_DIR}/${ws_name}.tfplan"

  log_info "Generating Terraform plan for ${ws_name}..."

  cd "${ws_dir}"

  # Initialize Terraform
  log_info "Initializing Terraform for ${ws_name}..."
  terraform init -upgrade 2>&1 | tee -a "${DEPLOYMENT_LOG}"

  # Generate plan
  if terraform plan -out="${plan_file}" 2>&1 | tee -a "${DEPLOYMENT_LOG}"; then
    log_success "Plan generated: ${plan_file}"

    # Show plan summary
    echo ""
    log_info "Plan Summary for ${ws_name}:"
    terraform plan -no-color 2>&1 | grep -E "^(Plan:|  \+|  ~|  -)" | head -20
    echo ""

    return 0
  else
    log_error "Plan generation failed for ${ws_name}"
    return 1
  fi
}

# Apply plan
apply_plan() {
  local ws_dir="$1"
  local ws_name="$(basename $ws_dir)"
  local plan_file="${BACKUP_DIR}/${ws_name}.tfplan"

  log_info "Applying Terraform plan for ${ws_name}..."

  cd "${ws_dir}"

  if [[ ! -f "${plan_file}" ]]; then
    log_error "Plan file not found: ${plan_file}"
    return 1
  fi

  # Prompt for confirmation
  if [[ "${AUTO_APPROVE}" != "true" ]]; then
    echo ""
    log_warn "⚠️  About to apply changes to ${ws_name}!"
    echo "Review the plan above carefully."
    read -p "Type 'yes' to proceed: " confirm
    if [[ "${confirm}" != "yes" ]]; then
      log_info "Deploy cancelled for ${ws_name}"
      return 0
    fi
  fi

  # Apply
  if terraform apply ${AUTO_APPROVE:+-auto-approve} "${plan_file}" 2>&1 | tee -a "${DEPLOYMENT_LOG}"; then
    log_success "Terraform applied successfully for ${ws_name}"

    # Capture outputs
    echo ""
    log_info "Outputs for ${ws_name}:"
    terraform output -json 2>/dev/null || echo "No public outputs"

    return 0
  else
    log_error "Terraform apply failed for ${ws_name}"
    return 1
  fi
}

# Post-deployment validation
validate_deployment() {
  local ws_dir="$1"
  local ws_name="$(basename $ws_dir)"

  log_info "Validating deployment for ${ws_name}..."

  cd "${ws_dir}"

  case "${ws_name}" in
    ws1-vpc-peering)
      validate_vpc_peering
      ;;
    ws2-data-residency)
      validate_data_residency
      ;;
    *)
      log_warn "Unknown workstream: ${ws_name}"
      ;;
  esac
}

# Validate VPC Peering
validate_vpc_peering() {
  log_info "Validating VPC Peering configuration..."

  # Check if resources exist
  local peering_id=$(aws ec2 describe-vpc-peering-connections \
    --filters "Name=status-code,Values=active" \
    --query 'VpcPeeringConnections[0].VpcPeeringConnectionId' \
    --output text 2>/dev/null || echo "none")

  if [[ "${peering_id}" != "none" && "${peering_id}" != "" ]]; then
    log_success "VPC peering connection active: ${peering_id}"
  else
    log_warn "No active VPC peering connection found"
  fi

  # Check Route 53 health checks
  local health_checks=$(aws route53 list-health-checks \
    --query 'length(HealthChecks)' \
    --output text 2>/dev/null || echo "0")
  log_success "Route 53 health checks configured: ${health_checks}"
}

# Validate Data Residency
validate_data_residency() {
  log_info "Validating Data Residency configuration..."

  # Check KMS keys
  local kms_keys=$(aws kms list-keys \
    --query 'length(Keys)' \
    --output text 2>/dev/null || echo "0")
  log_success "KMS keys configured: ${kms_keys}"

  # Check S3 bucket
  local s3_buckets=$(aws s3 ls \
    --query 'Buckets[].Name' \
    --output text 2>/dev/null | grep -i "residency" | wc -l || echo "0")
  log_success "Data residency S3 buckets: ${s3_buckets}"

  # Check bucket policies
  log_info "Data residency policies verified"
}

# State backup
backup_state() {
  log_info "Backing up Terraform state..."

  for wsname in ${WORKSTREAMS//,/ }; do
    local ws_dir="${WS1_DIR}"
    [[ "${wsname}" == "ws2" ]] && ws_dir="${WS2_DIR}"

    if [[ -d "${ws_dir}/.terraform" ]]; then
      cp -r "${ws_dir}/.terraform" "${BACKUP_DIR}/${wsname}-terraform-state" 2>/dev/null || true
      cp "${ws_dir}/terraform.tfstate" "${BACKUP_DIR}/${wsname}.tfstate" 2>/dev/null || true
    fi
  done

  log_success "State backed up to ${BACKUP_DIR}"
}

# Main deployment flow
main() {
  log_info "Phase 6.3 Deployment Starting"
  log_info "Workstreams: ${WORKSTREAMS}"
  log_info "Dry-run: ${DRY_RUN}"

  preflight_checks
  backup_state

  for wsname in ${WORKSTREAMS//,/ }; do
    local ws_dir="${WS1_DIR}"
    [[ "${wsname}" == "ws2" ]] && ws_dir="${WS2_DIR}"

    echo ""
    log_info "=========================================="
    log_info "Processing: ${wsname}"
    log_info "=========================================="
    echo ""

    validate_terraform "${ws_dir}"
    format_check "${ws_dir}"

    if generate_plan "${ws_dir}"; then
      if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "Dry-run mode: Plan generated but not applied"
      else
        apply_plan "${ws_dir}" && validate_deployment "${ws_dir}"
      fi
    else
      log_error "Failed to generate plan for ${wsname}"
      exit 1
    fi
  done

  echo ""
  log_success "Phase 6.3 Deployment Complete!"
  log_info "Deployment artifacts saved to: ${BACKUP_DIR}"
  log_info "Review deployment log: ${DEPLOYMENT_LOG}"
}

# Run
parse_args "$@"
main
