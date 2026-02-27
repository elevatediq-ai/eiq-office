#!/bin/bash
# ElevatedIQ Governance Drift Webhook Monitor
# Real-time monitoring of branch protection baseline drift with Slack alerting
# NIST CM-3: Configuration Change Control

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
PMO_DIR="${REPO_ROOT}/.pmo"
DRIFT_EVENTS_FILE="${PMO_DIR}/drift-events.json"
SLACK_CONFIG_FILE="${PMO_DIR}/governance-slack-config.json"
WATCH_PATHS=(
  "${PMO_DIR}/branch_protection_policy_baseline.json"
  "${PMO_DIR}/branch_protection_baseline_approvals.json"
  "${PMO_DIR}/branch_protection_baseline_versions.json"
  "${REPO_ROOT}/.github/CODEOWNERS"
  "${REPO_ROOT}/.github/workflows/"
)

# Colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

# Initialize drift events ledger
init_drift_ledger() {
  mkdir -p "$PMO_DIR"
  if [[ ! -f "$DRIFT_EVENTS_FILE" ]]; then
    echo '{"events": [], "last_baseline_hash": ""}' > "$DRIFT_EVENTS_FILE"
  fi
}

# Initialize Slack config if needed
init_slack_config() {
  if [[ ! -f "$SLACK_CONFIG_FILE" ]]; then
    cat > "$SLACK_CONFIG_FILE" << 'EOF'
{
  "webhook_url": "https://hooks.slack.com/services/YOUR/WEBHOOK/URL",
  "channel": "#governance-incidents",
  "enabled": false,
  "escalation_timeout_minutes": 5,
  "mention_on_critical": ["@security-team", "@compliance"]
}
EOF
    echo "⚠️  Slack webhook config created at $SLACK_CONFIG_FILE - update webhook_url to enable"
  fi
}

# Get current baseline hash (detection of changes)
get_baseline_hash() {
  # Combine key baseline files to create composite hash
  (
    cat "${PMO_DIR}/branch_protection_policy_baseline.json" 2>/dev/null || echo '{}'
    cat "${PMO_DIR}/branch_protection_baseline_approvals.json" 2>/dev/null || echo '{}'
    cat "${PMO_DIR}/branch_protection_baseline_versions.json" 2>/dev/null || echo '{}'
  ) | jq -s 'add' | md5sum | awk '{print $1}'
}

# Detect which specific baseline fields changed
detect_drift_type() {
  local old_policy="$1"
  local new_policy="$2"

  # Check for missing required-status-checks
  if echo "$old_policy" | jq -e '.require_status_checks' >/dev/null 2>&1; then
    if ! echo "$new_policy" | jq -e '.require_status_checks' >/dev/null 2>&1; then
      echo "required-status-checks_removed|critical"
      return 0
    fi
  fi

  # Check for permission changes
  if echo "$old_policy" | jq -e '.dismiss_stale_reviews' >/dev/null 2>&1; then
    if ! echo "$new_policy" | jq -e '.dismiss_stale_reviews' >/dev/null 2>&1; then
      echo "dismiss-stale-reviews_disabled|high"
      return 0
    fi
  fi

  # Generic drift detected
  echo "baseline_policy_modified|medium"
}

# Post to Slack with retry logic
post_slack_alert() {
  local drift_type="$1"
  local severity="$2"
  local details="$3"

  local slack_url=$(jq -r '.webhook_url' "$SLACK_CONFIG_FILE" 2>/dev/null || echo "")
  local slack_enabled=$(jq -r '.enabled' "$SLACK_CONFIG_FILE" 2>/dev/null || echo "false")
  local channel=$(jq -r '.channel' "$SLACK_CONFIG_FILE" 2>/dev/null || echo "#governance-incidents")

  if [[ "$slack_enabled" != "true" ]] || [[ -z "$slack_url" ]] || [[ "$slack_url" == "https://hooks"* ]]; then
    return 0  # Slack not configured
  fi

  # Determine color and mention based on severity
  local color="warning"
  local mention=""
  case "$severity" in
    critical)
      color="danger"
      mention=" @security-team"
      ;;
    high)
      color="warning"
      mention=" @compliance"
      ;;
  esac

  # Build Slack message
  local payload=$(jq -n \
    --arg channel "$channel" \
    --arg color "$color" \
    --arg drift_type "$drift_type" \
    --arg details "$details" \
    --arg mention "$mention" \
    '{
      "channel": $channel,
      "attachments": [{
        "color": $color,
        "title": "🚨 Governance Baseline Drift Detected",
        "text": "Drift Type: " + $drift_type + $mention,
        "fields": [
          {"title": "Severity", "value": $drift_type | split("|")[1], "short": true},
          {"title": "Type", "value": $drift_type | split("|")[0], "short": true},
          {"title": "Details", "value": $details, "short": false},
          {"title": "Repository", "value": "ElevatedIQ-Mono-Repo", "short": true},
          {"title": "Timestamp", "value": now | todate, "short": true}
        ],
        "footer": "ElevatedIQ Governance Monitor",
        "footer_icon": "https://github.com/favicon.ico"
      }]
    }')

  # Post with retry
  local retry_count=0
  while [[ $retry_count -lt 3 ]]; do
    if curl -X POST -H 'Content-type: application/json' \
      --data "$payload" \
      "$slack_url" 2>/dev/null; then
      echo "✅ Slack alert posted successfully"
      return 0
    fi
    ((retry_count++))
    sleep 1
  done

  echo -e "${YELLOW}⚠️  Slack alert failed after 3 retries${NC}"
  return 1
}

