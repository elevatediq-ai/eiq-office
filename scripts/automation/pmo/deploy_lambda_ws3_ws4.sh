#!/bin/bash

###############################################################################
# Phase 6.3 WS3-WS4 Lambda & EventBridge Deployment
# Workstreams: Failover Orchestrator (WS3) + Secrets Rotation (WS4)
# NIST Controls: CP-4 (Contingency), AC-2 (Account Mgmt), AU-2 (Audit)
# Timeline: Feb 20-24, 2026
###############################################################################

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel)"
WS3_DIR="${REPO_ROOT}/infra/phase-6.3/ws3-disaster-recovery"
WS4_DIR="${REPO_ROOT}/infra/phase-6.3/ws4-secrets-compliance"
BUILD_DIR="${REPO_ROOT}/build/lambda"
DEPLOYMENT_LOG="${BUILD_DIR}/deployment.log"
AWS_REGION="${AWS_REGION:-us-east-1}"
ENVIRONMENT="${ENVIRONMENT:-production}"

# Lambda Configuration
WS3_FUNCTION_NAME="failover-orchestrator"
WS3_HANDLER="lambda_function.lambda_handler"
WS3_RUNTIME="python3.12"
WS3_TIMEOUT="900"
WS3_MEMORY="512"

WS4_FUNCTION_NAME="secrets-rotation-engine"
WS4_HANDLER="lambda_function.lambda_handler"
WS4_RUNTIME="python3.12"
WS4_TIMEOUT="300"
WS4_MEMORY="256"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Flags
SKIP_TESTS="${SKIP_TESTS:-false}"
AUTO_APPROVE="${AUTO_APPROVE:-false}"
DRY_RUN="${DRY_RUN:-true}"

# Functions
log_info() { echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"; }

# Parse arguments
parse_args() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      --deploy)
        DRY_RUN="false"
        shift
        ;;
      --skip-tests)
        SKIP_TESTS="true"
        shift
        ;;
      --auto-approve)
        AUTO_APPROVE="true"
        shift
        ;;
      --ws3-only)
        WS4_FUNCTION_NAME=""
        shift
        ;;
      --ws4-only)
        WS3_FUNCTION_NAME=""
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
Phase 6.3 WS3-WS4 Lambda Deployment

Usage: $0 [OPTIONS]

Options:
  --deploy          Deploy Lambda functions (default: package only)
  --skip-tests      Skip unit tests
  --auto-approve    Auto-approve deployments
  --ws3-only        Deploy only WS3 (failover orchestrator)
  --ws4-only        Deploy only WS4 (secrets rotation)
  --help            Show this help message

Environment Variables:
  AWS_REGION        AWS region (default: us-east-1)
  ENVIRONMENT       Environment name (default: production)
  DRY_RUN           Dry-run mode (default: true)
  SKIP_TESTS        Skip tests (default: false)
  AUTO_APPROVE      Skip prompts (default: false)

Examples:
  # Package and test
  $0

  # Deploy both functions
  $0 --deploy --auto-approve

  # Deploy WS3 only
  $0 --ws3-only --deploy
EOF
}

# Setup
setup() {
  log_info "Setting up Lambda deployment environment..."

  mkdir -p "${BUILD_DIR}"
  touch "${DEPLOYMENT_LOG}"

  # Check AWS credentials
  if ! aws sts get-caller-identity > /dev/null 2>&1; then
    log_error "AWS credentials not configured"
    exit 1
  fi

  local account_id=$(aws sts get-caller-identity | jq -r '.Account')
  log_success "AWS account: ${account_id}"

  # Check Python
  if ! command -v python3 &> /dev/null; then
    log_error "Python 3 not found"
    exit 1
  fi

  log_success "Environment setup complete"
}

