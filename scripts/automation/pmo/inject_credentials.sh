#!/bin/bash
# [NIST-AC-2, NIST-IA-2] Credential Injection System
# Wraps the Python CredentialManager to export environment variables for shell sessions.

set -e

CLOUD_PROVIDER=${1:-"gcp"}
ENV=${2:-"dev"}

echo "🔐 Injecting $CLOUD_PROVIDER credentials for $ENV environment..."

# Ensure we are in the repo root or can find the libs
REPO_ROOT=$(git rev-parse --show-toplevel)
export PYTHONPATH="$PYTHONPATH:$REPO_ROOT"

# Run Python helper to fetch secrets and formatting them for export
# We Use a small python snippet to interact with our CredentialManager
CREDS_OUTPUT=$(python3 - <<EOF
import os
import sys
from libs.security.credential_manager import CredentialManager

mgr = CredentialManager(environment="$ENV")

try:
    if "$CLOUD_PROVIDER" == "gcp":
        secret_id = os.getenv("TF_GCP_SECRET_ID", "terraform-provisioner-key")
        try:
            creds = mgr.get_gcp_secret(secret_id)
            # Preserve structure for shell export
            print(f"export GOOGLE_CREDENTIALS='{creds}'")
            print("echo '✅ GOOGLE_CREDENTIALS injected via [GCP/AWS Fallback]'")
        except Exception as e:
            print(f"echo '❌ Fatal: Could not retrieve GCP credentials: {str(e)}'", file=sys.stderr)
            sys.exit(1)
    elif "$CLOUD_PROVIDER" == "aws":
        secret_id = os.getenv("TF_AWS_SECRET_ID", "terraform-provisioner-aws")
        creds = mgr.get_aws_secret(secret_id)
        print(f"export AWS_ACCESS_KEY_ID='{creds['access_key']}'")
        print(f"export AWS_SECRET_ACCESS_KEY='{creds['secret_key']}'")
        print("echo '✅ AWS_CREDENTIALS exported'")
except Exception as e:
    print(f"echo '❌ Error: {str(e)}'", file=sys.stderr)
    sys.exit(1)
EOF
)

if [ $? -eq 0 ]; then
    # WARNING: This evaluates the output to export variables in the current subshell
    # Usage: eval $(./scripts/pmo/inject_credentials.sh gcp)
    echo "$CREDS_OUTPUT"
else
    echo "FAILED to retrieve credentials."
    exit 1
fi