# Create GitHub Issue if Slack unavailable
create_drift_issue() {
  local drift_type="$1"
  local severity="$2"
  local details="$3"

  # Only create if Slack failed or is disabled
  gh issue create --repo kushin77/ElevatedIQ-Mono-Repo \
    --title "[AUTO-DRIFT] $severity - $drift_type" \
    --label "type:drift-alert,priority-$severity" \
    --body "## Governance Baseline Drift Alert

**Drift Type:** $drift_type
**Severity:** $severity
**Timestamp:** $(date -u +%Y-%m-%dT%H:%M:%SZ)

## Details
$details

## Impact
This deviation from approved branch protection baseline may affect:
- Require status checks
- Stale review dismissal
- CODEOWNERS enforcement

## Remediation
Run: \`./scripts/automation/pmo/branch_protection_auto_remediate.sh\`

---
_Auto-created by governance-drift-webhook.sh on baseline drift detection_" 2>/dev/null || true
}

# Record drift event in audit ledger
record_drift_event() {
  local drift_type="$1"
  local severity="$2"
  local details="$3"

  local new_event=$(jq -n \
    --arg type "$drift_type" \
    --arg sev "$severity" \
    --arg details "$details" \
    '{
      "timestamp": now | todate,
      "type": $type,
      "severity": $sev,
      "details": $details,
      "status": "detected",
      "remediated": false
    }')

  local updated=$(jq ".events += [$new_event]" "$DRIFT_EVENTS_FILE")
  echo "$updated" | jq . > "${DRIFT_EVENTS_FILE}.tmp"
  mv "${DRIFT_EVENTS_FILE}.tmp" "$DRIFT_EVENTS_FILE"

  echo -e "${RED}🚨 Drift event recorded: $drift_type ($severity)${NC}"
}

# Main monitoring loop
monitor_baseline_drift() {
  local last_hash=$(jq -r '.last_baseline_hash' "$DRIFT_EVENTS_FILE" 2>/dev/null || echo "")
  local current_hash=$(get_baseline_hash)

  if [[ "$last_hash" != "$current_hash" ]] && [[ -n "$last_hash" ]]; then
    # Baseline has changed - analyze the drift
    echo -e "${YELLOW}📊 Baseline drift detected!${NC}"

    local old_policy=$(cat "${PMO_DIR}/branch_protection_policy_baseline.json" 2>/dev/null || echo '{}')
    local new_policy=$(cat "${PMO_DIR}/branch_protection_policy_baseline.json" 2>/dev/null || echo '{}')

    local drift_info=$(detect_drift_type "$old_policy" "$new_policy")
    local drift_type=$(echo "$drift_info" | cut -d'|' -f1)
    local severity=$(echo "$drift_info" | cut -d'|' -f2)

    local details="Baseline policy changed from hash $last_hash to $current_hash"

    # Alert via Slack + fallback to GitHub Issue
    post_slack_alert "$drift_type" "$severity" "$details"
    create_drift_issue "$drift_type" "$severity" "$details"
    record_drift_event "$drift_type" "$severity" "$details"

    # Update baseline hash
    jq ".last_baseline_hash = \"$current_hash\"" "$DRIFT_EVENTS_FILE" > "${DRIFT_EVENTS_FILE}.tmp"
    mv "${DRIFT_EVENTS_FILE}.tmp" "$DRIFT_EVENTS_FILE"
  fi
}

# Command: Status report
cmd_status() {
  echo -e "${GREEN}🔍 Governance Drift Webhook Status${NC}"
  echo "====================================="
  echo ""

  if [[ -f "$DRIFT_EVENTS_FILE" ]]; then
    local event_count=$(jq '.events | length' "$DRIFT_EVENTS_FILE" 2>/dev/null || echo 0)
    echo "📊 Total drift events detected: $event_count"

    if [[ $event_count -gt 0 ]]; then
      echo ""
      echo "Recent events:"
      jq -r '.events[-5:] | reverse | .[] | "\(.timestamp) - \(.severity | ascii_upcase): \(.type)"' \
        "$DRIFT_EVENTS_FILE" 2>/dev/null
    fi
  fi

  echo ""
  echo "Slack Config: $(jq -r '.enabled' "$SLACK_CONFIG_FILE" 2>/dev/null || echo "Not configured")"
}

# Command: Watch mode
cmd_watch() {
  echo "👀 Watching for governance baseline drift (30s interval)..."
  while true; do
    monitor_baseline_drift || true
    sleep 30
  done
}

# Command: One-time check
cmd_check() {
  monitor_baseline_drift || true
}

# Main
main() {
  init_drift_ledger
  init_slack_config

  local cmd="${1:---check}"
  case "$cmd" in
    check|--check)
      cmd_check
      ;;
    watch|--watch)
      cmd_watch
      ;;
    status|--status)
      cmd_status
      ;;
    *)
      echo "Usage: $0 {check|watch|status}"
      exit 1
      ;;
  esac
}

main "$@"
