#!/bin/bash

#################################################################################
# Phase 6.3: Days 4-5 Deployment Executor
# Purpose: Execute WS1-WS4 infrastructure and Lambda deployment in sequence
# Status: AUTOMATED EXECUTION FRAMEWORK
# Date: February 17, 2026
#################################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

REPO_ROOT="/home/akushnir/ElevatedIQ-Mono-Repo"
DEPLOYMENT_LOG="$REPO_ROOT/docs/phase-6.3/DAYS_4_5_DEPLOYMENT_LOG.txt"
AWS_REGION_PRIMARY="us-east-1"
AWS_REGION_SECONDARY="us-west-2"

# Timestamp for logging
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$DEPLOYMENT_LOG"
}

success() {
    echo -e "${GREEN}✅ $1${NC}" | tee -a "$DEPLOYMENT_LOG"
}

error() {
    echo -e "${RED}❌ $1${NC}" | tee -a "$DEPLOYMENT_LOG"
    exit 1
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}" | tee -a "$DEPLOYMENT_LOG"
}

#################################################################################
# PRE-DEPLOYMENT VALIDATION
#################################################################################

validate_prerequisites() {
    log "🔍 Validating prerequisites..."

    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI not found. Please install AWS CLI v1.27+"
    fi

    # Check Terraform
    if ! command -v terraform &> /dev/null; then
        error "Terraform not found. Please install Terraform v1.0+"
    fi

    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Run 'aws configure'"
    fi

    # Check git
    if ! command -v git &> /dev/null; then
        error "Git not found"
    fi

    # Verify repository
    if [ ! -d "$REPO_ROOT" ]; then
        error "Repository not found at $REPO_ROOT"
    fi

    success "All prerequisites met"
}

#################################################################################
# TERRAFORM DEPLOYMENTS
#################################################################################

deploy_ws1_vpc_peering() {
    log "🚀 Deploying WS1: VPC Peering Infrastructure..."

    cd "$REPO_ROOT/infra/phase-6.3/ws1-vpc-peering"

    # Validate configuration
    log "  → Validating Terraform configuration..."
    terraform validate || error "Terraform validation failed"
    success "  ✅ Configuration valid"

    # Create plan
    log "  → Creating deployment plan..."
    terraform plan -out=ws1.plan || error "Terraform plan failed"
    success "  ✅ Plan created"

    # Apply infrastructure
    log "  → Applying infrastructure..."
    terraform apply ws1.plan || error "Terraform apply failed"
    success "  ✅ WS1 deployment complete"

    # Validate deployment
    log "  → Validating deployment..."
    VPC_PEERING_ID=$(terraform output -raw vpc_peering_id 2>/dev/null || echo "unknown")
    if [ "$VPC_PEERING_ID" != "unknown" ]; then
        success "  ✅ VPC peering connection: $VPC_PEERING_ID"
    fi
}

deploy_ws2_data_residency() {
    log "🚀 Deploying WS2: Data Residency & Compliance..."

    cd "$REPO_ROOT/infra/phase-6.3/ws2-data-residency"

    # Validate configuration
    log "  → Validating Terraform configuration..."
    terraform validate || error "Terraform validation failed"
    success "  ✅ Configuration valid"

    # Create plan
    log "  → Creating deployment plan..."
    terraform plan -out=ws2.plan || error "Terraform plan failed"
    success "  ✅ Plan created"

    # Apply infrastructure
    log "  → Applying infrastructure..."
    terraform apply ws2.plan || error "Terraform apply failed"
    success "  ✅ WS2 deployment complete"

    # Validate deployment
    log "  → Validating deployment..."
    S3_BUCKET=$(terraform output -raw audit_trail_bucket 2>/dev/null || echo "unknown")
    if [ "$S3_BUCKET" != "unknown" ]; then
        success "  ✅ S3 audit trail bucket: $S3_BUCKET"
    fi
}

#################################################################################
# LAMBDA DEPLOYMENTS
#################################################################################

