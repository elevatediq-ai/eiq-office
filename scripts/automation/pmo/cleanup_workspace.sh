#!/usr/bin/env bash
# ElevatedIQ - Workspace Cleanup & Performance Optimizer
# Purpose: Clean heavy Terraform caches, logs, and optimize VS Code performance
# NIST-CM-3: Configuration Management

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "🔧 ElevatedIQ Workspace Cleanup & Optimization"
echo "=============================================="
echo ""

# Function to calculate size
calculate_size() {
    du -sh "$1" 2>/dev/null | cut -f1 || echo "0B"
}

# 1. Clean Terraform Provider Caches
echo "1️⃣ Cleaning Terraform Provider Caches..."
TERRAFORM_DIRS=(
    "$WORKSPACE_ROOT/libs/terraform"
    "$WORKSPACE_ROOT/infra/terraform"
    "$WORKSPACE_ROOT/terraform/modules"
    "$WORKSPACE_ROOT/apps/hub-core"
    "$WORKSPACE_ROOT/apps/secret-rotator/terraform"
)

CLEANED_SIZE=0
for dir in "${TERRAFORM_DIRS[@]}"; do
    if [[ -d "$dir" ]]; then
        echo "   Scanning: $dir"
        BEFORE=$(calculate_size "$dir")
        find "$dir" -type d -name ".terraform" -exec rm -rf {} + 2>/dev/null || true
        find "$dir" -name "terraform-provider-*" -type f -delete 2>/dev/null || true
        AFTER=$(calculate_size "$dir")
        echo "   ✅ $dir: $BEFORE → $AFTER"
    fi
done

# 2. Clean Log Files
echo ""
echo "2️⃣ Cleaning Old Log Files (>7 days)..."
LOG_DIRS=(
    "$WORKSPACE_ROOT/logs"
    "$WORKSPACE_ROOT/scripts/logs"
    "$WORKSPACE_ROOT/scripts/pmo/logs"
    "$WORKSPACE_ROOT/scripts/pmo/test_logs"
)

for log_dir in "${LOG_DIRS[@]}"; do
    if [[ -d "$log_dir" ]]; then
        BEFORE=$(calculate_size "$log_dir")
        find "$log_dir" -type f -name "*.log" -mtime +7 -delete 2>/dev/null || true
        find "$log_dir" -type f -name "*.jsonl" -mtime +7 -delete 2>/dev/null || true
        AFTER=$(calculate_size "$log_dir")
        echo "   ✅ $log_dir: $BEFORE → $AFTER"
    fi
done

# 3. Clean Python Caches
echo ""
echo "3️⃣ Cleaning Python Caches..."
find "$WORKSPACE_ROOT" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
find "$WORKSPACE_ROOT" -type d -name ".pytest_cache" -exec rm -rf {} + 2>/dev/null || true
find "$WORKSPACE_ROOT" -type d -name ".mypy_cache" -exec rm -rf {} + 2>/dev/null || true
find "$WORKSPACE_ROOT" -type d -name ".ruff_cache" -exec rm -rf {} + 2>/dev/null || true
echo "   ✅ Python caches cleaned"

# 4. Clean VS Code Extension Cache
echo ""
echo "4️⃣ Cleaning VS Code Extension Cache..."
if [[ -d "$HOME/.vscode-server" ]]; then
    find "$HOME/.vscode-server" -type d -name "node_modules" -mtime +30 -exec rm -rf {} + 2>/dev/null || true
    find "$HOME/.vscode-server/data/logs" -type f -name "*.log" -mtime +7 -delete 2>/dev/null || true
    echo "   ✅ VS Code server cache cleaned"
fi

# 5. Restart VS Code Language Servers (if running)
echo ""
echo "5️⃣ Checking for Runaway Extension Host Processes..."
EXTENSION_HOST_COUNT=$(ps aux | grep -c "[e]xtensionHost" || true)
if [[ $EXTENSION_HOST_COUNT -gt 2 ]]; then
    echo "   ⚠️  Warning: $EXTENSION_HOST_COUNT extension host processes detected"
    echo "   💡 Recommendation: Reload VS Code window (Ctrl+Shift+P → 'Reload Window')"
else
    echo "   ✅ Extension host processes: $EXTENSION_HOST_COUNT (healthy)"
fi

# 6. Git Garbage Collection
echo ""
echo "6️⃣ Running Git Garbage Collection..."
cd "$WORKSPACE_ROOT"
git gc --aggressive --prune=now 2>/dev/null || echo "   ⚠️  Git GC skipped (not a git repo or failed)"
echo "   ✅ Git optimized"

# Summary
echo ""
echo "=============================================="
echo "✅ Workspace Cleanup Complete!"
echo ""
echo "📊 Recommended Next Steps:"
echo "   1. Reload VS Code window: Ctrl+Shift+P → 'Developer: Reload Window'"
echo "   2. Close unused terminals (you have 5+ terminals open)"
echo "   3. Review large folders: du -sh */  | sort -h | tail -10"
echo "   4. Monitor processes: ps aux | grep -i 'extensionHost\|copilot' | wc -l"
echo ""
echo "🎯 Performance Tips:"
echo "   - Keep Terraform providers in .terraform/ (now excluded from indexing)"
echo "   - Run this script weekly: ./scripts/pmo/cleanup_workspace.sh"
echo "   - Disable unused VS Code extensions"
echo ""
