#!/usr/bin/env bash
# =============================================================================
# ElevatedIQ Dev Environment Monitor
# =============================================================================
# Unified monitor for all developer environment failure modes that caused
# 2+ weeks of daily VS Code OOM crashes. Detects issues BEFORE they crash
# VS Code and auto-creates GitHub issues with full forensic data.
#
# MONITORS:
#   1. Kernel OOM kill events        (dmesg / /var/log/syslog)
#   2. fileWatcher CPU spinning      (> 85% CPU for > 60s → primary OOM cause)
#   3. Extension host memory bloat   (> 1.5GB warn, > 2.5GB kill+issue)
#   4. Duplicate VS Code sessions    (post-OOM reconnect double-spawning)
#   5. NODE_OPTIONS heap cap drift   (env var removed from .bashrc/.profile)
#   6. watcherExclude config drift   (**/.git/** removed from settings.json)
#   7. System memory pressure        (< 2GB available → pre-OOM warning)
#   8. .venv file explosion          (> 70K files → Pylance LSP bloat)
#   9. Git repo size growth          (> 1.5GB → watcher I/O pressure)
#  10. Pylance crash loop detection  (rapid respawn cycle)
#  11. Backend Dependency Health     (checks reachability of .42/.31 backends)
#
# USAGE:
#   ./scripts/pmo/devenv_monitor.sh             # single scan
#   ./scripts/pmo/devenv_monitor.sh --watch     # continuous (30s)
#   ./scripts/pmo/devenv_monitor.sh --status    # human-readable report
#   ./scripts/pmo/devenv_monitor.sh --install   # install systemd user service
#   ./scripts/pmo/devenv_monitor.sh --uninstall # remove systemd service
#
# AUTO-START (run --install once):
#   systemctl --user enable --now elevatediq-devenv-monitor.service
#
# NIST: CM-6 (Config Settings), SI-2 (Flaw Remediation), AU-2 (Audit Events)
# Issues: #3622 (OOM RCA), #3116, #2033, #3037
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null)"; then
  :
elif [[ -d "$SCRIPT_DIR/../../.git" ]]; then
  REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
elif [[ -d "$SCRIPT_DIR/../../../.git" ]]; then
  REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
else
  REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
fi
LOG_DIR="$SCRIPT_DIR/logs"
LOG_FILE="$LOG_DIR/devenv_monitor.log"
STATE_DIR="$LOG_DIR/.monitor_state"
ISSUE_DEDUP_DB="$LOG_DIR/.issue_dedup"

mkdir -p "$LOG_DIR" "$STATE_DIR"

# ── Shared monitor safety guards (circuit breaker, sentinel, safe logging) ────
MONITOR_SCRIPT_ID="devenv-monitor"
MONITOR_CB_LIMIT=10      # slightly higher than portal — 10 distinct OOM types can fire
MONITOR_CB_WINDOW=300
MONITOR_LOG_PREFIX="[DEVENV-MONITOR]"
# shellcheck source=../../lib/monitor_guards.sh
source "${REPO_ROOT}/scripts/lib/monitor_guards.sh"

# ── Thresholds ────────────────────────────────────────────────────────────────
WATCHER_CPU_WARN=85          # fileWatcher CPU% to start timing
WATCHER_CPU_SPIN_SECS=60     # seconds at WARN before it's a "spin" → issue
EXT_HOST_WARN_MB=3500        # increased from 2500
EXT_HOST_KILL_MB=${EXT_HOST_KILL_MB:-4500} # increased from 3500
EXT_HOST_REPEAT_KILL_WINDOW_SECS=${EXT_HOST_REPEAT_KILL_WINDOW_SECS:-900}
EXT_HOST_REPEAT_KILL_THRESHOLD=${EXT_HOST_REPEAT_KILL_THRESHOLD:-2} # more aggressive (lowered from 3)
EXT_HOST_MAX_KILL_CAP_MB=5120  # increased from 3500
DESIRED_HEAP_MB=3072         # increased from 2560 (3GB target)
VSCODE_ARGV_PATH="$HOME/.vscode-server/data/argv.json"
SYS_MEM_WARN_MB=2048         # system available RAM warn threshold
VENV_FILE_LIMIT=70000        # .venv file count before Pylance bloat warning
GIT_SIZE_WARN_MB=1500        # .git dir size warn
PYLANCE_CRASH_WINDOW=120     # seconds to detect rapid Pylance restart loop
# ── RCA-FIX 2026-02-26: ALERT_ONLY_MODE ─────────────────────────────────────
# DEVENV_MONITOR_ALERT_ONLY=1 (default): log + create issue but NEVER send
# SIGTERM/SIGKILL to VS Code processes. Killing extensionHost over Remote-SSH
# triggers "Cannot reconnect. Please reload the window." 2-4x/hour.
# Set DEVENV_MONITOR_ALERT_ONLY=0 ONLY to explicitly re-enable kill behavior.
# See: docs/ops/RCA_VSCODE_RECONNECT_2026-02-26.md
DEVENV_MONITOR_ALERT_ONLY=${DEVENV_MONITOR_ALERT_ONLY:-1}
# ─────────────────────────────────────────────────────────────────────────────
PYLANCE_CRASH_COUNT=3        # restarts within window = crash loop

REPO="kushin77/ElevatedIQ-Mono-Repo"
CI_MODE=${CI:-false}
QUIET=${QUIET:-false}

# ── Helpers ───────────────────────────────────────────────────────────────────
ts()  { date '+%Y-%m-%d %H:%M:%S'; }
log() {
  local msg="$(ts) [DEVENV-MONITOR] $*"
  echo "$msg" >> "$LOG_FILE"
  # Write to stderr only (not stdout) — prevents contaminating any watched dir
  # when this script's stdout is redirected to a *.log file (feedback loop risk)
  [[ "$QUIET" != "true" ]] && echo "$msg" >&2
}
warn_log()  { log "⚠️  WARN: $*"; }
error_log() { log "🚨 ERROR: $*"; }
normalize_ext_host_thresholds() {
  if [[ "$EXT_HOST_KILL_MB" -gt "$EXT_HOST_MAX_KILL_CAP_MB" ]]; then
    warn_log "EXT_HOST_KILL_MB=$EXT_HOST_KILL_MB exceeds safety cap ${EXT_HOST_MAX_KILL_CAP_MB}MB; clamping to ${EXT_HOST_MAX_KILL_CAP_MB}MB"
    EXT_HOST_KILL_MB=$EXT_HOST_MAX_KILL_CAP_MB
  fi

  if [[ "$EXT_HOST_KILL_MB" -le "$EXT_HOST_WARN_MB" ]]; then
    EXT_HOST_KILL_MB=$(( EXT_HOST_WARN_MB + 200 ))
    warn_log "Adjusted EXT_HOST_KILL_MB to ${EXT_HOST_KILL_MB}MB (must exceed WARN threshold)"
  fi
}

