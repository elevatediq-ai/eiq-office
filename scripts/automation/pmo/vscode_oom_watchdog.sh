#!/usr/bin/env bash
# =============================================================================
# VS Code OOM Watchdog - ElevatedIQ Mono-Repo
# =============================================================================
# RCA: VS Code extension host process (--type=extensionHost) grows unbounded
# due to Pylance analyzing 55K+ Python files and GitLens processing 1.2GB git
# history. When combined with TF/CUDA stubs and file watchers on 185K files,
# the Node.js V8 heap exceeds available RAM → Linux OOM killer fires.
#
# Evidence: Issues #2033 (2690MB LSP), #3116 (P0 Stability), #3037 (Memory Warning)
# Frequency: Multiple times per day for 2+ weeks
#
# SOLUTION: This watchdog monitors extension host memory every 30s. When it
# exceeds the WARN threshold it logs; when it exceeds KILL threshold it sends
# SIGTERM to allow graceful restart instead of hard OOM kill.
#
# USAGE:
#   ./scripts/pmo/vscode_oom_watchdog.sh          # run once
#   ./scripts/pmo/vscode_oom_watchdog.sh --watch  # continuous (30s interval)
#   ./scripts/pmo/vscode_oom_watchdog.sh --status # print current state only
#
# AUTOSTART: Add to crontab:  */1 * * * * /path/to/vscode_oom_watchdog.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
LOG_DIR="$SCRIPT_DIR/logs"
LOG_FILE="$LOG_DIR/vscode_oom_watchdog.log"
ISSUE_LOG="$LOG_DIR/oom_issues_created.log"
KILL_LOG="$LOG_DIR/oom_kills.log"

mkdir -p "$LOG_DIR"

# ── Shared monitor safety guards (circuit breaker, sentinel, safe logging) ────
MONITOR_SCRIPT_ID="vscode-oom-watchdog"
MONITOR_CB_LIMIT=5
MONITOR_CB_WINDOW=300
MONITOR_LOG_PREFIX="[OOM-WATCHDOG]"
# shellcheck source=../../lib/monitor_guards.sh
source "${REPO_ROOT}/scripts/lib/monitor_guards.sh"

# ── Thresholds (MB) ──────────────────────────────────────────────────────────
# WARN: Log alert when process exceeds this many MB
# Lowered defaults for aggressive protection on large mono-repo hosts
WARN_MB=${VSCODE_OOM_WARN_MB:-1200}
# KILL: Gracefully terminate the process when it exceeds this many MB
# Default reduced to 2000MB to avoid hard OOMs; can be overridden via env
KILL_MB=${VSCODE_OOM_KILL_MB:-2000}
# Cooldown between kills for the same PID (seconds)
# Shorter cooldown to allow quicker remediation during active spikes
KILL_COOLDOWN_SEC=${VSCODE_OOM_KILL_COOLDOWN_SEC:-300}
# Cooldown between auto-created issues for the same PID (seconds)
ISSUE_COOLDOWN_SEC=${VSCODE_OOM_ISSUE_COOLDOWN_SEC:-3600}
# CI mode: disable GitHub issue creation
CI_MODE=${CI:-false}
# ── RCA-FIX 2026-02-26: ALERT_ONLY_MODE ─────────────────────────────────────
# ALERT_ONLY_MODE=1 (default): Log warning + create GitHub issue but NEVER send
# SIGTERM/SIGKILL to VS Code processes. Killing extensionHost over Remote-SSH
# causes "Cannot reconnect. Please reload the window." 2-4x/hour.
# Set VSCODE_OOM_ALERT_ONLY=0 ONLY if you explicitly want kill behavior back.
# See: docs/ops/RCA_VSCODE_RECONNECT_2026-02-26.md
ALERT_ONLY_MODE=${VSCODE_OOM_ALERT_ONLY:-1}
# ─────────────────────────────────────────────────────────────────────────────

