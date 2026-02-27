#!/usr/bin/env bash
#####################################################################
# 🛡️ 10x Workspace Immune System (Self-Healing Structure)
# Purpose: Automatically detect/repair structural drift & compliance gaps
# Execution: Part of session initialization or pre-commit
#####################################################################
set -eb
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}🔍 [10x] Workspace Diagnostics & Auto-Healing...${NC}"

# 1. Enforce Symlinked Paths (No Drift)
declare -A PATHS=(
    ["scripts/pmo"]="scripts/automation/pmo"
    ["docs/pmo"]="docs/management"
)

for target in "${!PATHS[@]}"; do
    source="${PATHS[$target]}"
    if [ ! -L "$target" ] || [ "$(readlink -f $target)" != "$(readlink -f $source)" ]; then
        echo "  🩹 Healing structure: $target -> $source"
        rm -rf "$target"
        mkdir -p "$(dirname "$target")"
        if [ ! -d "$source" ]; then
             echo "  Source does not exist, creating: $source"
             mkdir -p "$source"
        fi
        ln -sf "$(realpath --relative-to="$(dirname "$target")" "$source")" "$target"
    fi
done

# 2. Enforce Permissions
echo "  🔒 Securing Permissions..."
find scripts/automation -name "*.sh" -exec chmod +x {} + 2>/dev/null || true
find scripts/automation -name "*.py" -exec chmod +x {} + 2>/dev/null || true

# 3. Cleanup Redundancy (Consolidation)
echo "  🧹 Cleaning up redundant scripts..."
# Remove misleading shims that conflict with real scripts
rm -f scripts/automation/shims/session_tracker.sh
rm -f scripts/automation/shims/10x_blocker_detection.sh
rm -f scripts/automation/shims/10x_blocker_detector.sh
# Remove deprecated PMO scripts
rm -f scripts/automation/pmo/10x_blocker_detection.sh

# 4. Validation Check
if [ -x "scripts/pmo/session_tracker.sh" ]; then
    echo -e "${GREEN}✅ Workspace is 10x Compliant.${NC}"
else
    echo -e "${RED}⚠️  Warning: scripts/pmo/session_tracker.sh verification failed.${NC}"
fi
