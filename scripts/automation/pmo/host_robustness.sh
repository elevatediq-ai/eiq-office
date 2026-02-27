#!/usr/bin/env bash
# ==============================================================================
# 🛡️ ElevatedIQ Host Robustness & Hardening Utility
# ==============================================================================
# Purpose: Enterprise-grade host optimization and security hardening.
# NIST 800-53 Alignment: CM-6 (Config Management), SI-4 (System Monitoring),
# SC-7 (Boundary Protection), AC-2 (Account Management)
# ==============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOG_DIR="${REPO_ROOT}/logs/hardening"
mkdir -p "$LOG_DIR"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="${LOG_DIR}/harden_${TIMESTAMP}.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'

log() { echo -e "${BLUE}[$(date +%H:%M:%S)]${NC} $1" | tee -a "$LOG_FILE"; }
success() { echo -e "${GREEN}[PASS]${NC} $1" | tee -a "$LOG_FILE"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$LOG_FILE"; }
error() { echo -e "${RED}[FAIL]${NC} $1" | tee -a "$LOG_FILE"; }
header() { echo -e "\n${MAGENTA}=== $1 ===${NC}" | tee -a "$LOG_FILE"; }

header "ElevatedIQ Host Hardening & Robustness"

# 1. Workspace Hygiene & Indexer Pressure Relief
header "1. Workspace Hygiene (NIST CM-6)"
log "Cleaning up high-volume transient artifacts that cause indexer crashes..."

# Deleting massive coverage reports (regenerated on demand)
if [ -d "${REPO_ROOT}/apps/control_plane/htmlcov" ]; then
    log "Removing stale coverage report (1.1GB)..."
    rm -rf "${REPO_ROOT}/apps/control_plane/htmlcov"
    success "Removed apps/control_plane/htmlcov"
fi

# Deleting legacy venv if it's orphaned (7.5GB)
if [ -d "${REPO_ROOT}/test_venv" ]; then
    log "Detected legacy test_venv (7.5GB). Excluding from watcher is better than deletion if used."
    warn "Legacy test_venv remains. Ensure it is in .vscode/settings.json watcherExclude."
fi

# Clean up __pycache__ and temp logs
log "Purging stale __pycache__ and log files..."
find "${REPO_ROOT}" -name "__pycache__" -type d -exec rm -rf {} +
find "${REPO_ROOT}" -name "*.log" -type f -mtime +7 -delete
success "Workspace hygiene complete."

# 2. Host Performance Tuning (NIST SI-4)
header "2. Host Performance Tuning"

# Check File Watcher Limits
WATCHER_LIMIT=$(cat /proc/sys/fs/inotify/max_user_watches || echo "524288")
if [ "$WATCHER_LIMIT" -lt 524288 ]; then
    warn "Low inotify limit: $WATCHER_LIMIT. Mono-repos require at least 524288."
    log "Recommendation: echo fs.inotify.max_user_watches=524288 | sudo tee -a /etc/sysctl.conf && sudo sysctl -p"
else
    success "Inotify limit is optimal: $WATCHER_LIMIT"
fi

# Check Open Files Limit
FILE_LIMIT=$(ulimit -n)
if [ "$FILE_LIMIT" -lt 100000 ]; then
    warn "User open files limit is low: $FILE_LIMIT"
    log "Recommendation: Update /etc/security/limits.conf with * soft nofile 1048576"
else
    success "Open files limit is optimal: $FILE_LIMIT"
fi

# 3. Security Boundary Hardening (NIST SC-7)
header "3. Security Hardening"

# Check SSH Port (AC-2/SC-7)
if grep -q "^#Port 22" /etc/ssh/sshd_config 2>/dev/null || grep -q "^Port 22" /etc/ssh/sshd_config 2>/dev/null; then
    log "SSH is running on default port 22."
    warn "Consider changing SSH port and disabling password auth (NIST AC-2)."
fi

# Check for unencrypted secrets (NIST SC-28)
log "Running quick secret scan..."
if command -v grep &> /dev/null; then
    SECRETS=$(grep -rE "password|api_key|secret_key" "${REPO_ROOT}" --exclude-dir=".git" --exclude-dir="node_modules" --exclude-dir="venv" | head -n 5 || true)
    if [ -n "$SECRETS" ]; then
        warn "Potential unencrypted secrets detected. Use 'scripts/security/secret_validator.sh'."
    else
        success "No obvious plaintext secrets found in root."
    fi
fi

# 4. Final Platform Health Status
header "4. Platform Status"
log "Memory: $(free -h | awk '/Mem:/ {print $4 " free of " $2}')"
log "Disk: $(df -h "${REPO_ROOT}" | tail -1 | awk '{print $4 " available on " $1}')"

success "Host robustness check complete."
log "Full report: $LOG_FILE"
