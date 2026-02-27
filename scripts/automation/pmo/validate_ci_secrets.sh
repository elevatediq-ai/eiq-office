#!/bin/bash
# 🔐 ElevatedIQ: CI/CD Secrets Provisioning & Validation Utility
# NIST-AC-3, NIST-IA-2 Aligned.
# This script guides the user through provisioning secrets needed for Phase 11.

set -e

REPO="kushin77/ElevatedIQ-Mono-Repo"

echo "🔐 ElevatedIQ CI/CD Secrets Setup Guide"
echo "========================================="
echo "This script identifies missing secrets for GitHub Actions."
echo ""

declare -a SECRETS=("GOOGLE_CREDENTIALS" "AWS_ACCESS_KEY_ID" "AWS_SECRET_ACCESS_KEY" "AZURE_CREDENTIALS" "SLACK_WEBHOOK_URL")

MISSING=0
for secret in "${SECRETS[@]}"; do
    if gh secret list --repo "$REPO" | grep -q "$secret"; then
        echo "✅ Secret found: $secret"
    else
        echo "❌ Secret MISSING: $secret"
        ((MISSING++))
    fi
done

echo ""
if [ $MISSING -eq 0 ]; then
    echo "🎉 All CI/CD secrets are provisioned! You can now run the Terraform deployment."
    echo "Recommendation: Proceed to Issue #2832."
else
    echo "⚠️ $MISSING secrets are missing from GitHub."
    echo "To provision them, run the following commands with your account credentials:"
    echo ""
    echo "  gh secret set GOOGLE_CREDENTIALS --repo $REPO < path/to/gcp-sa-key.json"
    echo "  echo \"your-aws-key\" | gh secret set AWS_ACCESS_KEY_ID --repo $REPO"
    echo "  echo \"your-aws-secret\" | gh secret set AWS_SECRET_ACCESS_KEY --repo $REPO"
    echo "  gh secret set AZURE_CREDENTIALS --repo $REPO < path/to/azure-sp.json"
    echo ""
    echo "Once complete, run this script again to validate."
fi

# Audit Log entry
./scripts/pmo/session_tracker.sh update issue "Ran CI Secrets Validation. $MISSING missing secrets identified."
