#!/bin/bash
# VSCode Crash Reporter - Auto-detect crashes and create GitHub Issues
# Monitors VSCode crash logs AND VS Code Server exthost logs, automatically
# reporting extension activation failures, Copilot crashes, and all [error]
# level events to GitHub Issues with root cause analysis and remediation steps.
#
# Issue: #5405 - VSCode/Copilot crash auto-report to git issues
# NIST: SI-2 (Flaw Remediation), AU-2 (Audit Events), SI-11 (Error Handling)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CRASH_LOG_DIR="${HOME}/.vscode/crash-logs"
VSCODE_SERVER_LOG_DIR="${HOME}/.vscode-server/data/logs"
CRASH_STATE_FILE="${REPO_ROOT}/.pmo/crash-reporter-state.json"
CRASH_HISTORY_FILE="${REPO_ROOT}/.pmo/crash-history.json"
EXTHOST_ERROR_STATE="${REPO_ROOT}/.pmo/exthost-error-state.json"
REPO="kushin77/ElevatedIQ-Mono-Repo"

# How many hours back to scan exthost logs (avoid re-reporting old errors)
EXTHOST_LOOKBACK_HOURS="${EXTHOST_LOOKBACK_HOURS:-2}"
# Max errors to report per run (prevent flood if many new errors)
MAX_EXTHOST_ISSUES_PER_RUN="${MAX_EXTHOST_ISSUES_PER_RUN:-3}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Initialize state files
init_state() {
  mkdir -p "$(dirname "$CRASH_STATE_FILE")"

  if [[ ! -f "$CRASH_STATE_FILE" ]]; then
    echo '{"processed_crashes": {}}' > "$CRASH_STATE_FILE"
  fi

  if [[ ! -f "$CRASH_HISTORY_FILE" ]]; then
    echo '{"crashes": [], "deduplications": []}' > "$CRASH_HISTORY_FILE"
  fi

  if [[ ! -f "$EXTHOST_ERROR_STATE" ]]; then
    echo '{"reported_fingerprints": {}}' > "$EXTHOST_ERROR_STATE"
  fi
}

# ── VS Code Server exthost log scanning (Issue #5405) ─────────────────────────

# Build a stable fingerprint for an exthost error line (for deduplication)
exthost_error_fingerprint() {
  local error_line="$1"
  # Strip timestamp, keep error message core. Normalize PIDs/paths.
  echo "$error_line" \
    | sed -E 's/^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]+ //' \
    | sed -E 's|/[^ ]+/[0-9]+/||g' \
    | sed -E 's/PID=[0-9]+/PID=X/g' \
    | md5sum | awk '{print $1}'
}

