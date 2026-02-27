#!/bin/bash
# ElevatedIQ Terraform Drift Detector
# Purpose: Detect infrastructure drift and escalate immediately.
# Refs: #4256

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TF_DIR="${REPO_ROOT}/terraform/production"
LOG_FILE="${REPO_ROOT}/logs/terraform_drift.log"
ESCALATE_SCRIPT="${REPO_ROOT}/scripts/pmo/escalate_failure.sh"

echo "🔍 Starting Terraform Drift Detection..." | tee "$LOG_FILE"

if [ ! -d "$TF_DIR" ]; then
    echo "❌ Terraform directory not found: $TF_DIR" | tee -a "$LOG_FILE"
    exit 1
fi

cd "$TF_DIR"

# Initialize Terraform (non-interactive)
echo "⚙️ Initializing Terraform..."
terraform init -input=false > /dev/null

# Plan and check for changes
echo "running terraform plan..."
set +e
terraform plan -detailed-exitcode -out=tfplan > /dev/null 2>&1
EXIT_CODE=$?
set -e

if [ $EXIT_CODE -eq 0 ]; then
    echo "✅ No drift detected." | tee -a "$LOG_FILE"
elif [ $EXIT_CODE -eq 1 ]; then
    echo "❌ Error running terraform plan." | tee -a "$LOG_FILE"
    # Escalate Error
    "$ESCALATE_SCRIPT" "[CRITICAL] Terraform Plan Failed" "Terraform plan in $TF_DIR failed with errors. Check logs." "bug,priority-p0"
elif [ $EXIT_CODE -eq 2 ]; then
    echo "⚠️ Drift detected!" | tee -a "$LOG_FILE"
    # Escalate Drift
    DRIFT_SUMMARY=$(terraform show -no-color tfplan | grep -E "Plan:|#")
    "$ESCALATE_SCRIPT" "[SECURITY] Infrastructure Drift Detected" "Terraform detected unmanaged changes (Drift) in production:\n\n\`\`\`\n$DRIFT_SUMMARY\n\`\`\`\n\nPlease investigate immediately." "security,priority-p0"
fi