# Build WS3
build_ws3() {
  log_info "Building WS3 Failover Orchestrator Lambda..."

  local build_path="${BUILD_DIR}/ws3-failover-orchestrator"
  rm -rf "${build_path}"
  mkdir -p "${build_path}"

  # Copy source code
  cp "${WS3_DIR}/failover_orchestrator.py" "${build_path}/lambda_function.py"

  # Install dependencies
  log_info "Installing WS3 dependencies..."
  python3 -m pip install \
    --quiet \
    --target "${build_path}" \
    boto3 \
    python-dateutil \
    2>&1 | tee -a "${DEPLOYMENT_LOG}"

  # Create zip package
  cd "${build_path}"
  zip -r -q "../ws3-failover-orchestrator.zip" . 2>&1 | tee -a "${DEPLOYMENT_LOG}"
  cd - > /dev/null

  log_success "WS3 package created: ${BUILD_DIR}/ws3-failover-orchestrator.zip"
  ls -lh "${BUILD_DIR}/ws3-failover-orchestrator.zip"
}

# Build WS4
build_ws4() {
  log_info "Building WS4 Secrets Rotation Lambda..."

  local build_path="${BUILD_DIR}/ws4-secrets-rotation"
  rm -rf "${build_path}"
  mkdir -p "${build_path}"

  # Copy source code
  cp "${WS4_DIR}/secrets_rotation_engine.py" "${build_path}/lambda_function.py"

  # Install dependencies
  log_info "Installing WS4 dependencies..."
  python3 -m pip install \
    --quiet \
    --target "${build_path}" \
    boto3 \
    cryptography \
    python-dateutil \
    2>&1 | tee -a "${DEPLOYMENT_LOG}"

  # Create zip package
  cd "${build_path}"
  zip -r -q "../ws4-secrets-rotation.zip" . 2>&1 | tee -a "${DEPLOYMENT_LOG}"
  cd - > /dev/null

  log_success "WS4 package created: ${BUILD_DIR}/ws4-secrets-rotation.zip"
  ls -lh "${BUILD_DIR}/ws4-secrets-rotation.zip"
}

# Test WS3
test_ws3() {
  if [[ "${SKIP_TESTS}" == "true" ]]; then
    log_warn "Skipping WS3 tests (--skip-tests)"
    return 0
  fi

  log_info "Testing WS3 Failover Orchestrator..."

  cd "${WS3_DIR}"

  # Run pytest
  if python3 -m pytest test_failover_orchestrator.py -v 2>&1 | tee -a "${DEPLOYMENT_LOG}"; then
    log_success "WS3 tests passed"
  else
    log_error "WS3 tests failed"
    return 1
  fi
}

# Test WS4
test_ws4() {
  if [[ "${SKIP_TESTS}" == "true" ]]; then
    log_warn "Skipping WS4 tests (--skip-tests)"
    return 0
  fi

  log_info "Testing WS4 Secrets Rotation..."

  cd "${WS4_DIR}"

  # Run pytest
  if python3 -m pytest test_secrets_rotation_engine.py -v 2>&1 | tee -a "${DEPLOYMENT_LOG}"; then
    log_success "WS4 tests passed"
  else
    log_error "WS4 tests failed"
    return 1
  fi
}

# Deploy WS3
deploy_ws3() {
  log_info "Deploying WS3 Lambda Function..."

  # Check if function exists
  if aws lambda get-function --function-name "${WS3_FUNCTION_NAME}" > /dev/null 2>&1; then
    log_info "Updating existing WS3 function..."

    aws lambda update-function-code \
      --function-name "${WS3_FUNCTION_NAME}" \
      --zip-file "fileb://${BUILD_DIR}/ws3-failover-orchestrator.zip" \
      >> "${DEPLOYMENT_LOG}" 2>&1

    # Wait for update to complete
    aws lambda wait function-updated --function-name "${WS3_FUNCTION_NAME}" >> "${DEPLOYMENT_LOG}" 2>&1

    aws lambda update-function-configuration \
      --function-name "${WS3_FUNCTION_NAME}" \
      --timeout "${WS3_TIMEOUT}" \
      --memory-size "${WS3_MEMORY}" \
      --runtime "${WS3_RUNTIME}" \
      --handler "${WS3_HANDLER}" \
      --environment "Variables={ENVIRONMENT=${ENVIRONMENT}}" \
      >> "${DEPLOYMENT_LOG}" 2>&1

  else
    log_info "Creating new WS3 function..."

    # Check if IAM role exists
    local role_arn=$(aws iam get-role --role-name lambda-execution-role --query 'Role.Arn' --output text 2>/dev/null || echo "")

    if [[ -z "${role_arn}" ]]; then
      log_error "Lambda execution role not found. Create with:"
      echo "  aws iam create-role --role-name lambda-execution-role --assume-role-policy-document file://trust-policy.json"
      return 1
    fi

    aws lambda create-function \
      --function-name "${WS3_FUNCTION_NAME}" \
      --runtime "${WS3_RUNTIME}" \
      --role "${role_arn}" \
      --handler "${WS3_HANDLER}" \
      --zip-file "fileb://${BUILD_DIR}/ws3-failover-orchestrator.zip" \
      --timeout "${WS3_TIMEOUT}" \
      --memory-size "${WS3_MEMORY}" \
      --environment "Variables={ENVIRONMENT=${ENVIRONMENT}}" \
      --tags \
        Key=Phase,Value=6.3 \
        Key=Workstream,Value=WS3 \
        Key=Environment,Value="${ENVIRONMENT}" \
      >> "${DEPLOYMENT_LOG}" 2>&1
  fi

  log_success "WS3 Lambda deployed: ${WS3_FUNCTION_NAME}"
}