# Classify an exthost error and return metadata as key=value pairs
classify_exthost_error() {
  local error_line="$1"
  local title="" severity="medium" label="crash-report" remediation=""

  if echo "$error_line" | grep -q "Activating extension.*failed"; then
    local ext_id
    ext_id=$(echo "$error_line" | grep -oP 'Activating extension \K[^ ]+' || echo "unknown")
    title="[AUTO-CRASH] Extension activation failed: ${ext_id}"
    severity="high"
    remediation="Run: \`code --uninstall-extension ${ext_id}\` or reinstall. Check for missing .wasm/.dll files. If ENOENT, the extension package is corrupted — reinstall from marketplace."
  elif echo "$error_line" | grep -q "ENOENT\|no such file"; then
    local file_ref
    file_ref=$(echo "$error_line" | grep -oP "open '\K[^']+" | head -1 || echo "unknown")
    title="[AUTO-CRASH] Missing file crash: ${file_ref##*/}"
    severity="medium"
    remediation="File not found: \`${file_ref}\`. The extension owning this file may need reinstallation. Run: \`rm -rf ~/.vscode-server/extensions/<ext-name>\` and reload."
  elif echo "$error_line" | grep -q -i "copilot\|github.copilot"; then
    title="[AUTO-CRASH] GitHub Copilot error in VS Code"
    severity="high"
    label="crash-report,copilot"
    remediation="1. Reload VS Code window (Ctrl+Shift+P → Reload Window)\n2. Check Copilot extension version\n3. Sign out/in from GitHub in VS Code\n4. If persists, disable then re-enable the Copilot extension"
  elif echo "$error_line" | grep -q "out of memory\|heap limit\|OOM"; then
    title="[AUTO-CRASH] Extension host out of memory"
    severity="critical"
    remediation="1. Heap limit exceeded in extension host. Check \`~/.vscode-server/data/argv.json\` → \`max-old-space-size\`\n2. Disable memory-heavy extensions\n3. Run devenv_monitor.sh to diagnose"
  elif echo "$error_line" | grep -q "pylance\|pyright\|ms-python"; then
    title="[AUTO-CRASH] Pylance/Python extension error"
    severity="high"
    remediation="1. Check pyrightconfig.json exclude list\n2. Verify \`userFileIndexingLimit: 2000\`\n3. Restart Pylance: Ctrl+Shift+P → Python: Restart Language Server"
  elif echo "$error_line" | grep -q "FATAL\|fatal error"; then
    title="[AUTO-CRASH] FATAL VS Code extension host error"
    severity="critical"
    remediation="Critical error in extension host. Reload VS Code immediately. Check logs at ~/.vscode-server/data/logs/ for full context."
  else
    # Generic [error] line
    local short
    short=$(echo "$error_line" | sed 's/.*\[error\] //' | cut -c1-80)
    title="[AUTO-CRASH] VS Code extension error: ${short}"
    severity="medium"
    remediation="Review the full error context in VS Code exthost logs at \`~/.vscode-server/data/logs/\`. Reload VS Code window to clear transient errors."
  fi

  echo "title=${title}"
  echo "severity=${severity}"
  echo "label=${label}"
  echo "remediation=${remediation}"
}

# Find the most recent VS Code server log session directories
find_recent_log_sessions() {
  local lookback_secs=$(( EXTHOST_LOOKBACK_HOURS * 3600 ))
  find "$VSCODE_SERVER_LOG_DIR" -maxdepth 1 -type d \
    -newer <(date -d "${EXTHOST_LOOKBACK_HOURS} hours ago" +%Y%m%dT%H%M%S 2>/dev/null || date -v-${EXTHOST_LOOKBACK_HOURS}H +%Y%m%dT%H%M%S 2>/dev/null || echo "") \
    2>/dev/null | sort -r | head -3
}

