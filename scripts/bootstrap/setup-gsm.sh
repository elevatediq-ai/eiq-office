#!/usr/bin/env bash
# Bootstrap helper for setting up Google Secret Manager and Workload Identity for GitHub Actions
# Usage: ./scripts/bootstrap/setup-gsm.sh <PROJECT_ID> <WIF_POOL_NAME> <WIF_PROVIDER_NAME> <GITHUB_ORG>

set -euo pipefail

PROJECT_ID=${1:-""}
WIF_POOL=${2:-"github-pool"}
WIF_PROVIDER=${3:-"github-provider"}
GITHUB_ORG=${4:-"your-gh-org"}

if [[ -z "$PROJECT_ID" ]]; then
  echo "Usage: $0 <PROJECT_ID> [WIF_POOL] [WIF_PROVIDER] [GITHUB_ORG]"
  exit 1
fi

echo "Setting up Secret Manager and Workload Identity for project: $PROJECT_ID"

# 1) Enable Secret Manager API
if ! gcloud services list --enabled --project="$PROJECT_ID" --filter="name:secretmanager.googleapis.com" --format="value(name)" | grep -q secretmanager; then
  echo "Enabling Secret Manager API..."
  gcloud services enable secretmanager.googleapis.com --project="$PROJECT_ID"
else
  echo "Secret Manager API already enabled"
fi

# 2) Create a service account for GitHub Actions to impersonate
SA_NAME="sa-ci-gsm"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
if ! gcloud iam service-accounts list --project="$PROJECT_ID" --format="value(email)" | grep -q "$SA_EMAIL"; then
  echo "Creating service account: $SA_EMAIL"
  gcloud iam service-accounts create "$SA_NAME" --project="$PROJECT_ID" --display-name="CI GSM accessor"
else
  echo "Service account exists: $SA_EMAIL"
fi

# 3) Grant the minimal Secret Manager role
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:$SA_EMAIL" \
  --role="roles/secretmanager.secretAccessor" || true

# 4) Create Workload Identity Pool and Provider (idempotent)
# NOTE: Adjust provider config for your GitHub org and repos per GCP docs
if ! gcloud iam workload-identity-pools describe "$WIF_POOL" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "Creating Workload Identity Pool: $WIF_POOL"
  gcloud iam workload-identity-pools create "$WIF_POOL" --project="$PROJECT_ID" --location="global" --display-name="GitHub Actions pool"
else
  echo "Workload Identity Pool exists: $WIF_POOL"
fi

if ! gcloud iam workload-identity-pools providers describe "$WIF_PROVIDER" --project="$PROJECT_ID" --location="global" --workload-identity-pool="$WIF_POOL" >/dev/null 2>&1; then
  echo "Creating Workload Identity Provider: $WIF_PROVIDER"
  echo "Please update the 'issuer-uri' and 'allowed_subjects' values per your GitHub org/repo."
  # The following is an example and may need updating for your org
  gcloud iam workload-identity-pools providers create-oidc "$WIF_PROVIDER" \
    --project="$PROJECT_ID" --location="global" --workload-identity-pool="$WIF_POOL" \
    --display-name="GitHub Actions Provider" \
    --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor" \
    --issuer-uri="https://token.actions.githubusercontent.com" \
    --allowed-audiences="https://github.com/$GITHUB_ORG"
else
  echo "Workload Identity Provider exists: $WIF_PROVIDER"
fi

# 5) Allow the WIF provider to impersonate the SA
POOL_RESOURCE="projects/$PROJECT_ID/locations/global/workloadIdentityPools/$WIF_POOL/providers/$WIF_PROVIDER"

gcloud iam service-accounts add-iam-policy-binding "$SA_EMAIL" \
  --project="$PROJECT_ID" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://$POOL_RESOURCE"

cat <<EOF

Bootstrap completed. Next steps:
- Create required secrets in GSM: use 'gcloud secrets create <NAME> --data-file=- --project=$PROJECT_ID'
- Update GitHub Actions with 'google-github-actions/auth@v2' using the Workload Identity config
- Example GH Action snippet available in .github/workflows/ci-gsm-example.yml
EOF