# Deploy WS4
deploy_ws4() {
  log_info "Deploying WS4 Lambda Function..."

  # Check if function exists
  if aws lambda get-function --function-name "${WS4_FUNCTION_NAME}" > /dev/null 2>&1; then
    log_info "Updating existing WS4 function..."

    aws lambda update-function-code \
      --function-name "${WS4_FUNCTION_NAME}" \
      --zip-file "fileb://${BUILD_DIR}/ws4-secrets-rotation.zip" \
      >> "${DEPLOYMENT_LOG}" 2>&1

    # Wait for update to complete
    aws lambda wait function-updated --function-name "${WS4_FUNCTION_NAME}" >> "${DEPLOYMENT_LOG}" 2>&1

    aws lambda update-function-configuration \
      --function-name "${WS4_FUNCTION_NAME}" \
      --timeout "${WS4_TIMEOUT}" \
      --memory-size "${WS4_MEMORY}" \
      --runtime "${WS4_RUNTIME}" \
      --handler "${WS4_HANDLER}" \
      --environment "Variables={ENVIRONMENT=${ENVIRONMENT}}" \
      >> "${DEPLOYMENT_LOG}" 2>&1

  else
    log_info "Creating new WS4 function..."

    local role_arn=$(aws iam get-role --role-name secrets-rotation-lambda-role --query 'Role.Arn' --output text 2>/dev/null || echo "")

    if [[ -z "${role_arn}" ]]; then
      log_error "Lambda execution role not found"
      return 1
    fi

    aws lambda create-function \
      --function-name "${WS4_FUNCTION_NAME}" \
      --runtime "${WS4_RUNTIME}" \
      --role "${role_arn}" \
      --handler "${WS4_HANDLER}" \
      --zip-file "fileb://${BUILD_DIR}/ws4-secrets-rotation.zip" \
      --timeout "${WS4_TIMEOUT}" \
      --memory-size "${WS4_MEMORY}" \
      --environment "Variables={ENVIRONMENT=${ENVIRONMENT}}" \
      --tags \
        Key=Phase,Value=6.3 \
        Key=Workstream,Value=WS4 \
        Key=Environment,Value="${ENVIRONMENT}" \
      >> "${DEPLOYMENT_LOG}" 2>&1
  fi

  log_success "WS4 Lambda deployed: ${WS4_FUNCTION_NAME}"
}

