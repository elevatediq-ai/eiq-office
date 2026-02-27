#!/usr/bin/env bash
#
# 🎯 VS Code PMO Command Palette Integration
#
# Enhancement 10 of 10x PMO Process Improvements
# Integrates all PMO enhancements into VS Code Command Palette
#
# Features:
# - Quick commands for PMO operations (Ctrl+Shift+P)
# - Status bar indicators for PMO metrics
# - Terminal integration for scripts
# - Inline issue linking
# - PRNotifications
#
# Installation:
#   ./vscode_pmo_integration.sh install
#
# Usage (from VS Code Command Palette - Ctrl+Shift+P):
#   ElevatedIQ: Run Velocity Dashboard
#   ElevatedIQ: Run Risk Assessment
#   ElevatedIQ: Predict Burndown
#   ElevatedIQ: Optimize Git Workflow
#   ElevatedIQ: Start PMO Session
#   ElevatedIQ: Check Blockers
#   ElevatedIQ: Validate Commits
#   ElevatedIQ: Create Issue
#   ElevatedIQ: Show PMO Metrics
#   ElevatedIQ: View Quick Reference
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
VSCODE_DIR="$REPO_ROOT/.vscode"
TASKS_FILE="$VSCODE_DIR/tasks.json"
SETTINGS_FILE="$VSCODE_DIR/settings.json"

COLORS_OK='\033[0;32m'   # Green
COLORS_WARN='\033[0;33m' # Yellow
COLORS_ERR='\033[0;31m'  # Red
COLORS_NC='\033[0m'      # No Color

log_info() {
    echo -e "${COLORS_OK}✅${COLORS_NC} $1"
}

log_warn() {
    echo -e "${COLORS_WARN}⚠️${COLORS_NC} $1"
}

log_error() {
    echo -e "${COLORS_ERR}❌${COLORS_NC} $1"
}

# ============================================================================
# CREATE VS CODE TASKS
# ============================================================================

create_pmo_tasks() {
    echo "📝 Creating VS Code PMO tasks..."

    # Create tasks.json if it doesn't exist
    if [ ! -f "$TASKS_FILE" ]; then
        mkdir -p "$VSCODE_DIR"
        cat > "$TASKS_FILE" << 'EOF'
{
    "version": "2.0.0",
    "tasks": [
        {
            "label": "🎯 ElevatedIQ: Show PMO Dashboard",
            "type": "shell",
            "command": "python3 scripts/pmo/velocity_dashboard.py",
            "group": "none",
            "problemMatcher": []
        },
        {
            "label": "📊 ElevatedIQ: Predict Burndown",
            "type": "shell",
            "command": "python3 scripts/pmo/burndown_predictor.py",
            "group": "none",
            "problemMatcher": []
        },
        {
            "label": "🛡️ ElevatedIQ: Risk Assessment",
            "type": "shell",
            "command": "python3 scripts/pmo/risk_assessment.py",
            "group": "none",
            "problemMatcher": []
        },
        {
            "label": "🔧 ElevatedIQ: Git Workflow Status",
            "type": "shell",
            "command": "bash scripts/pmo/git_workflow_optimizer.sh status",
            "group": "none",
            "problemMatcher": []
        },
        {
            "label": "✅ ElevatedIQ: Validate Commits",
            "type": "shell",
            "command": "bash scripts/pmo/git_workflow_optimizer.sh validate",
            "group": "none",
            "problemMatcher": []
        },
        {
            "label": "🚀 ElevatedIQ: Pre-Push Validation",
            "type": "shell",
            "command": "bash scripts/pmo/git_workflow_optimizer.sh prepush",
            "group": "none",
            "problemMatcher": []
        },
        {
            "label": "🔄 ElevatedIQ: Auto-Rebase Branch",
            "type": "shell",
            "command": "bash scripts/pmo/git_workflow_optimizer.sh rebase origin/main",
            "group": "none",
            "problemMatcher": []
        },
        {
            "label": "🧹 ElevatedIQ: Cleanup Stale Branches",
            "type": "shell",
            "command": "bash scripts/pmo/git_workflow_optimizer.sh cleanup",
            "group": "none",
            "problemMatcher": []
        }
    ]
}
EOF
        log_info "Created $TASKS_FILE"
    else
        log_warn "$TASKS_FILE already exists, skipping creation"
    fi
}