# Scan VS Code Server exthost logs and create GitHub issues for new [error] entries
scan_vscode_server_logs() {
  command -v gh &>/dev/null || { echo "ℹ️  gh CLI not found, skipping exthost scan"; return 0; }
  [[ -d "$VSCODE_SERVER_LOG_DIR" ]] || { echo "ℹ️  No VS Code server log dir found"; return 0; }

  local issues_created=0
  local lookback_min=$(( EXTHOST_LOOKBACK_HOURS * 60 ))

  # Find exthost log files modified in last LOOKBACK_HOURS
  while IFS= read -r log_file; do
    [[ -f "$log_file" ]] || continue

    # Extract [error] lines from this log
    while IFS= read -r error_line; do
      [[ -z "$error_line" ]] && continue

      # Build fingerprint for dedup
      local fp
      fp=$(exthost_error_fingerprint "$error_line")

      # Skip if already reported
      if jq -e ".reported_fingerprints | has(\"$fp\")" "$EXTHOST_ERROR_STATE" >/dev/null 2>&1; then
        continue
      fi

      # Classify the error
      local title="" severity="medium" label="crash-report" remediation=""
      while IFS='=' read -r key val; do
        case "$key" in
          title)       title="$val" ;;
          severity)    severity="$val" ;;
          label)       label="$val" ;;
          remediation) remediation="$val" ;;
        esac
      done < <(classify_exthost_error "$error_line")

      # Get surrounding context (5 lines after error)
      local line_num
      line_num=$(grep -n -F "$error_line" "$log_file" 2>/dev/null | head -1 | cut -d: -f1 || echo "1")
      local context
      context=$(sed -n "$((line_num > 3 ? line_num-2 : 1)),$((line_num+8))p" "$log_file" 2>/dev/null | head -15 || echo "$error_line")

      local log_session
      log_session=$(basename "$(dirname "$(dirname "$log_file")")")
      local detected_at
      detected_at=$(date '+%Y-%m-%d %H:%M:%S')

      echo -e "${YELLOW}🔍 New VS Code error (${severity}): ${title}${NC}"

      # Create GitHub issue
      local issue_url
      issue_url=$(gh issue create \
        --repo "$REPO" \
        --title "$title" \
        --label "type:bug" \
        --body "## 🔴 VS Code Crash / Extension Error Auto-Report

**Detected:** ${detected_at}
**Severity:** ${severity}
**Log Session:** ${log_session}
**Log File:** \`${log_file}\`
**Error Fingerprint:** \`${fp}\`

## Error Line
\`\`\`
${error_line}
\`\`\`

## Context (surrounding lines)
\`\`\`
${context}
\`\`\`

## Root Cause Analysis
${title#\[AUTO-CRASH\] }

## Remediation Steps
${remediation}

## How to Investigate
\`\`\`bash
# View full log session
cat '${log_file}' | grep -E '\\[error\\]|\\[warning\\]' | tail -50

# View all recent VS Code server errors
find ~/.vscode-server/data/logs -name 'remoteexthost.log' -newer . | xargs grep '\\[error\\]' 2>/dev/null

# Restart extension host
# VS Code: Ctrl+Shift+P → Developer: Restart Extension Host
\`\`\`

---
_Auto-detected by \`scripts/pmo/crash_reporter.sh\` → scan_vscode_server_logs_
_Issue #5405 — All VS Code error logs → GitHub Issues_" \
        2>/dev/null || echo "")

      if [[ -n "$issue_url" ]]; then
        echo -e "${GREEN}✅ Created: ${issue_url}${NC}"

        # Mark fingerprint as reported
        local updated
        updated=$(jq ".reported_fingerprints[\"$fp\"] = { \"url\": \"$issue_url\", \"title\": \"$title\", \"ts\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\" }" "$EXTHOST_ERROR_STATE")
        echo "$updated" > "$EXTHOST_ERROR_STATE"

        (( issues_created++ ))
      fi

      # Rate limiting: stop after max issues per run
      if (( issues_created >= MAX_EXTHOST_ISSUES_PER_RUN )); then
        echo "ℹ️  Max issues per run (${MAX_EXTHOST_ISSUES_PER_RUN}) reached. Remaining errors deferred to next scan."
        return 0
      fi

    done < <(find "$log_file" -newer <(date -d "${lookback_min} minutes ago" +%s 2>/dev/null || echo "") 2>/dev/null \
             && grep -hE '^\s*[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]+ \[error\]' "$log_file" 2>/dev/null \
             | grep -v "^$" || true)

  done < <(find "$VSCODE_SERVER_LOG_DIR" -name "remoteexthost.log" -newer <(stat -c %Z "$EXTHOST_ERROR_STATE" 2>/dev/null | xargs -I{} date -d @{} 2>/dev/null || date -d "${lookback_min} minutes ago") 2>/dev/null | sort -r | head -5)

  if (( issues_created == 0 )); then
    echo "✅ No new VS Code exthost errors found"
  else
    echo -e "${GREEN}✅ Reported ${issues_created} new VS Code error(s) to GitHub Issues${NC}"
  fi
}

# Extract stack trace hash (for deduplication)
get_crash_hash() {
  local crash_log="$1"
  # Get first 5 lines of stack trace for deduplication
  grep -A 5 "^[[:space:]]*at " "$crash_log" 2>/dev/null | head -5 | md5sum | awk '{print $1}' || echo "unknown"
}

# Analyze crash to determine root cause
analyze_crash() {
  local crash_log="$1"

  # Check for common root causes
  local root_cause=""
  local remediation=""
  local severity="medium"

  if grep -q "ExtensionHost" "$crash_log"; then
    if grep -q "out of memory" "$crash_log" -i; then
      root_cause="ExtensionHost out of memory (heap limit exceeded)"
      remediation="Disable memory-intensive extensions or increase VS Code heap limit"
      severity="high"
    elif grep -q "ms-python.vscode-pylance" "$crash_log"; then
      root_cause="Pylance language server crash"
      remediation="Check pyrightconfig.json, reduce file indexing limit"
      severity="high"
    elif grep -q "gitlens" "$crash_log" -i; then
      root_cause="GitLens extension crash"
      remediation="Disable GitLens code lens features in settings.json"
      severity="medium"
    else
      root_cause="Unknown ExtensionHost crash"
      remediation="Check VS Code error logs at ~/.vscode/crash-logs/"
      severity="medium"
    fi
  elif grep -q "FATAL" "$crash_log"; then
    root_cause="VSCode fatal error"
    remediation="Restart VS Code and check workspace integrity"
    severity="critical"
  fi

  echo "{\"root_cause\": \"$root_cause\", \"remediation\": \"$remediation\", \"severity\": \"$severity\"}"
}

# Extract crash summary
get_crash_summary() {
  local crash_log="$1"
  # Get first few lines with error info
  head -20 "$crash_log" | grep -E "Error|Exception|FATAL" | head -1 || echo "Unknown error"
}

# Create GitHub Issue for crash
create_crash_issue() {
  local crash_log="$1"
  local crash_hash="$2"
  local analysis="$3"

  local root_cause=$(echo "$analysis" | jq -r '.root_cause')
  local remediation=$(echo "$analysis" | jq -r '.remediation')
  local severity=$(echo "$analysis" | jq -r '.severity')
  local summary=$(get_crash_summary "$crash_log")

  # Extract key info from crash log
  local crash_date=$(head -1 "$crash_log" | cut -d' ' -f1-2 2>/dev/null || echo "$(date)")
  local stack_trace=$(grep -A 10 "^[[:space:]]*at " "$crash_log" 2>/dev/null | head -10 || echo "No stack trace available")

  # Check if we've already reported similar crash
  local existing_issue=$(jq -r '.crashes[] | select(.hash == "'$crash_hash'") | .issue_number' "$CRASH_HISTORY_FILE" 2>/dev/null || echo "")

  if [[ -n "$existing_issue" ]]; then
    # Add follow-up comment to existing issue
    gh issue comment "$existing_issue" --repo kushin77/ElevatedIQ-Mono-Repo \
      --body "🔴 **Crash Recurrence Detected** ($(date))

**Crash Count:** $(jq -r '.crashes[] | select(.hash == "'$crash_hash'") | .count' "$CRASH_HISTORY_FILE")
**Latest Timestamp:** $crash_date
**Severity:** $severity

_Auto-detected by crash_reporter.sh_"

    # Update history
    local new_count=$(($(jq -r '.crashes[] | select(.hash == "'$crash_hash'") | .count' "$CRASH_HISTORY_FILE") + 1))
    local updated=$(jq ".crashes[] |= if .hash == \"$crash_hash\" then .count = $new_count else . end" "$CRASH_HISTORY_FILE")
    echo "$updated" > "$CRASH_HISTORY_FILE"

    return 0
  fi

  # Create new issue
  local issue_num=$(gh issue create --repo kushin77/ElevatedIQ-Mono-Repo \
    --title "[AUTO-CRASH] $severity - $summary" \
    --label "type:bug,crash-report,priority-$severity" \
    --body "## 🔴 VSCode Crash Auto-Report

**Timestamp:** $crash_date
**Severity:** $severity
**Hash:** $crash_hash

## Root Cause
\`\`\`
$root_cause
\`\`\`

## Stack Trace
\`\`\`
$stack_trace
\`\`\`

## Remediation Steps
$remediation

## Full Crash Log
[View in workspace](file://${crash_log})

---
_Auto-detected and reported by elite PMO crash_reporter.sh_" 2>&1 | grep -oP 'https://github\.com/.*issues/\K[0-9]+' || echo "error")

  if [[ "$issue_num" != "error" ]]; then
    echo -e "${GREEN}✅ Created issue #$issue_num${NC}"

    # Record in history
    local new_entry="{\"hash\": \"$crash_hash\", \"issue_number\": $issue_num, \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\", \"count\": 1}"
    local updated=$(jq ".crashes += [$new_entry]" "$CRASH_HISTORY_FILE")
    echo "$updated" > "$CRASH_HISTORY_FILE"
  fi
}

# Main: Process new crashes
process_crashes() {
  # 1. Scan classic ~/.vscode/crash-logs/ (existing behavior)
  if [[ -d "$CRASH_LOG_DIR" ]]; then
    local processed=0

    while IFS= read -r crash_log; do
      local crash_hash=$(get_crash_hash "$crash_log")

      if jq -e ".processed_crashes | has(\"$crash_hash\")" "$CRASH_STATE_FILE" >/dev/null 2>&1; then
        continue
      fi

      echo -e "${YELLOW}🔍 Processing crash: $(basename "$crash_log")${NC}"
      local analysis=$(analyze_crash "$crash_log")
      create_crash_issue "$crash_log" "$crash_hash" "$analysis"

      jq ".processed_crashes[\"$crash_hash\"] = \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"" \
        "$CRASH_STATE_FILE" > "${CRASH_STATE_FILE}.tmp"
      mv "${CRASH_STATE_FILE}.tmp" "$CRASH_STATE_FILE"

      ((processed++))
    done < <(find "$CRASH_LOG_DIR" -name "*.json" -o -name "*.log" 2>/dev/null | sort -r | head -20)

    if [[ $processed -gt 0 ]]; then
      echo -e "${GREEN}✅ Processed $processed crash file(s)${NC}"
    fi
  fi

  # 2. Scan VS Code Server exthost logs (Issue #5405 — new capability)
  scan_vscode_server_logs
}

# Command: Status
cmd_status() {
  echo "🔍 VSCode Crash Reporter Status"
  echo "================================"

  if [[ -f "$CRASH_HISTORY_FILE" ]]; then
    local crash_count=$(jq '.crashes | length' "$CRASH_HISTORY_FILE")
    local dedup_count=$(jq '.deduplications | length' "$CRASH_HISTORY_FILE")
    echo "📊 Total unique crashes tracked: $crash_count"
    echo "🔗 Deduplications performed: $dedup_count"

    if [[ $crash_count -gt 0 ]]; then
      echo ""
      echo "Recent crashes:"
      jq -r '.crashes[] | "\(.issue_number): \(.root_cause) (\(.count) occurrences)"' "$CRASH_HISTORY_FILE"
    fi
  fi

  echo ""
  echo "🖥️  VS Code Server Exthost Errors (Issue #5405)"
  echo "--------------------------------------------"
  if [[ -f "$EXTHOST_ERROR_STATE" ]]; then
    local ext_count
    ext_count=$(jq '.reported_fingerprints | length' "$EXTHOST_ERROR_STATE")
    echo "📊 Total unique exthost errors reported: $ext_count"
    if (( ext_count > 0 )); then
      echo ""
      echo "Recent exthost issues:"
      jq -r '.reported_fingerprints | to_entries[] | "  \(.value.ts) → \(.value.url)"' "$EXTHOST_ERROR_STATE" | tail -5
    fi
  else
    echo "  No exthost errors reported yet"
  fi

  echo ""
  echo "📁 Log Directories"
  echo "  Crash logs:       ${CRASH_LOG_DIR} $([ -d "$CRASH_LOG_DIR" ] && echo '✅' || echo '❌ (not found)')"
  echo "  VS Code server:   ${VSCODE_SERVER_LOG_DIR} $([ -d "$VSCODE_SERVER_LOG_DIR" ] && echo '✅' || echo '❌ (not found)')"
}

# Command: Watch (continuous)
cmd_watch() {
  echo "👀 Watching for VSCode crashes..."
  while true; do
    init_state
    process_crashes
    sleep 30
  done
}

# Main
main() {
  local cmd="${1:-process}"

  case "$cmd" in
    process)
      init_state
      process_crashes
      ;;
    status)
      cmd_status
      ;;
    watch)
      cmd_watch
      ;;
    *)
      echo "Usage: $0 {process|status|watch}"
      exit 1
      ;;
  esac
}

main "$@"
