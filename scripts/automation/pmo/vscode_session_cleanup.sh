#!/usr/bin/env bash
# =============================================================================
# VS Code Session Cleanup & Deduplication
# =============================================================================
# Ensures only a single active VS Code extensionHost process runs.
# Auto-runs on VS Code connection + periodically via monitor.
# NIST: CM-7 (Least Privilege), CM-6 (Configuration)
# Issues: #4734, #4731, #3116
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/logs/session_cleanup.log"
mkdir -p "$(dirname "$LOG_FILE")"

ts() { date '+%Y-%m-%d %H:%M:%S'; }
log() { echo "[$(ts)] $*" | tee -a "$LOG_FILE"; }

log "🧹 VS Code Session Cleanup — $(ts)"
log "==================================="

# ──────────────────────────────────────────────────────────────────────────────
# STEP 1: Detect duplicate sessions
# ──────────────────────────────────────────────────────────────────────────────
log ""
log "📊 Checking for duplicate extensionHost sessions..."

sessions=$(ps -eo pid,etimes,cmd 2>/dev/null | \
  awk '/type=extensionHost/ && !/awk/ {print $1" "$2}' | \
  sort -k2,2n)  # Sort by runtime elapsed (newest first)

session_count=$(echo "$sessions" | grep -c . || true)

log "Found $session_count extensionHost process(es)"

if [[ $session_count -le 1 ]]; then
  log "✓ No duplicates detected (healthy state)"
  exit 0
fi

# ──────────────────────────────────────────────────────────────────────────────
# STEP 2: Kill stale (oldest) sessions, keep newest
# ──────────────────────────────────────────────────────────────────────────────
log ""
log "❌ DUPLICATE SESSIONS DETECTED — Auto-remediating..."
log ""

keep_pid=$(echo "$sessions" | head -1 | awk '{print $1}')
stale_pids=$(echo "$sessions" | tail -n +2 | awk '{print $1}')

log "  KEEP (most recent): PID=$keep_pid"
echo "$stale_pids" | while read -r pid; do
  runtime=$(ps -o etimes= -p "$pid" 2>/dev/null || echo "unknown")
  rss_mb=$(ps -o rss= -p "$pid" 2>/dev/null | awk '{print int($1/1024)}' || echo "unknown")
  log "  KILL (stale): PID=$pid (Runtime=${runtime}s, RSS=${rss_mb}MB)"
done

# Kill stale sessions with graceful SIGTERM
log ""
log "  Sending SIGTERM to stale sessions..."
echo "$stale_pids" | xargs -r kill -SIGTERM 2>/dev/null || true

# Wait 2 seconds for graceful termination
sleep 2

# Force-kill any that didn't respond
log "  Verifying all stale sessions terminated..."
remaining=0
while read -r pid; do
  [[ -n "$pid" ]] || continue
  if ps -p "$pid" >/dev/null 2>&1; then
    remaining=$((remaining + 1))
  fi
done <<< "$stale_pids"
if [[ $remaining -gt 0 ]]; then
  log "  ⚠️ Some sessions didn't respond to SIGTERM — force-killing with SIGKILL..."
  echo "$stale_pids" | xargs -r kill -SIGKILL 2>/dev/null || true
  sleep 1
fi

# Verify cleanup
final_count=$(ps -eo cmd 2>/dev/null | awk '/type=extensionHost/ && !/awk/ {count++} END {print count+0}')
log ""
log "✓ Cleanup complete:"
log "  Before: $session_count extensionHost(s)"
log "  After:  $final_count extensionHost(s)"

if [[ $final_count -eq 1 ]]; then
  log "✓ SUCCESS: Single session confirmed"
  exit 0
else
  log "⚠️ WARNING: Expected 1 session, found $final_count"
  log "Manual intervention may be needed"
  exit 1
fi