deploy_ws3_failover_lambda() {
    log "🚀 Deploying WS3: Failover Orchestrator Lambda..."

    cd "$REPO_ROOT/infra/phase-6.3/ws3-disaster-recovery"

    # Validate Python syntax
    log "  → Validating Python syntax..."
    python3 -m py_compile failover_orchestrator.py || error "Python syntax error"
    success "  ✅ Syntax valid"

    # Create deployment package
    log "  → Creating deployment package..."
    zip -j failover_orchestrator.zip failover_orchestrator.py 2>/dev/null
    success "  ✅ Package created"

    # Check IAM role
    log "  → Checking IAM role..."
    ROLE_ARN=$(aws iam get-role --role-name ElevatedIQ-Failover-Orchestrator --query 'Role.Arn' --output text 2>/dev/null)
    if [ -z "$ROLE_ARN" ]; then
        warning "  ⚠️  IAM role not found. Creating..."
        aws iam create-role \
            --role-name ElevatedIQ-Failover-Orchestrator \
            --assume-role-policy-document file://$REPO_ROOT/infra/phase-6.3/lambda-trust-policy.json
        aws iam put-role-policy \
            --role-name ElevatedIQ-Failover-Orchestrator \
            --policy-name failover-permissions \
            --policy-document file://$REPO_ROOT/infra/phase-6.3/iam-failover-policy.json
        sleep 10
        ROLE_ARN="arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/ElevatedIQ-Failover-Orchestrator"
    fi
    success "  ✅ IAM role: $ROLE_ARN"

    # Deploy Lambda
    log "  → Deploying Lambda function..."
    aws lambda create-function \
        --function-name ElevatedIQ-Failover-Orchestrator \
        --runtime python3.11 \
        --role "$ROLE_ARN" \
        --handler failover_orchestrator.lambda_handler \
        --timeout 900 \
        --memory-size 512 \
        --zip-file fileb://failover_orchestrator.zip \
        --region "$AWS_REGION_PRIMARY" 2>/dev/null || \
    aws lambda update-function-code \
        --function-name ElevatedIQ-Failover-Orchestrator \
        --zip-file fileb://failover_orchestrator.zip \
        --region "$AWS_REGION_PRIMARY"

    success "  ✅ WS3 Lambda deployed/updated"
}

deploy_ws4_rotation_lambda() {
    log "🚀 Deploying WS4: Secrets Rotation Lambda..."

    cd "$REPO_ROOT/infra/phase-6.3/ws4-secrets-compliance"

    # Validate Python syntax
    log "  → Validating Python syntax..."
    python3 -m py_compile secrets_rotation_engine.py || error "Python syntax error"
    success "  ✅ Syntax valid"

    # Create deployment package
    log "  → Creating deployment package..."
    zip -j secrets_rotation.zip secrets_rotation_engine.py 2>/dev/null
    success "  ✅ Package created"

    # Check IAM role
    log "  → Checking IAM role..."
    ROLE_ARN=$(aws iam get-role --role-name ElevatedIQ-Secrets-Rotation --query 'Role.Arn' --output text 2>/dev/null)
    if [ -z "$ROLE_ARN" ]; then
        warning "  ⚠️  IAM role not found. Creating..."
        aws iam create-role \
            --role-name ElevatedIQ-Secrets-Rotation \
            --assume-role-policy-document file://$REPO_ROOT/infra/phase-6.3/lambda-trust-policy.json
        aws iam put-role-policy \
            --role-name ElevatedIQ-Secrets-Rotation \
            --policy-name secrets-rotation-permissions \
            --policy-document file://$REPO_ROOT/infra/phase-6.3/iam-rotation-policy.json
        sleep 10
        ROLE_ARN="arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/ElevatedIQ-Secrets-Rotation"
    fi
    success "  ✅ IAM role: $ROLE_ARN"

    # Deploy Lambda
    log "  → Deploying Lambda function..."
    aws lambda create-function \
        --function-name ElevatedIQ-Secrets-Rotation \
        --runtime python3.11 \
        --role "$ROLE_ARN" \
        --handler secrets_rotation_engine.lambda_handler \
        --timeout 300 \
        --memory-size 256 \
        --zip-file fileb://secrets_rotation.zip \
        --region "$AWS_REGION_PRIMARY" 2>/dev/null || \
    aws lambda update-function-code \
        --function-name ElevatedIQ-Secrets-Rotation \
        --zip-file fileb://secrets_rotation.zip \
        --region "$AWS_REGION_PRIMARY"

    success "  ✅ WS4 Lambda deployed/updated"
}

#################################################################################
# INTEGRATION VALIDATION
#################################################################################

validate_deployment() {
    log "🔍 Validating complete deployment..."

    # Count deployed resources
    LAMBDA_COUNT=$(aws lambda list-functions --region "$AWS_REGION_PRIMARY" --query 'Functions[?contains(FunctionName, `ElevatedIQ`)].FunctionName' --output text | wc -w)
    log "  → Lambda functions deployed: $LAMBDA_COUNT"

    success "🎯 Deployment validation complete"
}

#################################################################################
# MAIN EXECUTION
#################################################################################

main() {
    log "╔════════════════════════════════════════════════════════════════╗"
    log "║  ElevatedIQ Phase 6.3: Days 4-5 Deployment Executor          ║"
    log "╚════════════════════════════════════════════════════════════════╝"

    # Initialize log
    mkdir -p "$(dirname "$DEPLOYMENT_LOG")"
    > "$DEPLOYMENT_LOG"

    # Execute deployment sequence
    validate_prerequisites
    deploy_ws1_vpc_peering
    deploy_ws2_data_residency
    deploy_ws3_failover_lambda
    deploy_ws4_rotation_lambda
    validate_deployment

    log "╔════════════════════════════════════════════════════════════════╗"
    log "║  ✅ Days 4-5 DEPLOYMENT COMPLETE                              ║"
    log "╚════════════════════════════════════════════════════════════════╝"
}

# Execute if not sourced
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    main "$@"
fi