enforce_heap_guardrails() {
  local remediated=false
  local marker="# elevatediq-oom-guardrail"
  local desired_line="export NODE_OPTIONS=\"\${NODE_OPTIONS} --max-old-space-size=${DESIRED_HEAP_MB}\" ${marker}"

  for profile in "$HOME/.bashrc" "$HOME/.profile"; do
    [[ -f "$profile" ]] || touch "$profile"
    if grep -q 'max-old-space-size' "$profile" 2>/dev/null; then
      local cleaned
      cleaned=$(mktemp)
      grep -v 'max-old-space-size' "$profile" > "$cleaned" || true
      mv "$cleaned" "$profile"
      remediated=true
      warn_log "Removed stale NODE_OPTIONS heap entries from $profile"
    fi

    if ! grep -q "$marker" "$profile" 2>/dev/null; then
      echo "$desired_line" >> "$profile"
      remediated=true
      warn_log "Added normalized NODE_OPTIONS heap guardrail to $profile"
    fi
  done

  python3 - "$VSCODE_ARGV_PATH" "$DESIRED_HEAP_MB" <<'PY'
import json
import os
import sys

path = sys.argv[1]
desired = int(sys.argv[2])
os.makedirs(os.path.dirname(path), exist_ok=True)

data = {}
if os.path.exists(path):
    try:
        with open(path, encoding="utf-8") as handle:
            data = json.load(handle)
        if not isinstance(data, dict):
            data = {}
    except Exception:
        data = {}

current = data.get("max-old-space-size")
if not isinstance(current, int) or current < desired:
    data["max-old-space-size"] = desired
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(data, handle, indent=2)
    print("updated")
else:
    print("ok")
PY
  local py_status=$?
  if [[ $py_status -ne 0 ]]; then
    error_log "Failed to enforce argv heap guardrail at $VSCODE_ARGV_PATH"
  fi

  if [[ "$remediated" == "true" ]]; then
    ok_log "Heap guardrails auto-remediated (reload shell or restart VS Code server to apply profile changes)."
  fi
}
ok_log()    { log "✅ OK: $*"; }

settings_json_query() {
  local mode="$1"
  local settings_file="$REPO_ROOT/.vscode/settings.json"

  python3 - "$settings_file" "$mode" <<'PY'
import json
import re
import sys

settings_file = sys.argv[1]
mode = sys.argv[2]

def strip_jsonc(text: str) -> str:
  out = []
  i = 0
  n = len(text)
  in_str = False
  escape = False
  while i < n:
    ch = text[i]
    if in_str:
      out.append(ch)
      if escape:
        escape = False
      elif ch == "\\":
        escape = True
      elif ch == '"':
        in_str = False
      i += 1
      continue
    if ch == '"':
      in_str = True
      out.append(ch)
      i += 1
      continue
    if ch == "/" and i + 1 < n and text[i + 1] == "/":
      i += 2
      while i < n and text[i] != "\n":
        i += 1
      continue
    if ch == "/" and i + 1 < n and text[i + 1] == "*":
      i += 2
      while i + 1 < n and not (text[i] == "*" and text[i + 1] == "/"):
        i += 1
      i += 2
      continue
    out.append(ch)
    i += 1

  cleaned = "".join(out)
  cleaned = re.sub(r",\s*([}\]])", r"\1", cleaned)
  return cleaned

try:
  with open(settings_file, encoding="utf-8") as fh:
    settings = json.loads(strip_jsonc(fh.read().lstrip("\ufeff")))
except Exception as exc:
  print(f"error:{exc}")
  sys.exit(2)

watcher_exclude = settings.get("files.watcherExclude", {})

if mode == "watcher_git":
  print("yes" if "**/.git/**" in watcher_exclude else "no")
  sys.exit(0)

if mode == "watcher_summary":
  print(f"entries={len(watcher_exclude)} git_excluded={'✅' if '**/.git/**' in watcher_exclude else '❌ MISSING'}")
  sys.exit(0)

if mode == "venv_excluded":
  excludes = settings.get("python.analysis.exclude", [])
  if any(".venv" in str(item) for item in excludes):
    print("yes")
    sys.exit(0)
  print("no")
  sys.exit(1)

print(f"error:unknown_mode:{mode}")
sys.exit(2)
PY
}

# ── Issue deduplication ───────────────────────────────────────────────────────
# Creates a fingerprint from the issue type+key so we don't spam the same issue
# multiple times within the dedup window (default: 6 hours)
DEDUP_WINDOW_SECS=${DEDUP_WINDOW_SECS:-21600}

should_create_issue() {
  local fingerprint="$1"
  local state_file="$STATE_DIR/dedup_${fingerprint//\//_}"
  local now
  now=$(date +%s)

  if [[ -f "$state_file" ]]; then
    local last_created
    last_created=$(cat "$state_file")
    local age=$(( now - last_created ))
    if [[ $age -lt $DEDUP_WINDOW_SECS ]]; then
      log "  (dedup: issue '$fingerprint' created $((age/60))m ago, skipping)"
      return 1
    fi
  fi
  echo "$now" > "$state_file"
  return 0
}

# ── GitHub issue creator ──────────────────────────────────────────────────────
create_issue() {
  local title="$1"
  local body="$2"
  local labels="${3:-type:bug,priority-p0}"
  local fingerprint="${4:-$(echo "$title" | md5sum | cut -c1-8)}"

  [[ "$CI_MODE" == "true" ]] && { log "  CI mode: skipping issue creation"; return 0; }
  command -v gh &>/dev/null || { log "  gh CLI not found, skipping issue"; return 0; }
  should_create_issue "$fingerprint" || return 0

  # Circuit breaker: halt if rate limit exceeded — hard stop for runaway scenarios
  circuit_breaker_check || { log "  [CIRCUIT-BREAKER] Issue creation suppressed (rate limit)"; return 0; }

  local url
  url=$(gh issue create \
    --repo "$REPO" \
    --title "$title" \
    --label "$labels" \
    --assignee "kushin77" \
    --body "$body" 2>/dev/null) || { log "  ⚠️ gh issue create failed (network/auth?)"; return 0; }

  circuit_breaker_record
  log "  📋 Issue created: $url"
  echo "$(ts) $fingerprint $url" >> "$ISSUE_DEDUP_DB"
}