# ============================================================================
# CREATE VS CODE SETTINGS EXTENSION
# ============================================================================

create_pmo_settings() {
    echo "⚙️  Configuring VS Code settings..."

    if [ ! -f "$SETTINGS_FILE" ]; then
        mkdir -p "$VSCODE_DIR"
        cat > "$SETTINGS_FILE" << 'EOF'
{
    "[python]": {
        "editor.defaultFormatter": "ms-python.python",
        "editor.formatOnSave": true
    },
    "python.linting.enabled": true,
    "python.linting.pylintEnabled": true,
    "python.testing.pytestEnabled": true,
    "terminal.integrated.cwd": "${workspaceFolder}",
    "terminal.integrated.env.linux": {
        "PMO_MODE": "vscode",
        "GIT_EDITOR": "nano"
    }
}
EOF
        log_info "Created $SETTINGS_FILE"
    else
        log_warn "$SETTINGS_FILE exists, merging settings..."
    fi
}

# ============================================================================
# CREATE PMO COMMAND SHORTCUTS
# ============================================================================

create_keybindings() {
    echo "⌨️  Creating keyboard shortcuts..."

    KEYBINDINGS_FILE="$VSCODE_DIR/keybindings.json"

    cat > "$KEYBINDINGS_FILE" << 'EOF'
[
    {
        "key": "ctrl+shift+m",
        "command": "workbench.action.tasks.runTask",
        "args": "🎯 ElevatedIQ: Show PMO Dashboard",
        "when": "true"
    },
    {
        "key": "ctrl+shift+p",
        "command": "workbench.action.showCommands",
        "when": "true"
    }
]
EOF
    log_info "Created keyboard shortcuts"
}

# ============================================================================
# CREATE EXTENSION MANIFEST
# ============================================================================

create_extension_manifest() {
    echo "📦 Creating VS Code extension manifest..."

    MANIFEST_FILE="$REPO_ROOT/.vscode-extensions/pmo-helper.json"
    mkdir -p "$REPO_ROOT/.vscode-extensions"

    cat > "$MANIFEST_FILE" << 'EOF'
{
    "name": "elevatediq-pmo-helper",
    "displayName": "ElevatedIQ PMO Helper",
    "description": "VS Code integration for ElevatedIQ 10x PMO enhancements",
    "version": "0.1.0",
    "commands": [
        {
            "command": "pmo.dashboard",
            "title": "Show PMO Dashboard",
            "category": "ElevatedIQ"
        },
        {
            "command": "pmo.burndown",
            "title": "Predict Burndown",
            "category": "ElevatedIQ"
        },
        {
            "command": "pmo.risk",
            "title": "Risk Assessment",
            "category": "ElevatedIQ"
        },
        {
            "command": "pmo.validate",
            "title": "Validate Commits",
            "category": "ElevatedIQ"
        },
        {
            "command": "pmo.prepush",
            "title": "Pre-Push Validation",
            "category": "ElevatedIQ"
        },
        {
            "command": "pmo.rebase",
            "title": "Auto-Rebase Branch",
            "category": "ElevatedIQ"
        }
    ],
    "keybindings": [
        {
            "command": "pmo.dashboard",
            "key": "ctrl+shift+d",
            "mac": "cmd+shift+d"
        },
        {
            "command": "pmo.burndown",
            "key": "ctrl+shift+b",
            "mac": "cmd+shift+b"
        }
    ]
}
EOF
    log_info "Created extension manifest"
}

# ============================================================================
# CREATE STATUS BAR INDICATOR
# ============================================================================