ts() { date '+%Y-%m-%d %H:%M:%S'; }
epoch() { date +%s; }
# IMPORTANT: log() writes to file + stderr ONLY — never stdout.
# Using tee here would contaminate any watched log dir if this script's stdout
# is redirected (the root cause of the portal-monitor feedback loop incident).
log() {
    local msg
    msg="$(ts) [OOM-WATCHDOG] $*"
    echo "${msg}" >> "${LOG_FILE}"
    echo "${msg}" >&2
}

recent_event_exists() {
  local file="$1"
  local pid="$2"
  local cooldown="$3"
  local now
  now=$(epoch)

  if [[ ! -f "$file" ]]; then
    return 1
  fi

  local last_ts
  last_ts=$(awk -v target="$pid" '$2==target {print $1}' "$file" | tail -1)
  if [[ -z "$last_ts" ]]; then
    return 1
  fi

  local age=$(( now - last_ts ))
  [[ $age -lt $cooldown ]]
}

record_event() {
  local file="$1"
  local pid="$2"
  local rss_mb="$3"
  echo "$(epoch) $pid $rss_mb" >> "$file"
}

# ── Process scanner ──────────────────────────────────────────────────────────
scan_processes() {
  local found_issue=0

  # Find ALL extensionHost processes, Pylance language server, and ruff
  while IFS= read -r line; do
    local pid rss_kb cmd
    pid=$(echo "$line" | awk '{print $1}')
    rss_kb=$(echo "$line" | awk '{print $2}')
    cmd=$(echo "$line" | awk '{for(i=3;i<=NF;i++) printf $i" "; print ""}')
    local rss_mb=$(( rss_kb / 1024 ))

    # Never kill ephemeral helpers that are expected to spike transiently
    if [[ "$cmd" =~ ruff ]]; then
      continue
    fi

    if [[ $rss_mb -ge $KILL_MB ]]; then
      if recent_event_exists "$KILL_LOG" "$pid" "$KILL_COOLDOWN_SEC"; then
        log "⏳ COOLDOWN ACTIVE: PID=$pid RSS=${rss_mb}MB (skipping kill for ${KILL_COOLDOWN_SEC}s window)"
        found_issue=1
        continue
      fi

      log "🚨 KILL THRESHOLD HIT: PID=$pid RSS=${rss_mb}MB CMD=${cmd:0:80}"
      if [[ "$ALERT_ONLY_MODE" == "1" ]]; then
        log "   [ALERT_ONLY_MODE] Would SIGTERM PID=$pid — SKIPPED to prevent VS Code disconnect (RCA 2026-02-26)"
        log "   Action: GitHub issue will be created. To enable kills: VSCODE_OOM_ALERT_ONLY=0"
      else
        log "   Sending SIGTERM to allow graceful extension host restart..."
        kill -TERM "$pid" 2>/dev/null || log "   Could not kill PID=$pid (already dead?)"
      fi
        record_event "$KILL_LOG" "$pid" "$rss_mb"
        # Emit an incident file for off-host processing/automation.
        # Writes a JSON payload to .watchdog/incidents/<timestamp>_pid_<pid>.json
        emit_incident_file() {
          local pid_i="$1" rss_i="$2" cmd_i="$3" ts_i
          ts_i=$(date -u +%Y%m%dT%H%M%SZ)
          mkdir -p "$REPO_ROOT/.watchdog/incidents"
          local outfile="$REPO_ROOT/.watchdog/incidents/${ts_i}_pid_${pid_i}.json"
          cat > "$outfile" <<-JSON
    {
      "timestamp": "${ts_i}",
      "pid": ${pid_i},
      "rss_mb": ${rss_i},
      "cmd": "${cmd_i//"/\\\"}",
      "host": "$(hostname)",
      "watchdog_version": "1"
    }
    JSON
          log "   Incident file written: $outfile"

          # Optional: attempt to push incident to remote branch for GitHub Action automation
          if [[ "${EIQ_WATCHDOG_AUTOPUSH:-false}" == "true" ]]; then
            if git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
              log "   Attempting to push incident file to branch watchdog-incidents (auto-push enabled)"
              # Prefer WATCHDOG_GIT_REMOTE, then origin-watchdog, then origin, then first remote
              PUSH_REMOTE=${WATCHDOG_GIT_REMOTE:-origin-watchdog}
              if ! git -C "$REPO_ROOT" remote | grep -q "^${PUSH_REMOTE}$"; then
                if git -C "$REPO_ROOT" remote | grep -q '^origin-watchdog$'; then
                  PUSH_REMOTE=origin-watchdog
                elif git -C "$REPO_ROOT" remote | grep -q '^origin$'; then
                  PUSH_REMOTE=origin
                else
                  PUSH_REMOTE=$(git -C "$REPO_ROOT" remote | head -n1 || true)
                fi
              fi
              if [[ -z "${PUSH_REMOTE:-}" ]]; then
                log "   No git remote configured; cannot auto-push incident"
              else
                (cd "$REPO_ROOT" && git checkout -B watchdog-incidents >/dev/null 2>&1 || true && git add ".watchdog/incidents/$(basename "$outfile")" >/dev/null 2>&1 && git commit -m "chore(watchdog): incident ${ts_i} pid ${pid_i}" >/dev/null 2>&1 && git push "${PUSH_REMOTE}" watchdog-incidents >/dev/null 2>&1) && log "   Incident pushed to remote ${PUSH_REMOTE}/watchdog-incidents" || log "   Incident push failed (no auth or remote); manual push required"
              fi
            else
              log "   Repo root not a git working tree; cannot auto-push incident"
            fi
          fi
        }
        emit_incident_file "$pid" "$rss_mb" "$cmd"

      # Create GitHub issue if not already reported for this PID recently
      if [[ "$CI_MODE" != "true" ]] && command -v gh &>/dev/null; then
        if ! recent_event_exists "$ISSUE_LOG" "$pid" "$ISSUE_COOLDOWN_SEC"; then
          if circuit_breaker_check; then
            log "   Creating GitHub issue for OOM event..."
            local issue_url
            issue_url=$(gh issue create \
              --repo "kushin77/ElevatedIQ-Mono-Repo" \
              --title "🚨 [AUTO-OOM] Extension Host Killed: PID=$pid ${rss_mb}MB" \
              --label "type:bug,priority-p0,status:in-progress" \
              --body "## Auto-Detected OOM Event

**Timestamp:** $(ts)
**PID:** $pid
**RSS Memory:** ${rss_mb}MB (threshold: ${KILL_MB}MB)
**Process:** \`${cmd:0:200}\`

## Root Cause
Extension host (Pylance/GitLens) exceeded memory threshold before OS OOM killer fired.
Watchdog sent SIGTERM for graceful restart.

## Related Issues
- #2033 (2690MB LSP runaway - closed but recurring)
- #3116 (OOM Hardening - closed but recurring)

## Action Taken
- Watchdog sent SIGTERM to PID $pid
- VS Code extension host will restart automatically

## Permanent Fix Status
See: \`.vscode/settings.json\` python.analysis.exclude + GitLens lockdown (applied $(ts))

_Auto-generated by \`scripts/pmo/vscode_oom_watchdog.sh\`_" 2>/dev/null || echo "issue-create-failed")
            circuit_breaker_record
            record_event "$ISSUE_LOG" "$pid" "$rss_mb"
            log "   Issue created: $issue_url"
          else
            log "   [CIRCUIT-BREAKER] Issue creation skipped for PID=$pid (rate limit)"
          fi
        else
          log "   Issue cooldown active for PID=$pid (window ${ISSUE_COOLDOWN_SEC}s)"
        fi
      fi
      found_issue=1

    elif [[ $rss_mb -ge $WARN_MB ]]; then
      log "⚠️  WARN THRESHOLD: PID=$pid RSS=${rss_mb}MB CMD=${cmd:0:80}"
      found_issue=1
    fi

  done < <(ps aux --no-headers 2>/dev/null | awk '
    /extensionHost|pylance-server|pyright|ruff/ {
      rss_kb = $6
      pid = $2
      cmd = ""
      for(i=11;i<=NF;i++) cmd = cmd " " $i
      print pid " " rss_kb " " cmd
    }
  ')

  return $found_issue
}

# ── Terraform cache guard (NIST CM-3, SI-12) ─────────────────────────
# Prevent .terraform directories from accumulating.
# Integrated with terraform_maintenance_enhanced.sh for 10X guardrails.
check_terraform_bloat() {
  local maintenance_script="/home/akushnir/ElevatedIQ-Mono-Repo/scripts/automation/infrastructure/terraform_maintenance_enhanced.sh"
  
  if [[ -f "$maintenance_script" ]]; then
    log "[INFRA] Running terraform cache maintenance (10X Gate)..."
    # Call the enhanced script to check status and handle bypass/enforcement
    "$maintenance_script" status >> "$LOG_FILE" 2>&1 || true
    
    # Check if threshold exceeded (using the logic from the script)
    local current_size
    current_size=$("$maintenance_script" status | grep "Current Cache:" | awk '{print $3}' | sed 's/MB//')
    
    if [[ ${current_size:-0} -gt 2000 ]]; then
      log "⚠️  TERRAFORM CACHE CRITICAL: ${current_size}MB detected. Triggering auto-purge."
      "$maintenance_script" purge >> "$LOG_FILE" 2>&1 || true
      
      # Notify via GitHub issue if possible (reuse existing logic if available)
      if [[ "$CI_MODE" != "true" ]] && command -v gh &>/dev/null && circuit_breaker_check; then
         gh issue create \
          --repo "kushin77/ElevatedIQ-Mono-Repo" \
          --title "⚠️ [AUTO-FIX] .terraform cache auto-purged: ${current_size}MB" \
          --label "type:task,priority-p0" \
          --body "Terraform provider caches exceeded 2000MB and were automatically purged by the watchdog.\n\nActions Taken:\n1. Relocated to /tmp/eiq_cache_history\n2. Logged event in VS Code OOM watchdog\n3. System stability preserved.\n\n_Auto-generated by vscode_oom_watchdog.sh_" 2>/dev/null || true
        circuit_breaker_record
      fi
    fi
  else
    log "⚠️  MISSING INFRA SCRIPT: $maintenance_script not found."
  fi
}

# ── .venv guard ───────────────────────────────────────────────────────────────
# Warn if .venv file count exceeds sane limit (Pylance will try to analyze stubs)
check_venv_size() {
  if [[ -d "$REPO_ROOT/.venv" ]]; then
    local venv_files
    venv_files=$(find "$REPO_ROOT/.venv" -type f 2>/dev/null | wc -l)
    if [[ $venv_files -gt 70000 ]]; then
      log "⚠️  .venv has ${venv_files} files. Consider removing TF/CUDA packages from dev venv or using separate AI venv."
    fi
  fi
}

# ── Duplicate session detection and cleanup ───────────────────────────────────
# Issue #4743: Duplicate extensionHost processes accumulate after OOM crash
# causing next OOM crash. This function detects and kills older stale sessions.
check_duplicate_sessions() {
  local extension_hosts
  extension_hosts=$(ps aux --no-headers 2>/dev/null | grep "type=extensionHost" | grep -v grep | awk '{print $2 " " $9}' | sort -k2 -r)

  local count
  count=$(echo "$extension_hosts" | grep -c . || true)

  if [[ $count -gt 1 ]]; then
    log "⚠️  DUPLICATE SESSION ALERT: $count extensionHost processes detected"

    # Kill all but the newest (most recent start time)
    local oldest_pids
    oldest_pids=$(echo "$extension_hosts" | tail -n +2 | awk '{print $1}')

    if [[ -n "$oldest_pids" ]]; then
      log "   Killing stale extensionHost sessions (keeping newest)..."
      while IFS= read -r old_pid; do
        if [[ -n "$old_pid" ]]; then
          log "   → Stale PID=$old_pid detected"
          if [[ "$ALERT_ONLY_MODE" == "1" ]]; then
            log "   [ALERT_ONLY_MODE] Would SIGTERM stale PID=$old_pid — SKIPPED (RCA 2026-02-26)"
          else
            log "   → Sending SIGTERM to stale PID=$old_pid"
            kill -TERM "$old_pid" 2>/dev/null || log "     Could not kill PID=$old_pid (already dead?)"
            sleep 1
          fi
        fi
      done <<< "$oldest_pids"

      # Give processes time to gracefully terminate
      sleep 5

      # Force kill any that didn't respond to SIGTERM
      while IFS= read -r old_pid; do
        if [[ -n "$old_pid" ]] && ps -p "$old_pid" > /dev/null 2>&1; then
          if [[ "$ALERT_ONLY_MODE" == "1" ]]; then
            log "   [ALERT_ONLY_MODE] Would SIGKILL PID=$old_pid — SKIPPED (RCA 2026-02-26)"
          else
            log "   → SIGKILL to force-terminated PID=$old_pid"
            kill -9 "$old_pid" 2>/dev/null || true
          fi
        fi
      done <<< "$oldest_pids"

      # Create GitHub issue for duplicate session event
      if [[ "$CI_MODE" != "true" ]] && command -v gh &>/dev/null; then
        if ! recent_event_exists "$ISSUE_LOG" "duplicate-sessions" "$ISSUE_COOLDOWN_SEC"; then
          log "   Creating GitHub issue for duplicate session cleanup..."
          gh issue create \
            --repo "kushin77/ElevatedIQ-Mono-Repo" \
            --title "⚠️ [AUTO] Duplicate VS Code sessions: $count extensionHosts running" \
            --label "type:bug,priority-p1" \
            --body "## ⚠️ Duplicate VS Code Sessions

**Count:** $count extensionHost instances
**Detected:** $(ts)

This means VS Code reconnected after an OOM crash without killing the stale session.
Each extra session adds ~800-1200MB RAM, directly causing the NEXT OOM crash.

## Sessions
\`\`\`
$(ps aux --no-headers 2>/dev/null | grep 'type=extensionHost' | grep -v grep | awk '{printf \"PID=%-6s STARTED=%s RSS=%-6.0fMB\\n\", $2, substr(\$9,0,12), \$6/1024}')
\`\`\`

## Auto-Remediation
Sent SIGTERM to stale extensionHost PID(s): $(echo \"$oldest_pids\" | tr '\\n' ' ')

If duplicates still remain after SIGTERM, re-run monitor or kill oldest manually:
\`\`\`bash
ps -eo pid,etimes,cmd | grep 'type=extensionHost' | grep -v grep | sort -k2,2nr
\`\`\`

_Auto-detected by \\\`scripts/pmo/devenv_monitor.sh\\\` — check_duplicate_sessions_" 2>/dev/null || true
          record_event "$ISSUE_LOG" "duplicate-sessions" "$count"
        fi
      fi
    fi
  fi
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
  local mode="${1:-once}"

  case "$mode" in
    --status)
      log "=== Current VS Code Process Memory ==="
      ps aux --no-headers 2>/dev/null | awk '
        /extensionHost|pylance|pyright|ruff/ {
          rss_mb = $6 / 1024
          printf "  PID=%-8s RSS=%-6.0fMB  %s\n", $2, rss_mb, substr($0, index($0,$11), 80)
        }
      '
      log "=== Workspace File Count ==="
      find "$REPO_ROOT" -not -path '*/.git/*' -not -path '*/.venv/*' \
        -not -path '*/node_modules/*' -type f 2>/dev/null | wc -l | xargs -I{} echo "  {} files (excl .venv/node_modules/.git)"
      log "=== Memory ==="
      free -h | grep -E "Mem|Swap"
      ;;
    --watch)
      # Sentinel: prevent duplicate watchdog instances
      startup_sentinel_acquire "${MONITOR_SCRIPT_ID}"
      trap 'startup_sentinel_release' EXIT INT TERM
      log "Starting OOM watchdog (WARN=${WARN_MB}MB KILL=${KILL_MB}MB interval=30s)"
      while true; do
        check_duplicate_sessions || true
        scan_processes || true
        check_terraform_bloat
        check_venv_size
        sleep 30
      done
      ;;
    *)
      log "Running single scan (WARN=${WARN_MB}MB KILL=${KILL_MB}MB)"
      check_duplicate_sessions || true
      scan_processes || true
      check_terraform_bloat
      check_venv_size
      log "Scan complete."
      ;;
  esac
}

main "${1:-once}"