# ─────────────────────────────────────────────────────────────────────────────
# CHECK 1: Kernel OOM kill events
# Reads dmesg for "Killed process" lines since last scan
# ─────────────────────────────────────────────────────────────────────────────
check_kernel_oom() {
  local last_check_file="$STATE_DIR/last_oom_check_ts"
  local last_ts=0
  [[ -f "$last_check_file" ]] && last_ts=$(cat "$last_check_file")
  date +%s > "$last_check_file"

  # dmesg relative timestamps — scan for OOM kill events
  local oom_events
  oom_events=$(dmesg --time-format=iso 2>/dev/null | \
    grep -E 'Out of memory|Killed process|oom_kill_process|oom-kill' 2>/dev/null | \
    tail -10) || true

  if [[ -n "$oom_events" ]]; then
    local count
    count=$(echo "$oom_events" | wc -l)
    error_log "Kernel OOM kill events detected ($count):"
    echo "$oom_events" | while read -r line; do log "  $line"; done

    # Check if any of these mention code/vscode
    local vscode_oom
    vscode_oom=$(echo "$oom_events" | grep -iE 'node|code-server|vscode' || true)
    if [[ -n "$vscode_oom" ]]; then
      local body
      body="## 🔴 Kernel OOM Kill — VS Code Process

**Detected at:** $(ts)
**Source:** \`dmesg\`

\`\`\`
$vscode_oom
\`\`\`

## Context
$(free -h 2>/dev/null)

## Recent High-Memory Processes
\`\`\`
$(ps aux --sort=-%mem 2>/dev/null | grep -E 'node|python|terraform' | head -10)
\`\`\`

## Likely Root Cause
VS Code Remote Server Node.js process hit V8 heap ceiling or OS killed it
via OOM killer before watchdog SIGTERM fired.

## Immediate Actions
1. Check \`~/.vscode-server/data/argv.json\` exists with \`max-old-space-size:4096\`
2. Check \`NODE_OPTIONS\` in \`~/.bashrc\` and \`~/.profile\`
3. Verify \`files.watcherExclude\` includes \`**/.git/**\`

## Related
Issues: #3622, #3116, #2033

_Auto-detected by \`scripts/pmo/devenv_monitor.sh\` — check_kernel_oom_"
      create_issue \
        "🔴 [AUTO-OOM] Kernel killed VS Code process — $(ts | cut -c1-10)" \
        "$body" \
        "type:bug,priority-p0" \
        "kernel_oom_vscode"
    fi
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# CHECK 2: fileWatcher CPU spinning (THE primary OOM root cause - issue #3622)
# ─────────────────────────────────────────────────────────────────────────────
check_filewatcher_spin() {
  local spin_state_file="$STATE_DIR/filewatcher_spin_since"

  # Get all fileWatcher processes and their CPU%
  local watcher_lines
  watcher_lines=$(ps aux --no-headers 2>/dev/null | grep 'type=fileWatcher' | grep -v grep || true)

  if [[ -z "$watcher_lines" ]]; then
    rm -f "$spin_state_file"
    return 0
  fi

  local max_cpu=0
  while IFS= read -r line; do
    local cpu
    cpu=$(echo "$line" | awk '{print $3}' | cut -d. -f1)
    [[ $cpu -gt $max_cpu ]] && max_cpu=$cpu
  done <<< "$watcher_lines"

  if [[ $max_cpu -ge $WATCHER_CPU_WARN ]]; then
    local now
    now=$(date +%s)
    if [[ ! -f "$spin_state_file" ]]; then
      echo "$now" > "$spin_state_file"
      warn_log "fileWatcher at ${max_cpu}% CPU — timing spin (threshold=${WATCHER_CPU_SPIN_SECS}s)"
    else
      local spin_since
      spin_since=$(cat "$spin_state_file")
      local spin_dur=$(( now - spin_since ))
      if [[ $spin_dur -ge $WATCHER_CPU_SPIN_SECS ]]; then
        error_log "fileWatcher SPIN DETECTED: ${max_cpu}% CPU for ${spin_dur}s"

        local watcher_pids
        watcher_pids=$(echo "$watcher_lines" | awk '{print $2}' | tr '\n' ' ')

        local body
        body="## 🚨 fileWatcher CPU Spin Detected

**Duration:** ${spin_dur}s at ${max_cpu}% CPU
**Detected at:** $(ts)
**PIDs:** $watcher_pids

## Root Cause Pattern
This is the PRIMARY root cause of daily OOM crashes (#3622).
fileWatcher spins when it watches files that change at high frequency
(e.g. \`.git/HEAD\`, \`.git/COMMIT_EDITMSG\`, \`.git/refs/**\`) with a 994MB git history.

## Current watcherExclude Status
\`\`\`
$(grep -A3 '\"files.watcherExclude\"' "$REPO_ROOT/.vscode/settings.json" 2>/dev/null | head -10)
\`\`\`

## git/** excluded?
$(python3 -c "import json; d=json.load(open('$REPO_ROOT/.vscode/settings.json', encoding='utf-8')); we=d.get('files.watcherExclude',{}); print('YES' if '**/.git/**' in we else 'NO')" 2>/dev/null || echo 'Could not check')

## System Memory
\`\`\`
$(free -h)
\`\`\`

## Action Taken
Sending SIGTERM to spinning fileWatcher process(es): $watcher_pids

_Auto-detected by \`scripts/pmo/devenv_monitor.sh\` — check_filewatcher_spin_"

        # Auto-remediate: kill the spinning watcher
        if [[ "$DEVENV_MONITOR_ALERT_ONLY" == "1" ]]; then
          log "  [ALERT_ONLY_MODE] Would SIGTERM fileWatcher PIDs: $watcher_pids — SKIPPED (RCA 2026-02-26)"
          log "  Action: GitHub issue created. To enable kills: DEVENV_MONITOR_ALERT_ONLY=0"
        else
          echo "$watcher_lines" | awk '{print $2}' | xargs -r kill -SIGTERM 2>/dev/null || true
          log "  SIGTERM sent to fileWatcher PIDs: $watcher_pids"
        fi
        rm -f "$spin_state_file"

        create_issue \
          "🚨 [AUTO] fileWatcher CPU spin ${max_cpu}% for ${spin_dur}s — OOM risk" \
          "$body" \
          "type:bug,priority-p0" \
          "filewatcher_spin_$(date +%Y%m%d)"
      else
        warn_log "fileWatcher spin timer: ${spin_dur}/${WATCHER_CPU_SPIN_SECS}s at ${max_cpu}% CPU"
      fi
    fi
  else
    rm -f "$spin_state_file"
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# CHECK 3: Extension host / Pylance memory bloat
# ─────────────────────────────────────────────────────────────────────────────
check_ext_host_memory() {
  record_ext_host_kill_event() {
    local now_ts="$1"
    local pid="$2"
    local rss_mb="$3"
    local kill_events_file="$STATE_DIR/ext_host_kill_events"

    {
      if [[ -f "$kill_events_file" ]]; then
        awk -v cutoff="$(( now_ts - EXT_HOST_REPEAT_KILL_WINDOW_SECS ))" '$1 >= cutoff {print $1}' "$kill_events_file"
      fi
      echo "$now_ts"
    } > "${kill_events_file}.tmp"
    mv "${kill_events_file}.tmp" "$kill_events_file"

    local kill_count
    kill_count=$(wc -l < "$kill_events_file" | tr -d ' ')

    if [[ "$kill_count" -ge "$EXT_HOST_REPEAT_KILL_THRESHOLD" ]]; then
      error_log "EXT_HOST_REPEAT_ESCALATION: ${kill_count} ExtensionHost kills in ${EXT_HOST_REPEAT_KILL_WINDOW_SECS}s"
      create_issue \
        "🚨 [AUTO-OOM] Repeated ExtensionHost kills (${kill_count} in ${EXT_HOST_REPEAT_KILL_WINDOW_SECS}s)" \
        "## 🚨 Repeated ExtensionHost OOM Kill Pattern\n\n**Detected:** $(ts)\n**Recent kill count:** ${kill_count}\n**Window:** ${EXT_HOST_REPEAT_KILL_WINDOW_SECS}s\n**Latest PID:** ${pid}\n**Latest RSS:** ${rss_mb}MB\n\n## Impact\nRepeated kill/restart loops indicate likely persistent ExtensionHost memory pressure or leak.\n\n## Immediate Actions\n1. Capture extensionHost heap snapshots\n2. Validate extension set + workspace indexing boundaries\n3. Tune memory limits and reduce high-churn watch surfaces\n\n_Auto-detected by \`scripts/pmo/devenv_monitor.sh\` — check_ext_host_memory_" \
        "type:bug,priority-p0" \
        "ext_host_repeat_kills"
    fi
  }

  if [[ "${DEVENV_MONITOR_FORCE_EXT_HOST_KILL_EVENT:-0}" == "1" ]]; then
    warn_log "DEVENV_MONITOR_FORCE_EXT_HOST_KILL_EVENT=1 — simulating ExtensionHost kill event"
    record_ext_host_kill_event "$(date +%s)" "SIMULATED" "$EXT_HOST_KILL_MB"
    return 0
  fi

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    local pid rss_kb rss_mb proc_type
    pid=$(echo "$line" | awk '{print $1}')
    rss_kb=$(echo "$line" | awk '{print $2}')
    rss_mb=$(( rss_kb / 1024 ))
    proc_type="unknown"
    echo "$line" | grep -q 'pylance\|pyright'      && proc_type="Pylance-LSP"
    echo "$line" | grep -q -- '--type=extensionHost' && proc_type="ExtensionHost"
    echo "$line" | grep -q 'terraform-ls'          && proc_type="terraform-ls"
    echo "$line" | grep -q 'spell-checker\|cSpell'  && proc_type="cSpell"

    # Only terminate heavy VS Code host and Pylance processes; warn-only for helpers
    if [[ "$proc_type" != "ExtensionHost" && "$proc_type" != "Pylance-LSP" ]]; then
      if [[ $rss_mb -ge $EXT_HOST_WARN_MB ]]; then
        warn_log "${proc_type} PID=$pid at ${rss_mb}MB (WARN threshold: ${EXT_HOST_WARN_MB}MB)"
      fi
      continue
    fi

    if [[ $rss_mb -ge $EXT_HOST_KILL_MB ]]; then
      error_log "${proc_type} PID=$pid at ${rss_mb}MB — EXCEEDS kill threshold (${EXT_HOST_KILL_MB}MB)"
      if [[ "$DEVENV_MONITOR_ALERT_ONLY" == "1" ]]; then
        error_log "[ALERT_ONLY_MODE] Would SIGTERM ${proc_type} PID=$pid — SKIPPED to prevent VS Code disconnect (RCA 2026-02-26)"
        error_log "  Action: GitHub issue will be created. To enable kills: DEVENV_MONITOR_ALERT_ONLY=0"
      else
        error_log "${proc_type} PID=$pid at ${rss_mb}MB — killing before OOM"
        kill -SIGTERM "$pid" 2>/dev/null || true
      fi
      if [[ "$proc_type" == "ExtensionHost" ]]; then
        record_ext_host_kill_event "$(date +%s)" "$pid" "$rss_mb"
      fi

      local body
      body="## 🚨 ${proc_type} Memory Kill

**PID:** $pid
**RSS:** ${rss_mb}MB (kill threshold: ${EXT_HOST_KILL_MB}MB)
**Detected:** $(ts)

## Memory Snapshot
\`\`\`
$(ps aux --sort=-%mem 2>/dev/null | grep -E 'extensionHost|pylance|terraform' | head -8)
\`\`\`
\`\`\`
$(free -h)
\`\`\`

## Heap Ceiling Status
- argv.json: \`$(cat ~/.vscode-server/data/argv.json 2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); print(f'max-old-space-size={d.get(\"max-old-space-size\",\"NOT SET\")}')" 2>/dev/null || echo "FILE MISSING ❌")\`
- NODE_OPTIONS (Process Env): \`$(strings /proc/$pid/environ 2>/dev/null | grep NODE_OPTIONS || echo "NOT SET IN PROCESS ❌")\`
- NODE_OPTIONS (Monitor Env): \`${NODE_OPTIONS:-NOT SET ❌}\`

## Action
SIGTERM sent. VS Code will restart the extension host automatically.

_Auto-detected by \`scripts/pmo/devenv_monitor.sh\` — check_ext_host_memory_"
      create_issue \
        "🚨 [AUTO-OOM] ${proc_type} killed at ${rss_mb}MB — PID $pid" \
        "$body" \
        "type:bug,priority-p0" \
        "ext_host_kill_${pid}"

    elif [[ $rss_mb -ge $EXT_HOST_WARN_MB ]]; then
      warn_log "${proc_type} PID=$pid at ${rss_mb}MB (WARN threshold: ${EXT_HOST_WARN_MB}MB)"
    fi

  done < <(ps aux --no-headers 2>/dev/null | awk '
    /--type=extensionHost|pylance|pyright|terraform-ls|spell-checker/ {
      print $2, $6, substr($0, index($0,$11))
    }
  ')
}

# ─────────────────────────────────────────────────────────────────────────────
# CHECK 4: Duplicate VS Code sessions (post-OOM reconnect doesn't kill stale)
# ─────────────────────────────────────────────────────────────────────────────
check_duplicate_sessions() {
  local session_count
  session_count=$(ps -eo cmd 2>/dev/null | awk '/type=extensionHost/ && !/awk/ {count++} END {print count+0}')

  if [[ $session_count -gt 1 ]]; then
    error_log "DUPLICATE VS CODE SESSIONS: $session_count extensionHost instances running"

    local session_details
    session_details=$(ps -eo pid,lstart,rss,cmd 2>/dev/null | \
      awk '/type=extensionHost/ && !/awk/ {
        pid=$1
        started=$2" "$3" "$4" "$5" "$6
        rss_mb=int($7/1024)
        printf "PID=%-7s STARTED=%s RSS=%-6sMB\n", pid, started, rss_mb
      }')

    local stale_pids
    stale_pids=$(ps -eo pid,etimes,cmd 2>/dev/null | \
      awk '/type=extensionHost/ && !/awk/ {print $1" "$2}' | \
      sort -k2,2n | awk 'NR>1 {print $1}' | xargs)

    # Auto-run cleanup script for immediate remediation
    if [[ -x "$SCRIPT_DIR/vscode_session_cleanup.sh" ]]; then
      log "  Executing vscode_session_cleanup.sh for immediate remediation..."
      bash "$SCRIPT_DIR/vscode_session_cleanup.sh" 2>&1 | grep -v "^\[" | sed 's/^/    /'
    else
      warn_log "vscode_session_cleanup.sh not found or not executable at $SCRIPT_DIR/vscode_session_cleanup.sh"
    fi

    local remediation
    remediation="Cleanup script executed. If duplicates persist, manual intervention needed."
    if [[ -n "$stale_pids" ]]; then
      if [[ "$DEVENV_MONITOR_ALERT_ONLY" == "1" ]]; then
        warn_log "[ALERT_ONLY_MODE] Would SIGTERM stale PIDs: $stale_pids — SKIPPED (RCA 2026-02-26)"
        remediation="ALERT_ONLY_MODE: Stale PIDs logged but not killed. Set DEVENV_MONITOR_ALERT_ONLY=0 to enable."
      else
        kill -SIGTERM $stale_pids 2>/dev/null || true
        remediation="Sent SIGTERM to stale extensionHost PID(s): $stale_pids"
        log "  Auto-remediation applied: $remediation"
      fi
    fi

    local body
    body="## ⚠️ Duplicate VS Code Sessions

**Count:** $session_count extensionHost instances
**Detected:** $(ts)

This means VS Code reconnected after an OOM crash without killing the stale session.
Each extra session adds ~800-1200MB RAM, directly causing the NEXT OOM crash.

## Sessions Before Cleanup
\`\`\`
$session_details
\`\`\`

## Auto-Remediation
$remediation

A cleanup script (vscode_session_cleanup.sh) has been executed to terminate stale sessions.

If duplicates still remain, re-run monitor or kill oldest manually:
\`\`\`bash
ps -eo pid,etimes,cmd | grep 'type=extensionHost' | grep -v grep | sort -k2,2nr
./scripts/pmo/vscode_session_cleanup.sh  # Automated cleanup
\`\`\`

## Prevention
To prevent reconnect duplicates:
1. Ensure adequate memory (32GB+) to avoid OOM crashes
2. Disable memory-heavy extensions (cSpell, GitLens, Continue)
3. Configure aggressive memory thresholds

_Auto-detected by \`scripts/pmo/devenv_monitor.sh\` — check_duplicate_sessions_"
    create_issue \
      "⚠️ [AUTO] Duplicate VS Code sessions: $session_count extensionHosts running" \
      "$body" \
      "type:bug,priority-p1" \
      "duplicate_sessions_$(date +%Y%m%d_%H)"
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# CHECK 5: NODE_OPTIONS heap ceiling drift
# ─────────────────────────────────────────────────────────────────────────────
check_node_options_drift() {
  local marker="# elevatediq-oom-guardrail"
  local bashrc_ok=false
  local profile_ok=false

  grep -q "$marker" "$HOME/.bashrc" 2>/dev/null && bashrc_ok=true
  grep -q "$marker" "$HOME/.profile" 2>/dev/null && profile_ok=true

  # Also check if the value is correct even if marker is present
  if [[ "$bashrc_ok" == "true" ]]; then
    if ! grep -q "max-old-space-size=${DESIRED_HEAP_MB}" "$HOME/.bashrc" 2>/dev/null; then
      bashrc_ok=false
    fi
  fi
  if [[ "$profile_ok" == "true" ]]; then
    if ! grep -q "max-old-space-size=${DESIRED_HEAP_MB}" "$HOME/.profile" 2>/dev/null; then
      profile_ok=false
    fi
  fi

  if [[ "$bashrc_ok" == "false" || "$profile_ok" == "false" ]]; then
    warn_log "NODE_OPTIONS heap guardrails MISSING or OUTDATED in shell profiles (bashrc=$bashrc_ok, profile=$profile_ok)"
    enforce_heap_guardrails

    local body
    body="## 🚨 Heap Ceiling Config Drift

**Detected:** $(ts)
**Desired Heap:** ${DESIRED_HEAP_MB}MB

The \`NODE_OPTIONS\` heap guardrail was missing, outdated, or lacked the safety marker in \`~/.bashrc\` or \`~/.profile\`.

## Action
Auto-remediation applied. Profiles updated to:
\`\`\`bash
export NODE_OPTIONS=\"\${NODE_OPTIONS} --max-old-space-size=${DESIRED_HEAP_MB}\"
\`\`\`

_Auto-detected by \`scripts/pmo/devenv_monitor.sh\` — check_node_options_drift_"

    create_issue \
      "🚨 [CONFIG-DRIFT] NODE_OPTIONS heap guardrails updated to ${DESIRED_HEAP_MB}MB" \
      "$body" \
      "type:bug,priority-p1" \
      "node_options_drift_$(date +%Y%m%d)"
  else
    ok_log "NODE_OPTIONS heap guardrails are up-to-date (${DESIRED_HEAP_MB}MB)"
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# CHECK 6: watcherExclude config drift (**.git/** removed)
# ─────────────────────────────────────────────────────────────────────────────
check_watcher_exclude_drift() {
  local settings_file="$REPO_ROOT/.vscode/settings.json"
  [[ ! -f "$settings_file" ]] && { warn_log ".vscode/settings.json not found"; return 0; }

  local git_excluded
  git_excluded=$(settings_json_query watcher_git 2>/dev/null || echo "error")

  if [[ "$git_excluded" == error:* || "$git_excluded" == "error" ]]; then
    warn_log "Unable to parse .vscode/settings.json as JSONC; skipping watcherExclude drift check"
    return 0
  fi

  if [[ "$git_excluded" == "no" ]]; then
    error_log "CRITICAL CONFIG DRIFT: **/.git/** missing from files.watcherExclude"
    create_issue \
      "🚨 [CONFIG-DRIFT] **/.git/** removed from files.watcherExclude — fileWatcher spin OOM risk" \
      "## 🚨 Critical Config Drift Detected

**Detected:** $(ts)
**File:** \`.vscode/settings.json\`

The \`\"**/.git/**\": true\` entry in \`files.watcherExclude\` has been removed.
This was the PRIMARY root cause of 2 weeks of daily OOM crashes (#3622).

Without this exclusion, VS Code fileWatcher watches every git write
(\`HEAD\`, \`COMMIT_EDITMSG\`, \`refs/**\`, \`logs/**\`) and enters a 99-100% CPU
inotify spin loop with the 994MB git history.

## Fix
\`\`\`bash
# Add to .vscode/settings.json files.watcherExclude:
\"**/.git/**\": true
\`\`\`

_Auto-detected by \`scripts/pmo/devenv_monitor.sh\` — check_watcher_exclude_drift_" \
      "type:bug,priority-p0" \
      "watcher_exclude_drift_git"
  fi

  return 0
}

# ─────────────────────────────────────────────────────────────────────────────
# CHECK 7: System memory pressure
# ─────────────────────────────────────────────────────────────────────────────
check_system_memory() {
  local available_kb
  available_kb=$(awk '/MemAvailable/ {print $2}' /proc/meminfo 2>/dev/null || echo 99999999)
  local available_mb=$(( available_kb / 1024 ))

  if [[ $available_mb -lt $SYS_MEM_WARN_MB ]]; then
    error_log "SYSTEM MEMORY CRITICAL: Only ${available_mb}MB available (threshold: ${SYS_MEM_WARN_MB}MB)"

    local body
    body="## ⚠️ System Memory Critically Low

**Available:** ${available_mb}MB
**Threshold:** ${SYS_MEM_WARN_MB}MB
**Detected:** $(ts)

## Memory Breakdown
\`\`\`
$(free -h)
\`\`\`

## Top Memory Consumers
\`\`\`
$(ps aux --sort=-%mem 2>/dev/null | head -15)
\`\`\`

_Auto-detected by \`scripts/pmo/devenv_monitor.sh\` — check_system_memory_"
    create_issue \
      "⚠️ [AUTO] System memory critical: ${available_mb}MB available — OOM imminent" \
      "$body" \
      "type:bug,priority-p0,infrastructure" \
      "sys_mem_$(date +%Y%m%d_%H)"
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# CHECK 8: .venv file explosion
# ─────────────────────────────────────────────────────────────────────────────
check_venv_size() {
  if [[ -d "$REPO_ROOT/.venv" ]]; then
    local venv_files
    venv_files=$(find "$REPO_ROOT/.venv" -type f 2>/dev/null | wc -l)
    if [[ $venv_files -gt $VENV_FILE_LIMIT ]]; then
      # Suppress false positive: if .venv is already in python.analysis.exclude
      # in .vscode/settings.json, Pylance will NOT index it — no bloat risk.
      local settings_file="$REPO_ROOT/.vscode/settings.json"
      if [[ -f "$settings_file" ]] && settings_json_query venv_excluded >/dev/null 2>&1; then
        ok_log ".venv has ${venv_files} files but is already in python.analysis.exclude — Pylance bloat risk is ZERO, skipping alert"
        return 0
      fi
      warn_log ".venv has ${venv_files} files (>${VENV_FILE_LIMIT}) — Pylance will attempt to analyze all stubs"
      create_issue \
        "⚠️ [DEVENV] .venv has ${venv_files} files — Pylance LSP bloat risk" \
        "## .venv File Count Explosion

**Count:** ${venv_files} files
**Limit:** ${VENV_FILE_LIMIT}
**Detected:** $(ts)

This usually means TF/CUDA/AI packages are installed in the dev venv.
Pylance will try to load all their type stubs, causing 4-8GB heap use.

## Fix
Consider separating AI/GPU packages into a dedicated venv or ensuring
\`python.analysis.exclude\` covers \`.venv\`.

_Auto-detected by \`scripts/pmo/devenv_monitor.sh\` — check_venv_size_" \
        "type:task,priority-p1" \
        "venv_explosion_$(date +%Y%m%d)"
    fi
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# CHECK 9: Git repo size growth
# ─────────────────────────────────────────────────────────────────────────────
check_git_size() {
  local git_size_kb
  git_size_kb=$(du -sk "$REPO_ROOT/.git" 2>/dev/null | awk '{print $1}' || echo 0)
  local git_size_mb=$(( git_size_kb / 1024 ))

  if [[ $git_size_mb -gt $GIT_SIZE_WARN_MB ]]; then
    warn_log ".git is ${git_size_mb}MB (>${GIT_SIZE_WARN_MB}MB) — elevated fileWatcher I/O pressure"
    create_issue \
      "⚠️ [DEVENV] .git is ${git_size_mb}MB — elevated fileWatcher I/O pressure" \
      "## .git Repo Size Warning

**Size:** ${git_size_mb}MB
**Threshold:** ${GIT_SIZE_WARN_MB}MB
**Detected:** $(ts)

Large git history increases inotify event volume. Even with \`**/.git/**\` excluded
from fileWatcher, the watcher process still indexes inotify limits.

## Fix
\`\`\`bash
git gc --aggressive --prune=now
git reflog expire --expire=90.days --all
\`\`\`

_Auto-detected by \`scripts/pmo/devenv_monitor.sh\` — check_git_size_" \
      "type:task,priority-p2" \
      "git_size_$(date +%Y%m%d)"
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# CHECK 10: Pylance crash loop (rapid PID change = fast respawn)
# ─────────────────────────────────────────────────────────────────────────────
check_pylance_crash_loop() {
  local pid_file="$STATE_DIR/pylance_pid_history"
  local now
  now=$(date +%s)

  local current_pid
  current_pid=$(ps aux 2>/dev/null | grep 'pylance\|pyright' | grep -v grep | \
    awk 'NR==1{print $2}') || true

  if [[ -z "$current_pid" ]]; then
    rm -f "$pid_file"
    return 0
  fi

  # Append timestamped PID to history
  echo "$now $current_pid" >> "$pid_file"

  # Count unique PIDs in the crash window
  local window_start=$(( now - PYLANCE_CRASH_WINDOW ))
  local unique_pids
  unique_pids=$(awk -v ws="$window_start" '$1 >= ws {print $2}' "$pid_file" 2>/dev/null | \
    sort -u | wc -l)

  # Prune old entries
  awk -v ws="$window_start" '$1 >= ws' "$pid_file" > "${pid_file}.tmp" 2>/dev/null && \
    mv "${pid_file}.tmp" "$pid_file" || true

  if [[ $unique_pids -ge $PYLANCE_CRASH_COUNT ]]; then
    error_log "PYLANCE CRASH LOOP: ${unique_pids} unique PIDs in ${PYLANCE_CRASH_WINDOW}s"
    create_issue \
      "🚨 [AUTO] Pylance crash loop: ${unique_pids} restarts in ${PYLANCE_CRASH_WINDOW}s" \
      "## Pylance LSP Crash Loop Detected

**Restarts:** ${unique_pids} in ${PYLANCE_CRASH_WINDOW}s
**Detected:** $(ts)

## Likely Causes
1. Pylance analyzing files outside \`python.analysis.include\` bounds
2. Missing \`python.analysis.userFileIndexingLimit\` (currently set to 5000)
3. Package with broken stubs in .venv
4. \`pyrightconfig.json\` exclude list has been modified

## Current pyrightconfig.json include
\`\`\`
$(python3 -c "import json; d=json.load(open('$REPO_ROOT/pyrightconfig.json')); print(json.dumps(d.get('include',[]),indent=2))" 2>/dev/null || echo "could not read")
\`\`\`

_Auto-detected by \`scripts/pmo/devenv_monitor.sh\` — check_pylance_crash_loop_" \
      "type:bug,priority-p0" \
      "pylance_crash_loop_$(date +%Y%m%d_%H)"
    # Trim history to avoid unbounded growth
    echo "$now $current_pid" > "$pid_file"
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Check for VSCode crashes and auto-report to GitHub Issues
# ─────────────────────────────────────────────────────────────────────────────
check_vscode_crashes() {
  local crash_reporter_script="$SCRIPT_DIR/crash_reporter.sh"

  if [[ ! -x "$crash_reporter_script" ]]; then
    # Make it executable if needed
    chmod +x "$crash_reporter_script" 2>/dev/null || return 0
  fi

  # Run crash reporter and capture any new issues created
  # Run in subshell to avoid stopping main monitoring if crash reporter fails
  "$crash_reporter_script" process 2>/dev/null || true
}

# ─────────────────────────────────────────────────────────────────────────────
# Status report (human-readable, no issue creation)
# ─────────────────────────────────────────────────────────────────────────────
show_status() {
  echo ""
  echo "════════════════════════════════════════════════════════════"
  echo "  ElevatedIQ Dev Environment Monitor — Status Report"
  echo "  $(ts)"
  echo "════════════════════════════════════════════════════════════"

  echo ""
  echo "📊 SYSTEM MEMORY"
  free -h | grep -E 'Mem|Swap'

  echo ""
  echo "🔍 VS CODE PROCESSES (RSS)"
  ps aux --no-headers 2>/dev/null | grep -E 'extensionHost|pylance|fileWatcher|terraform-ls' | \
    grep -v grep | \
    awk '{printf "  %-14s PID=%-8s CPU=%-6s RSS=%-6sMB\n",
      (/extensionHost/?"ExtHost":(/pylance|pyright/?"Pylance":(/fileWatcher/?"FileWatcher":"Other"))),
      $2, $3"%", int($6/1024)}' | head -10
  local sessions
  sessions=$(ps aux 2>/dev/null | grep 'type=extensionHost' | grep -v grep | wc -l)
  echo "  ExtHost sessions: $sessions $([ "$sessions" -gt 1 ] && echo "⚠️ DUPLICATE" || echo "✅")"

  echo ""
  echo "🔒 HEAP CEILING"
  local argv_val
  argv_val=$(python3 -c "import json; d=json.load(open('$VSCODE_ARGV_PATH')); print(f\"{d.get('max-old-space-size','MISSING')}MB\")" 2>/dev/null || echo "FILE MISSING ❌")
  echo "  argv.json max-old-space-size: $argv_val"
  echo "  NODE_OPTIONS in .bashrc: $(grep -c 'max-old-space-size' ~/.bashrc 2>/dev/null && echo '✅' || echo '❌')"
  echo "  NODE_OPTIONS in .profile: $(grep -c 'max-old-space-size' ~/.profile 2>/dev/null && echo '✅' || echo '❌')"

  echo ""
  echo "👁️ WATCHER EXCLUDE"
  local git_excl
  if [[ -f "$REPO_ROOT/.vscode/settings.json" ]]; then
    git_excl=$(settings_json_query watcher_summary 2>/dev/null || true)
    [[ -z "$git_excl" || "$git_excl" == error:* ]] && git_excl="entries=0 git_excluded=❌ PARSE_ERROR"
  else
    git_excl="entries=0 git_excluded=❌ SETTINGS_MISSING"
  fi
  echo "  settings.json: $git_excl"

  echo ""
  echo "📁 SIZES"
  printf "  .git:   %s\n" "$(du -sh "$REPO_ROOT/.git" 2>/dev/null | cut -f1)"
  printf "  .venv:  %s files\n" "$(find "$REPO_ROOT/.venv" -type f 2>/dev/null | wc -l)"

  echo ""
  echo "📋 RECENT ISSUES CREATED"
  tail -5 "$ISSUE_DEDUP_DB" 2>/dev/null || echo "  None yet"
  echo ""
  echo "📄 LOG: $LOG_FILE"
  echo "════════════════════════════════════════════════════════════"
}

# ─────────────────────────────────────────────────────────────────────────────
# systemd user service installer
# ─────────────────────────────────────────────────────────────────────────────
install_service() {
  local service_dir="$HOME/.config/systemd/user"
  mkdir -p "$service_dir"

  local script_path
  script_path=$(realpath "$SCRIPT_DIR/devenv_monitor.sh")
  local path_env
  path_env=$(echo "$PATH")

  cat > "$service_dir/elevatediq-devenv-monitor.service" << EOF
[Unit]
Description=ElevatedIQ Dev Environment Monitor (OOM + fileWatcher protection)
After=default.target

[Service]
Type=simple
ExecStart=${script_path} --watch
Restart=always
RestartSec=30
StandardOutput=append:${LOG_FILE}
StandardError=append:${LOG_FILE}
Environment=QUIET=true
Environment=HOME=${HOME}
Environment=PATH=${path_env}

[Install]
WantedBy=default.target
EOF

  systemctl --user daemon-reload
  systemctl --user enable elevatediq-devenv-monitor.service
  systemctl --user start elevatediq-devenv-monitor.service
  echo "✅ Service installed and started."
  echo "   Status: systemctl --user status elevatediq-devenv-monitor"
  echo "   Logs:   journalctl --user -u elevatediq-devenv-monitor -f"
  echo "   Log file: $LOG_FILE"
}

uninstall_service() {
  systemctl --user stop elevatediq-devenv-monitor.service 2>/dev/null || true
  systemctl --user disable elevatediq-devenv-monitor.service 2>/dev/null || true
  rm -f "$HOME/.config/systemd/user/elevatediq-devenv-monitor.service"
  systemctl --user daemon-reload
  echo "✅ Service removed."
}

# ── Monitor 11: Backend Connectivity Check ────────────────────────────────────
# [NIST-SC-7] Boundary protection & availability check
check_backend_connectivity() {
  local hosts_env=""
  if [[ -f "$REPO_ROOT/infrastructure/hosts.env" ]]; then
    hosts_env="$REPO_ROOT/infrastructure/hosts.env"
  elif [[ -f "$REPO_ROOT/infra/hosts.env" ]]; then
    hosts_env="$REPO_ROOT/infra/hosts.env"
  fi

  if [[ -z "$hosts_env" ]]; then
    warn_log "hosts.env not found (checked infrastructure/hosts.env, infra/hosts.env) - skipping backend check"
    return 0
  fi

  host_env_value() {
    local key="$1"
    local value
    value=$(grep -E "^[[:space:]]*${key}[[:space:]]*=" "$hosts_env" | head -n1 | \
      sed -E "s/^[^=]+=//; s/[[:space:]]*#.*$//; s/^[[:space:]]+//; s/[[:space:]]+$//; s/^\"//; s/\"$//; s/^'//; s/'$//")
    echo "$value"
  }

  first_non_empty_host() {
    local candidate
    for key in "$@"; do
      candidate="$(host_env_value "$key")"
      if [[ -n "$candidate" ]]; then
        echo "$candidate"
        return 0
      fi
    done
    return 1
  }

  # Extract key hosts
  local prod_host
  prod_host="$(first_non_empty_host ONPREM_COMPUTE_HOST ONPREM_FULLSTACK_NODE DEPLOY_TARGET_HOST || true)"
  local dev_host
  dev_host="$(first_non_empty_host ONPREM_DEV_HOST ONPREM_FULLSTACK_NODE DEPLOY_TARGET_HOST || true)"

  # Check Prod Host (.42)
  if [[ -n "$prod_host" ]]; then
    if ping -c 1 -W 1 "$prod_host" > /dev/null 2>&1; then
       ok_log "Production Compute Host ($prod_host) is reachable"
    else
      warn_log "Production Compute Host ($prod_host) is UNREACHABLE"
      create_issue "[DEVENV] Production Compute Host $prod_host is Unreachable" \
        "The on-prem compute host is not responding to ping. This will block GPU inference.
         - Host: $prod_host
         - Action: Check network/VPN/power." "type:infra,priority-p1" "backend_unreachable_prod"
    fi
  fi

  # Check Dev Host (.31)
  if [[ -n "$dev_host" ]]; then
    if ping -c 1 -W 1 "$dev_host" > /dev/null 2>&1; then
      ok_log "Development Host ($dev_host) is reachable"
    else
      warn_log "Development Host ($dev_host) is UNREACHABLE"
      create_issue "[DEVENV] Development Host $dev_host is Unreachable" \
        "The on-prem development host is not responding to ping. This will block dev GPU workloads.
         - Host: $dev_host
         - Action: Check connectivity to isolated VLAN 4042." "type:infra,priority-p2" "backend_unreachable_dev"
    fi
  fi
}

# ── Monitor 12: Workload Placement Protection ───────────────────────────────
# [NIST-AC-2, NIST-SC-7] Enforces workload isolation between nodes.
# Specifically ensures NO high-compute tasks (pytest, docker) run on .31.
check_workload_violation() {
  local workstation_ip="192.168.168.31"
  local current_ip
  current_ip=$(hostname -I | awk '{print $1}' || echo "unknown")

  # Only enforce on the workstation
  if [[ "$current_ip" != *"$workstation_ip"* ]]; then
    return 0
  fi

  local violations=()

  # 1. 🔍 Detect pytest processes
  local pytest_pids
  pytest_pids=$(pgrep -f pytest || true)
  if [[ -n "$pytest_pids" ]]; then
    violations+=("pytest")
  fi

  # 2. 🔍 Detect docker containers
  if command -v docker &>/dev/null; then
    local running_containers
    running_containers=$(docker ps -q 2>/dev/null | wc -l || echo 0)
    if [[ "$running_containers" -gt 0 ]]; then
      violations+=("docker-containers")
    fi
  fi

  # 3. 🔍 Detect high CPU non-VSCode processes
  # Any process using > 70% CPU that isn't node (VS Code), pylance, or terraform-ls
  local high_cpu_proc
  high_cpu_proc=$(ps aux --sort=-%cpu | awk 'NR>1 && $3 > 70.0 && $11 !~ /node|terraform-ls|pylance|bash|sshd/ {print $11}' | head -n1)
  if [[ -n "$high_cpu_proc" ]]; then
    violations+=("high-cpu-unauthorized[$high_cpu_proc]")
  fi

  if [[ ${#violations[@]} -gt 0 ]]; then
    error_log "Workload placement violation detected on WORKSTATION (.31): ${violations[*]}"

    # Active Remediation: Kill forbidden processes
    if [[ " ${violations[*]} " =~ " pytest " ]]; then
      warn_log "Killing unauthorized pytest processes..."
      pkill -9 -f pytest || true
    fi

    if [[ " ${violations[*]} " =~ " docker-containers " ]]; then
      warn_log "Stopping unauthorized Docker containers..."
      docker stop $(docker ps -q) &>/dev/null || true
    fi

    # Create Issue
    local body="## 🛑 Workload Placement Violation — WORKSTATION (.31)

**Detected at:** $(ts)
**Violations:** ${violations[*]}

### Process Snapshot
\`\`\`
$(ps aux --sort=-%cpu | head -n 15)
\`\`\`

### Context
Policy mandates that all compute-heavy or service workloads (Docker, Pytest, Inference)
MUST run on [192.168.168.42](192.168.168.42).
The Workstation ([192.168.168.31](192.168.168.31)) is for coding and docs only.

### Auto-Remediation
- [x] Unauthorized processes (pytest/docker) have been terminated/stopped.

### Actions Required
- Investigate why these workloads were started on the workstation.
- Ensure VS Code tasks are configured with \`DEPLOY_TARGET_HOST=192.168.168.42\`."

    create_issue "[GOV] Workload Placement Violation on Workstation (.31)" \
      "$body" "security,foundation,priority-p1" "workstation_workload_violation"
  else
    ok_log "Workload isolation check passed on $current_ip"
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────
run_all_checks() {
  check_kernel_oom || true
  normalize_ext_host_thresholds
  check_filewatcher_spin || true
  check_ext_host_memory || true
  check_duplicate_sessions || true
  check_node_options_drift || true
  check_watcher_exclude_drift || true
  check_system_memory || true
  check_venv_size || true
  check_git_size || true
  check_pylance_crash_loop || true
  check_vscode_crashes || true
  check_backend_connectivity || true
  check_workload_violation || true
}

main() {
  local mode="${1:---once}"
  case "$mode" in
    --status)
      show_status
      ;;
    --watch)
      log "Starting continuous monitoring (interval=30s, 11 checks active)"
      log "Thresholds: watcher_cpu=${WATCHER_CPU_WARN}%, ext_mem_kill=${EXT_HOST_KILL_MB}MB, sys_mem_warn=${SYS_MEM_WARN_MB}MB"
      while true; do
        run_all_checks || true
        sleep 30
      done
      ;;
    --install)
      install_service
      ;;
    --uninstall)
      uninstall_service
      ;;
    --once|-*)
      log "Running full scan (11 checks)"
      run_all_checks
      log "Scan complete. Log: $LOG_FILE"
      ;;
  esac
}

main "${1:---once}"