# Setup EventBridge Rules
setup_eventbridge() {
  log_info "Setting up EventBridge triggers..."

  # WS3: Health check rule (every 5 minutes)
  aws events put-rule \
    --name elevatediq-${ENVIRONMENT}-ws3-failover-health-check \
    --schedule-expression 'rate(5 minutes)' \
    --state ENABLED \
    >> "${DEPLOYMENT_LOG}" 2>&1

  aws lambda add-permission \
    --function-name "${WS3_FUNCTION_NAME}" \
    --statement-id AllowEventBridgeInvoke \
    --action lambda:InvokeFunction \
    --principal events.amazonaws.com \
    --source-arn "arn:aws:events:${AWS_REGION}:$(aws sts get-caller-identity | jq -r '.Account'):rule/elevatediq-${ENVIRONMENT}-ws3-failover-health-check" \
    2>/dev/null || true

  aws events put-targets \
    --rule elevatediq-${ENVIRONMENT}-ws3-failover-health-check \
    --targets "Id=1,Arn=arn:aws:lambda:${AWS_REGION}:$(aws sts get-caller-identity | jq -r '.Account'):function:${WS3_FUNCTION_NAME}" \
    >> "${DEPLOYMENT_LOG}" 2>&1

  log_success "WS3 EventBridge trigger configured"

  # WS4: Nightly rotation rule (02:00 UTC)
  aws events put-rule \
    --name elevatediq-${ENVIRONMENT}-ws4-secrets-rotation-schedule \
    --schedule-expression 'cron(0 2 * * ? *)' \
    --state ENABLED \
    >> "${DEPLOYMENT_LOG}" 2>&1

  aws lambda add-permission \
    --function-name "${WS4_FUNCTION_NAME}" \
    --statement-id AllowEventBridgeInvoke \
    --action lambda:InvokeFunction \
    --principal events.amazonaws.com \
    --source-arn "arn:aws:events:${AWS_REGION}:$(aws sts get-caller-identity | jq -r '.Account'):rule/elevatediq-${ENVIRONMENT}-ws4-secrets-rotation-schedule" \
    2>/dev/null || true

  aws events put-targets \
    --rule elevatediq-${ENVIRONMENT}-ws4-secrets-rotation-schedule \
    --targets "Id=1,Arn=arn:aws:lambda:${AWS_REGION}:$(aws sts get-caller-identity | jq -r '.Account'):function:${WS4_FUNCTION_NAME}" \
    >> "${DEPLOYMENT_LOG}" 2>&1

  log_success "WS4 EventBridge trigger configured"
}

# Validate deployment
validate_deployment() {
  log_info "Validating Lambda deployments..."

  # Test WS3
  aws lambda invoke \
    --function-name "${WS3_FUNCTION_NAME}" \
    --payload '{"trigger":"manual","target_service":"all"}' \
    /tmp/ws3-test-response.json \
    >> "${DEPLOYMENT_LOG}" 2>&1

  if grep -q '"statusCode": 200' /tmp/ws3-test-response.json 2>/dev/null; then
    log_success "WS3 Lambda test invocation successful"
  else
    log_warn "WS3 Lambda test invocation returned non-200 status"
    cat /tmp/ws3-test-response.json
  fi

  # Test WS4
  aws lambda invoke \
    --function-name "${WS4_FUNCTION_NAME}" \
    --payload '{"trigger":"manual","secret_types":["all"]}' \
    /tmp/ws4-test-response.json \
    >> "${DEPLOYMENT_LOG}" 2>&1

  if grep -q '"statusCode": 200' /tmp/ws4-test-response.json 2>/dev/null; then
    log_success "WS4 Lambda test invocation successful"
  else
    log_warn "WS4 Lambda test invocation returned non-200 status"
    cat /tmp/ws4-test-response.json
  fi
}

# Main flow
main() {
  log_info "Phase 6.3 WS3-WS4 Lambda Deployment Starting"

  setup

  echo ""
  echo "=========================================="
  echo "Building Lambda packages..."
  echo "=========================================="

  if [[ -n "${WS3_FUNCTION_NAME}" ]]; then
    build_ws3
    test_ws3
  fi

  if [[ -n "${WS4_FUNCTION_NAME}" ]]; then
    build_ws4
    test_ws4
  fi

  if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "Dry-run mode: Packages built and tested"
    log_info "To deploy, run: $0 --deploy"
  else
    echo ""
    echo "=========================================="
    echo "Deploying Lambda functions..."
    echo "=========================================="

    if [[ -n "${WS3_FUNCTION_NAME}" ]]; then
      deploy_ws3
    fi

    if [[ -n "${WS4_FUNCTION_NAME}" ]]; then
      deploy_ws4
    fi

    setup_eventbridge
    validate_deployment

    log_success "Phase 6.3 Lambda Deployment Complete!"
  fi

  echo ""
  log_info "Deployment log: ${DEPLOYMENT_LOG}"
}

# Run
parse_args "$@"
main
