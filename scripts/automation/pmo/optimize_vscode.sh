#!/usr/bin/env bash
# ==============================================================================
# 🛠️ ElevatedIQ VS Code Optimizer
# ==============================================================================
# Purpose: Apply enterprise-grade settings for Mono-Repo stability.
# ==============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SETTINGS_FILE="${REPO_ROOT}/.vscode/settings.json"

echo "🚀 Optimizing VS Code for ElevatedIQ Mono-Repo..."

if [ ! -f "$SETTINGS_FILE" ]; then
    echo "Creating .vscode/settings.json..."
    mkdir -p "${REPO_ROOT}/.vscode"
    echo "{}" > "$SETTINGS_FILE"
fi

# Use python to safely update the JSON if available, otherwise use a temporary hack or simple overwrite
# Given we are in a Python-heavy repo, let's use a small python snippet to merge settings.

python3 - <<EOF
import json
import os

path = "$SETTINGS_FILE"
with open(path, 'r') as f:
    try:
        data = json.load(f)
    except:
        data = {}

# Enterprise Exclusions
data["files.exclude"] = {
    **data.get("files.exclude", {}),
    "**/.git": True,
    "**/__pycache__": True,
    "**/.pytest_cache": True,
    "**/.mypy_cache": True,
    "test_venv/": True,
    "test_audit_venv/": True,
    "temp_audit_venv/": True,
    "**/venv": True,
    "**/.venv": True,
    "**/.ci-venv": True,
    "**/node_modules": True,
    "**/dist": True,
    "**/build": True,
    "**/htmlcov": True,
    "**/.coverage": True,
    "**/.tox": True,
    "**/.nox": True,
    "**/.ruff_cache": True,
    "**/.terraform": True,
    "**/.terraform.lock.hcl": True,
    "**/*.tfstate*": True,
    "**/logs/**": True,
    "**/test_logs/**": True,
    "_archived/": True,
    "_unorganized/": True,
    "artifacts/": True,
    "data/": True,
    "datasets/": True,
    "test_data/": True,
    "apps/control-plane-go/rust-kernel": True
}

data["search.exclude"] = {
    **data.get("search.exclude", {}),
    "**/node_modules": True,
    "**/bower_components": True,
    "**/*.code-search": True,
    "test_venv/": True,
    "test_audit_venv/": True,
    "temp_audit_venv/": True,
    "**/venv": True,
    "**/.venv": True,
    "**/.ci-venv": True,
    "**/htmlcov": True,
    "**/.terraform": True,
    "**/.terraform.lock.hcl": True,
    "**/*.tfstate*": True,
    "**/logs/**": True,
    "_archived/": True,
    "_unorganized/": True,
    "artifacts/": True,
    "data/": True,
    "datasets/": True,
    "test_data/": True
}

data["files.watcherExclude"] = {
    **data.get("files.watcherExclude", {}),
    "**/.git/objects/**": True,
    "**/.git/subtree-cache/**": True,
    "**/node_modules/**": True,
    "**/dist/**": True,
    "test_venv/**": True,
    "test_audit_venv/**": True,
    "temp_audit_venv/**": True,
    "**/venv/**": True,
    "**/.venv/**": True,
    "**/.ci-venv/**": True,
    "**/htmlcov/**": True,
    "**/.terraform/**": True,
    "**/logs/**": True,
    "**/test_logs/**": True,
    "_archived/**": True,
    "_unorganized/**": True,
    "artifacts/**": True,
    "data/**": True,
    "datasets/**": True,
    "test_data/**": True,
    "**/__pycache__/**": True,
    "**/.pytest_cache/**": True,
    "**/.mypy_cache/**": True,
    "**/venv/**": True,
    "**/.venv/**": True
}

# Performance Settings
data["git.autorefresh"] = False
data["git.fetchOnPull"] = True
data["editor.minimap.enabled"] = False
data["workbench.list.smoothScanning"] = True

with open(path, 'w') as f:
    json.dump(data, f, indent=2)
EOF

echo "✅ VS Code settings optimized for maximum resilience."
echo "💡 Tip: Restart VS Code or run 'Developer: Restart Extension Host' to apply watcher changes."
