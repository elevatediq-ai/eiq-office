#!/usr/bin/env bash
set -euo pipefail

REPO_PATH="/home/akushnir/ElevatedIQ-Mono-Repo"
ENV_DIR="infrastructure/terraform/environments/cicd"
ISSUE_PARENT=6105
PLAN_FILE=tfplan

cd "$REPO_PATH"
./scripts/pmo/host_awareness_check.sh || true

# Support sourcing from .env or aws-credentials.env
for f in .env aws-credentials.env; do
  if [[ -f "$f" ]]; then
     echo "🔍 Sourcing $f..."
     # use specific grep to avoid accidental export of wrong values
     export $(grep -v '^#' "$f" | grep -E 'VAULT_|AWS_' | xargs) || true
  fi
done

# Helper: post comment to issue
post_issue(){
  local msg="$1"
  gh issue comment "$ISSUE_PARENT" --body "$msg" || true
}

# Try multiple credential discovery strategies
cred_ok=0

# 1. Environment AWS vars
if [[ -n "${AWS_ACCESS_KEY_ID:-}" && -n "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
  cred_ok=1
  post_issue "Phase 5 auto-run: Using AWS env vars present on host."
fi

# 2. AWS CLI call (instance role or credentials)
if [[ $cred_ok -eq 0 ]]; then
  if command -v aws >/dev/null 2>&1; then
    if aws sts get-caller-identity >/dev/null 2>&1; then
      cred_ok=1
      post_issue "Phase 5 auto-run: AWS CLI able to fetch caller identity (instance role or credentials available)."
    fi
  fi
fi

# 3. Vault: AppRole or token
if [[ $cred_ok -eq 0 ]]; then
  if [[ -n "${VAULT_ADDR:-}" ]]; then
    # prefer token if available
    if [[ -n "${VAULT_TOKEN:-}" ]]; then
      # attempt to read secret path
      if command -v vault >/dev/null 2>&1; then
        set +e
        secret_json=$(vault kv get -format=json secret/data/elevatediq/aws 2>/dev/null)
        set -e
        if [[ -n "$secret_json" ]]; then
          AWS_ACCESS_KEY_ID=$(echo "$secret_json" | jq -r '.data.data.AWS_ACCESS_KEY_ID')
          AWS_SECRET_ACCESS_KEY=$(echo "$secret_json" | jq -r '.data.data.AWS_SECRET_ACCESS_KEY')
          export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
          cred_ok=1
          post_issue "Phase 5 auto-run: Retrieved AWS creds from Vault using VAULT_TOKEN."
        fi
      fi
    fi
    # AppRole method via curl (no CLI dependency)
    if [[ $cred_ok -eq 0 && -n "${VAULT_ROLE_ID:-}" && -n "${VAULT_SECRET_ID:-}" ]]; then
      if command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
        set +e
        # Step 1: Authenticate via AppRole
        VAULT_LOGIN_RESP=$(curl -s -X POST \
          "${VAULT_ADDR}/v1/auth/approle/login" \
          -H "Content-Type: application/json" \
          -d "{\"role_id\":\"${VAULT_ROLE_ID}\",\"secret_id\":\"${VAULT_SECRET_ID}\"}"  )

        if [[ -n "$VAULT_LOGIN_RESP" ]]; then
          VAULT_TOKEN=$(echo "$VAULT_LOGIN_RESP" | jq -r '.auth.client_token // empty')
          if [[ -n "$VAULT_TOKEN" ]]; then
            # Step 2: Retrieve AWS credentials from AWS secret engine
            echo "🔍 VAULT: Token retrieved, fetching AWS credentials..."
            AWS_CREDS=$(curl -s -X GET \
              "${VAULT_ADDR}/v1/aws/creds/terraform-role" \
              -H "X-Vault-Token: ${VAULT_TOKEN}" )

            if [[ -n "$AWS_CREDS" ]]; then
              AWS_ACCESS_KEY_ID=$(echo "$AWS_CREDS" | jq -r '.data.access_key // empty')
              AWS_SECRET_ACCESS_KEY=$(echo "$AWS_CREDS" | jq -r '.data.secret_key // empty')

              if [[ -n "$AWS_ACCESS_KEY_ID" && -n "$AWS_SECRET_ACCESS_KEY" ]]; then
                export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY VAULT_TOKEN
                cred_ok=1
                post_issue "✅ Phase 5 auto-run: Retrieved AWS credentials from Vault AppRole (aws/creds/terraform-role)"
              else
                echo "❌ VAULT: AWS credential extraction failed"
                post_issue "⚠️ Phase 5 auto-run: Vault AppRole authentication succeeded but AWS credential extraction failed."
              fi
            else
              echo "❌ VAULT: Failed to call aws/creds/terraform-role"
              post_issue "⚠️ Phase 5 auto-run: Vault AppRole auth succeeded but could not reach /aws/creds/terraform-role"
            fi
          else
            echo "❌ VAULT: Login response did not contain client_token"
            post_issue "⚠️ Phase 5 auto-run: Vault login response did not contain a client_token."
          fi
        else
          echo "❌ VAULT: Login call failed (empty response)"
          post_issue "⚠️ Phase 5 auto-run: Vault AppRole login call failed (empty response)."
        fi
        set -e
      fi
    fi
  fi
fi

if [[ $cred_ok -ne 1 ]]; then
  post_issue "Phase 5 auto-run: No valid cloud credentials found on host. Auto-run aborted.\nPlease provision AWS credentials (env or ~/.aws/credentials) or configure Vault access (VAULT_ADDR + VAULT_TOKEN or AppRole). See #6105 for details."
  echo "❌ No credentials found; aborting"
  exit 2
fi

# Setup cleanup trap (remove AWS credentials on exit)
cleanup_credentials(){
  if [[ -n "${AWS_ACCESS_KEY_ID:-}" ]]; then
    unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
    post_issue "🧹 Phase 5 cleanup: AWS credentials cleared from environment"
  fi
}
trap cleanup_credentials EXIT

# Ensure terraform exists
if ! command -v terraform >/dev/null 2>&1; then
  post_issue "Phase 5 auto-run: Terraform not installed on host. Install terraform and re-run."
  echo "terraform not installed"
  exit 3
fi

cd "$ENV_DIR"
post_issue "🚀 Phase 5 auto-run started on $(hostname). Initializing Terraform backend with retrieved credentials..."
terraform init -input=false -reconfigure
terraform plan -input=false -out=$PLAN_FILE -var-file=prod.tfvars  2>&1 | tee plan_audit.log
terraform show -no-color $PLAN_FILE > plan_offline.txt
GIST_URL=$(gh gist create plan_offline.txt -d "Phase 5 Terraform plan (cicd) [OFFLINE]" --public --jq '.html_url' 2>/dev/null || true)

post_issue "✅ Phase 5 auto-run completed on $(hostname). Plan generated: ${GIST_URL:-(gist creation failed)}\n\n**Next Steps:**\n1. Review plan at: ${GIST_URL}\n2. Approve via: \`/approve phase-5\` comment\n3. Apply via: \`terraform apply -input=false $PLAN_FILE\`\n\n**NIST Controls Honored:** SC-7 (zero-trust credentials), SC-3 (AppRole access control), AU-2 (Vault audit logs)"

echo "✅ Phase 5 Terraform plan completed"
echo "📊 Plan URL: $GIST_URL"
exit 0
