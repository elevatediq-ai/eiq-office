#!/usr/bin/env bash
set -euo pipefail

REPO_PATH="/home/akushnir/ElevatedIQ-Mono-Repo"
ENV_DIR="infrastructure/terraform/environments/cicd"
ISSUE_PARENT=6105
GIST_DESC="Phase 5 Terraform plan (cicd)"

cd "$REPO_PATH"

# Host awareness
./scripts/pmo/host_awareness_check.sh || true

# Ensure Terraform is installed
if ! command -v terraform >/dev/null 2>&1; then
  echo "ERROR: terraform not installed on this host"
  gh issue comment "$ISSUE_PARENT" --body "Phase 5 runbook attempted on $(hostname) but terraform is not installed. Please install terraform version >= required and re-run the plan."
  exit 2
fi

cd "$ENV_DIR"

# Credential checks
CRED_OK=0
if [[ -n "${AWS_ACCESS_KEY_ID:-}" && -n "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
  CRED_OK=1
fi

if command -v aws >/dev/null 2>&1; then
  if aws sts get-caller-identity >/dev/null 2>&1; then
    CRED_OK=1
  fi
fi

if [[ -f "$HOME/.aws/credentials" ]]; then
  if grep -q "aws_access_key_id" "$HOME/.aws/credentials"; then
    CRED_OK=1
  fi
fi

if [[ "$CRED_OK" -ne 1 ]]; then
  echo "ERROR: No valid cloud credentials found on host"
  gh issue comment "$ISSUE_PARENT" --body "Phase 5 runbook attempted on $(hostname) but no valid cloud credentials were found (env / aws cli / instance role). Please provision credentials on the host or provide a secure Vault retrieval method. See recommended commands in #6105."
  exit 3
fi

# Initialize and plan
echo "Running terraform init and plan (no apply)"
terraform init -input=false
PLAN_OUT=tfplan
terraform plan -input=false -out="$PLAN_OUT" -var-file=prod.tfvars

# Export plan to human-readable text
terraform show -no-color "$PLAN_OUT" > plan.txt

# Create a gist for the plan (so reviewers can view full output)
GIST_URL=$(gh gist create plan.txt -d "$GIST_DESC" --public --jq '.html_url' 2>/dev/null || true)

# Create approval issue
ISSUE_BODY="Phase 5 Terraform plan (environment: cicd) generated on $(hostname)\n\nPlan gist: ${GIST_URL:-(gist creation failed; see repo plan.txt)}\n\nTo approve and apply run:\n\n\`ssh akushnir@192.168.168.42 'cd $REPO_PATH/$ENV_DIR && terraform apply -input=false $PLAN_OUT'\`\n\nThis is an automated proposal for Phase 5 (OAuth2 hardening + WAF). Review before applying."

gh issue create --title "Phase 5: Terraform Plan Proposal (cicd)" --body "$ISSUE_BODY" --label pmo,phase-5,needs-approval || true

echo "Plan generated and proposal issue created. Gist: $GIST_URL"
exit 0
