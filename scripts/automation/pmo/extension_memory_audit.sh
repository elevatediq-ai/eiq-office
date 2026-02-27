#!/usr/bin/env bash
# =============================================================================
# Extension Memory Audit Tool
# =============================================================================
# Identifies memory-hungry extensions and provides remediation suggestions
# NIST: SI-2 (Flaw Remediation), CM-6 (Configuration Settings)
# Issues: #4731, #3116, #2033
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/logs/extension_audit.log"
mkdir -p "$(dirname "$LOG_FILE")"

ts() { date '+%Y-%m-%d %H:%M:%S'; }
log() { echo "[$(ts)] $*" | tee -a "$LOG_FILE"; }

log "🔍 Extension Memory Audit — $(ts)"
log "====================================="

# ──────────────────────────────────────────────────────────────────────────────
# PART 1: Measure current extensions running
# ──────────────────────────────────────────────────────────────────────────────
log ""
log "📊 ACTIVE EXTENSION PROCESSES:"
log "───────────────────────────────"

ps aux --no-headers 2>/dev/null | awk '
  /pylance|pyright|terraform-ls|spell-checker|cSpell|node/ && !/grep/ {
    pid=$2
    mem_mb=int($6/1024)
    cmd=$11

    if (/(pylance|pyright)/) name="Pylance-LSP"
    else if (/terraform-ls/) name="Terraform-LS"
    else if (/(spell|cSpell)/) name="cSpell"
    else if (/type=extensionHost/) name="ExtensionHost"
    else name=$11

    printf "%-20s PID=%6d RSS=%6dMB  %s\n", name, pid, mem_mb, substr($11, 0, 60)
  }
' | sort -k5 -rn | tee -a "$LOG_FILE"

# ──────────────────────────────────────────────────────────────────────────────
# PART 2: Check installed extensions
# ──────────────────────────────────────────────────────────────────────────────
log ""
log "📦 INSTALLED EXTENSIONS (vs. allowlist):"
log "───────────────────────────────────────"

VSCODE_EXT_DIR="$HOME/.vscode-server/extensions"

if [[ -d "$VSCODE_EXT_DIR" ]]; then
  local allowed=(
    "ms-python.python"
    "ms-python.vscode-pylance"
    "charliermarsh.ruff"
    "hashicorp.terraform"
    "ms-vscode.makefile-tools"
    "github.copilot"
    "github.copilot-chat"
  )

  echo "✓ ALLOWED (should be installed):"
  for ext in "${allowed[@]}"; do
    if [[ -d "$VSCODE_EXT_DIR/$ext"-* ]]; then
      size_kb=$(du -sk "$VSCODE_EXT_DIR/$ext"-* 2>/dev/null | awk '{print $1}')
      size_mb=$((size_kb / 1024))
      echo "  ✓ $ext (${size_mb}MB)"
    else
      echo "  ⚠ $ext (NOT INSTALLED)"
    fi
  done | tee -a "$LOG_FILE"

  echo ""
  echo "❌ PROBLEMATIC (should be disabled):" | tee -a "$LOG_FILE"
  local problematic=(
    "continue.continue"
    "ms-vscode.test-explorer-ui"
    "orta.vscode-jest"
    "hbenl.vscode-test-explorer"
    "sonarsource.sonarlint-vscode"
    "ms-vscode-remote.remote-ssh-edit"
    "eamodio.gitlens"
    "codemetrics.codemetrics"
  )

  for ext in "${problematic[@]}"; do
    if [[ -d "$VSCODE_EXT_DIR/$ext"-* ]]; then
      size_kb=$(du -sk "$VSCODE_EXT_DIR/$ext"-* 2>/dev/null | awk '{print $1}')
      size_mb=$((size_kb / 1024))
      echo "  ❌ $ext (${size_mb}MB) — DISABLE IMMEDIATELY" | tee -a "$LOG_FILE"
    fi
  done
else
  log "ℹ️ No VS Code extensions directory found at $VSCODE_EXT_DIR"
fi

# ──────────────────────────────────────────────────────────────────────────────
# PART 3: Heap guardrail verification
# ──────────────────────────────────────────────────────────────────────────────
log ""
log "🛡️ HEAP GUARDRAIL STATUS:"
log "────────────────────────"

ARGV_JSON="$HOME/.vscode-server/data/argv.json"
if [[ -f "$ARGV_JSON" ]]; then
  heap=$(python3 -c "import json; print(json.load(open('$ARGV_JSON'))['max-old-space-size'])" 2>/dev/null || echo "ERROR")
  echo "✓ argv.json max-old-space-size: ${heap}MB" | tee -a "$LOG_FILE"
else
  echo "❌ argv.json NOT FOUND at $ARGV_JSON" | tee -a "$LOG_FILE"
fi

if grep -q "max-old-space-size" ~/.bashrc 2>/dev/null; then
  heap=$(grep "max-old-space-size" ~/.bashrc | grep -oE "[0-9]+")
  echo "✓ ~/.bashrc NODE_OPTIONS: ${heap}MB" | tee -a "$LOG_FILE"
else
  echo "❌ NODE_OPTIONS NOT in ~/.bashrc" | tee -a "$LOG_FILE"
fi

# ──────────────────────────────────────────────────────────────────────────────
# PART 4: Watcher configuration
# ──────────────────────────────────────────────────────────────────────────────
log ""
log "👁️ WATCHER EXCLUSION STATUS:"
log "────────────────────────────"

SETTINGS="$HOME/ElevatedIQ-Mono-Repo/.vscode/settings.json"
if [[ -f "$SETTINGS" ]]; then
  has_git=$(python3 -c "
import json
s = json.load(open('$SETTINGS'))
we = s.get('files.watcherExclude', {})
print('YES' if '**/.git/**' in we else 'NO')
  " 2>/dev/null || echo "ERROR")
  echo "✓ **/.git/** excluded: $has_git" | tee -a "$LOG_FILE"
else
  log "ℹ️ Settings not in standard location; check $(pwd)/.vscode/settings.json"
fi

# ──────────────────────────────────────────────────────────────────────────────
# PART 5: Recommendations
# ──────────────────────────────────────────────────────────────────────────────
log ""
log "💡 RECOMMENDATIONS:"
log "──────────────────"
cat << 'EOL' | tee -a "$LOG_FILE"

1. DISABLE memory-heavy extensions:
   - continue.continue (AI pairs programming)
   - ms-vscode.test-explorer-ui (multiple test runners)
   - eamodio.gitlens (advanced git features)

2. TUNE Pylance settings:
   - "python.analysis.indexing": false
   - "python.analysis.diagnosticMode": "openFilesOnly"
   - "python.defaultInterpreterPath": "<path to venv python>"

3. MONITOR continuously:
   ./scripts/pmo/devenv_monitor.sh --watch

4. IF OOM still occurs:
   - Increase available system memory
   - Use workspace exclusions to reduce indexed files
   - Split workspace into smaller projects
   - Use VS Code Remote to move workload to faster hardware

5. HARDWARE SIZING (recommended):
   - CPU: 8+ cores
   - RAM: 32GB+
   - Storage: SSD 500GB+
   - Network: Gigabit

EOL

log ""
log "✓ Audit complete. Results logged to: $LOG_FILE"