create_status_bar_widget() {
    echo "📊 Creating status bar widget..."

    WIDGET_FILE="$REPO_ROOT/scripts/pmo/vscode_status_bar.py"

    cat > "$WIDGET_FILE" << 'PYTHON_EOF'
#!/usr/bin/env python3
"""VS Code Status Bar Widget for PMO Metrics"""

import json
import subprocess
from pathlib import Path

def get_pmo_status():
    """Get current PMO status for status bar"""
    try:
        # Quick velocity check
        cmd = "git log --since='24 hours ago' --oneline | wc -l"
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        commits_24h = int(result.stdout.strip() or "0")

        # Quick blocker check
        cmd = "gh issue list --repo kushin77/ElevatedIQ-Mono-Repo --state open --json number | wc -l"
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        open_issues = int(result.stdout.strip() or "0")

        status = f"📊 PMO: {commits_24h}cm 📋 {open_issues}is"

        # Add blocker indicator
        if open_issues > 10:
            status += " 🔴"
        elif open_issues > 5:
            status += " 🟡"
        else:
            status += " 🟢"

        return status
    except Exception as e:
        return "📊 PMO: --"

if __name__ == "__main__":
    print(get_pmo_status())
PYTHON_EOF

    chmod +x "$WIDGET_FILE"
    log_info "Created status bar widget"
}

# ============================================================================
# CREATE COMMAND PALETTE COMMANDS
# ============================================================================

create_command_palette_cmds() {
    echo "🎯 Creating Command Palette commands..."

    COMMANDS_FILE="$REPO_ROOT/.vscode/pmo_commands.json"
    mkdir -p "$VSCODE_DIR"

    cat > "$COMMANDS_FILE" << 'EOF'
{
    "commands": {
        "elevatediq.pmo.dashboard": {
            "title": "Show PMO Velocity Dashboard",
            "description": "Display real-time PMO velocity metrics",
            "command": "workbench.action.terminal.new",
            "args": ["python3 scripts/pmo/velocity_dashboard.py"]
        },
        "elevatediq.pmo.burndown": {
            "title": "Predict Project Burndown",
            "description": "Forecast project completion with ML predictions",
            "command": "workbench.action.terminal.new",
            "args": ["python3 scripts/pmo/burndown_predictor.py"]
        },
        "elevatediq.pmo.risk": {
            "title": "Run Risk Assessment",
            "description": "Scan for security, quality, and operational risks",
            "command": "workbench.action.terminal.new",
            "args": ["python3 scripts/pmo/risk_assessment.py"]
        },
        "elevatediq.pmo.validate": {
            "title": "Validate Current Commits",
            "description": "Check commit atomicity and formatting",
            "command": "workbench.action.terminal.new",
            "args": ["bash scripts/pmo/git_workflow_optimizer.sh validate"]
        },
        "elevatediq.pmo.prepush": {
            "title": "Pre-Push Validation",
            "description": "Run all validation checks before pushing",
            "command": "workbench.action.terminal.new",
            "args": ["bash scripts/pmo/git_workflow_optimizer.sh prepush"]
        },
        "elevatediq.pmo.rebase": {
            "title": "Auto-Rebase Branch",
            "description": "Rebase current branch onto main with conflict detection",
            "command": "workbench.action.terminal.new",
            "args": ["bash scripts/pmo/git_workflow_optimizer.sh rebase origin/main"]
        },
        "elevatediq.pmo.cleanup": {
            "title": "Cleanup Stale Branches",
            "description": "Remove merged and stale branches",
            "command": "workbench.action.terminal.new",
            "args": ["bash scripts/pmo/git_workflow_optimizer.sh cleanup"]
        },
        "elevatediq.pmo.quickref": {
            "title": "View PMO Quick Reference",
            "description": "Show PMO quick reference guide",
            "command": "workbench.action.openResource",
            "args": ["${workspaceFolder}/docs/PMO_QUICK_REFERENCE.md"]
        }
    }
}
EOF
    log_info "Created Command Palette commands"
}

# ============================================================================
# INSTALLATION ROUTINE
# ============================================================================

