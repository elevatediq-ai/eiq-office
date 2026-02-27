#!/usr/bin/env bash
# ==============================================================================
# ElevatedIQ Secret Sync Utility (GSM to GitHub)
# ==============================================================================
# Purpose: Securely sync secrets from Google Secret Manager to GitHub Actions
# FedRAMP: NIST-AC-3 (Access Enforcement), NIST-IA-2 (Identification & Auth)
# ==============================================================================

set -euo pipefail

SECRET_NAME=${1:-"SNYK_TOKEN"}
REPO=${2:-"kushin77/ElevatedIQ-Mono-Repo"}

echo "🔐 Syncing secret '$SECRET_NAME' from GSM to GitHub repo '$REPO'..."

# 1. Verify gcloud auth
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
    echo "❌ ERROR: No active gcloud account. Please run 'gcloud auth login'."
    exit 1
fi

# 2. Fetch secret value from GSM
echo "📥 Fetching secret value from Google Secret Manager..."
SECRET_VALUE=$(gcloud secrets versions access latest --secret="$SECRET_NAME" 2>/dev/null || true)

if [[ -z "$SECRET_VALUE" ]]; then
    echo "❌ ERROR: Could not retrieve secret '$SECRET_NAME' from GSM."
    exit 1
fi

# 3. Verify gh CLI auth
if ! gh auth status &>/dev/null; then
    echo "❌ ERROR: gh CLI not authenticated. Please run 'gh auth login'."
    exit 1
fi

# 4. Set GitHub repository secret
echo "📤 Updating GitHub repository secret..."
echo "$SECRET_VALUE" | gh secret set "$SECRET_NAME" --repo "$REPO"

echo "✅ Successfully synced '$SECRET_NAME' to GitHub."
