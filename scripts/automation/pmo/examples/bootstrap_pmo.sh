#!/usr/bin/env bash
# ==============================================================================
# PMO Bootstrap Fallback - Minimal Issue Creation
# ==============================================================================
# Purpose: Minimal script to verify PMO capabilities in a new repo
# ==============================================================================

set -euo pipefail

# Find repo root
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

# Source library if available
if [ -f "${REPO_ROOT}/scripts/pmo/lib/common.sh" ]; then
    source "${REPO_ROOT}/scripts/pmo/lib/common.sh"
else
    echo "ERROR: PMO library not found at ${REPO_ROOT}/scripts/pmo/lib/common.sh"
    echo "Run scripts/pmo/install.sh first."
    exit 1
fi

# Example Usage
echo "🚀 Bootstrapping PMO Example..."

pmo_create_issue "[TEST] PMO Subsystem Verified" \
"This issue was created by the PMO bootstrap fallback script.
It confirms that:
1. scripts/pmo/lib/common.sh is successfully sourced.
2. gh CLI is configured and authenticated.
3. REPO variable is correctly set." \
"pmo-test,bootstrap"

echo "✅ Bootstrap verification complete."