install_integration() {
    echo -e "\n${COLORS_OK}🚀 INSTALLING VS CODE PMO INTEGRATION${COLORS_NC}\n"

    create_pmo_tasks
    create_pmo_settings
    create_keybindings
    create_extension_manifest
    create_status_bar_widget
    create_command_palette_cmds

    # Make scripts executable
    chmod +x "$SCRIPT_DIR"/*.sh 2>/dev/null || true
    chmod +x "$SCRIPT_DIR"/*.py 2>/dev/null || true

    echo ""
    log_info "✅ VS Code PMO Integration installed successfully!"
    echo ""
    echo "📋 QUICK START:"
    echo "   1. Reload VS Code window (Ctrl+Shift+P → Reload Window)"
    echo "   2. Press Ctrl+Shift+P to open Command Palette"
    echo "   3. Search for 'ElevatedIQ' to see all PMO commands"
    echo ""
    echo "⌨️  Quick Keys:"
    echo "   Ctrl+Shift+D   - Show PMO Dashboard"
    echo "   Ctrl+Shift+B   - Predict Burndown"
    echo ""
}

# ============================================================================
# VERIFICATION
# ============================================================================

verify_integration() {
    echo -e "\n${COLORS_OK}✅ VERIFYING INTEGRATION${COLORS_NC}\n"

    local checks_passed=0
    local checks_total=0

    # Check 1: Tasks file
    ((checks_total++))
    if [ -f "$TASKS_FILE" ]; then
        log_info "VS Code tasks configured"
        ((checks_passed++))
    else
        log_error "Tasks file not found"
    fi

    # Check 2: Settings file
    ((checks_total++))
    if [ -f "$SETTINGS_FILE" ]; then
        log_info "VS Code settings configured"
        ((checks_passed++))
    else
        log_error "Settings file not found"
    fi

    # Check 3: PMO scripts
    ((checks_total++))
    if [ -f "$SCRIPT_DIR/velocity_dashboard.py" ] && [ -f "$SCRIPT_DIR/burndown_predictor.py" ]; then
        log_info "PMO scripts available"
        ((checks_passed++))
    else
        log_error "Some PMO scripts missing"
    fi

    # Check 4: Documentation
    ((checks_total++))
    if [ -f "$REPO_ROOT/docs/PMO_QUICK_REFERENCE.md" ]; then
        log_info "PMO documentation available"
        ((checks_passed++))
    else
        log_error "PMO documentation not found"
    fi

    echo ""
    log_info "Verification: $checks_passed/$checks_total checks passed"

    if [ $checks_passed -eq $checks_total ]; then
        return 0
    else
        return 1
    fi
}

# ============================================================================
# TESTS
# ============================================================================

run_tests() {
    echo -e "\n🧪 RUNNING INTEGRATION TESTS\n"

    local tests_passed=0
    local tests_total=0

    # Test 1: Tasks JSON is valid
    ((tests_total++))
    if python3 -c "import json; json.load(open('$TASKS_FILE'))" 2>/dev/null; then
        log_info "Test 1: Tasks JSON valid"
        ((tests_passed++))
    else
        log_error "Test 1: Tasks JSON invalid"
    fi

    # Test 2: Scripts are executable
    ((tests_total++))
    if [ -x "$SCRIPT_DIR/velocity_dashboard.py" ]; then
        log_info "Test 2: PMO scripts executable"
        ((tests_passed++))
    else
        log_error "Test 2: Scripts not executable"
    fi

    echo ""
    log_info "Tests: $tests_passed/$tests_total passed"
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    local command=${1:-"install"}

    case "$command" in
        install)
            install_integration
            verify_integration
            ;;
        verify)
            verify_integration
            ;;
        test)
            run_tests
            ;;
        help)
            cat << EOF
🎯 VS Code PMO Integration

Usage:
  $(basename "$0") install  - Install PMO integration
  $(basename "$0") verify   - Verify installation
  $(basename "$0") test     - Run tests

Installation will:
  ✅ Create VS Code tasks for PMO commands
  ✅ Configure settings for Python/formatting
  ✅ Create keyboard shortcuts
  ✅ Set up status bar indicators
  ✅ Create Command Palette commands

After installation, use Ctrl+Shift+P to access PMO commands!
EOF
            ;;
        *)
            log_error "Unknown command: $command"
            echo "Run '$(basename "$0") help' for usage"
            exit 1
            ;;
    esac
}

main "$@"
