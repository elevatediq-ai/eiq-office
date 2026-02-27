#!/usr/bin/env bash
################################################################################
# 🔧 EIQ Systemd Service Manager - Elite 0.01% Production Monitoring
################################################################################
# Purpose: Install, manage, and verify systemd user services for governance
#          monitoring infrastructure (devenv_monitor + governance_drift_webhook)
# Compliance: NIST CM-3 (Change Control), AU-2 (Audit Event Generation)
# Status: Production Ready ($VERSION = 1.0.0)
################################################################################

set -euo pipefail

# =============================================================================
# CONFIGURATION & STATE
# =============================================================================

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../" && pwd)"
SYSTEMD_USER_DIR="${HOME}/.config/systemd/user"
log_file="${REPO_ROOT}/logs/systemd-service-manager.log"
state_file="${REPO_ROOT}/.pmo/systemd-service-state.json"
VERSION="1.0.0"

# Service definitions
declare -A SERVICES=(
  [devenv-monitor]="elevatediq-devenv-monitor.service"
  [governance-monitor]="elevatediq-governance-monitor.service"
)

# =============================================================================
# LOGGING & UTILITIES
# =============================================================================

log() {
  local level="$1"
  shift
  local msg="$*"
  local timestamp=$(date '+%Y-%m-%dT%H:%M:%S%z')
  echo "[$timestamp] [$level] $msg" | tee -a "$log_file"
}

init_state_file() {
  mkdir -p "$(dirname "$state_file")"
  if [[ ! -f "$state_file" ]]; then
    cat > "$state_file" <<EOF
{
  "version": "1.0.0",
  "installed_services": [],
  "last_health_check": null,
  "service_status": {},
  "audit_trail": []
}
EOF
    log "INFO" "Initialized systemd service state file"
  fi
}

record_audit_event() {
  local action="$1"
  local service="$2"
  local status="$3"
  local details="${4:-}"

  local event=$(jq -n \
    --arg action "$action" \
    --arg service "$service" \
    --arg status "$status" \
    --arg details "$details" \
    --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{action: $action, service: $service, status: $status, details: $details, timestamp: $timestamp}')

  state_file_data=$(jq ".audit_trail += [$event]" "$state_file")
  echo "$state_file_data" > "$state_file"
}

# =============================================================================
# SERVICE INSTALLATION & MANAGEMENT
# =============================================================================

install_service() {
  local service_name="$1"
  local service_file="${REPO_ROOT}/.config/systemd/user/${service_name}"

  if [[ ! -f "$service_file" ]]; then
    log "ERROR" "Service file not found: $service_file"
    record_audit_event "install_failed" "$service_name" "error" "service_file_missing"
    return 1
  fi

  # Ensure systemd user directory exists
  mkdir -p "$SYSTEMD_USER_DIR"

  # Copy service file
  cp "$service_file" "$SYSTEMD_USER_DIR/"
  chmod 644 "$SYSTEMD_USER_DIR/$(basename "$service_file")"

  # Reload systemd
  systemctl --user daemon-reload

  # Enable service
  systemctl --user enable "$service_name"

  # Record installation
  record_audit_event "service_installed" "$service_name" "success" "systemd_unit_enabled"
  log "INFO" "✅ Installed and enabled service: $service_name"

  return 0
}

start_service() {
  local service_name="$1"

  if ! systemctl --user is-enabled "$service_name" &>/dev/null; then
    log "WARN" "Service not enabled: $service_name. Installing first..."
    install_service "$service_name" || return 1
  fi

  systemctl --user start "$service_name"
  record_audit_event "service_started" "$service_name" "success" ""
  log "INFO" "✅ Started service: $service_name"
}

stop_service() {
  local service_name="$1"

  systemctl --user stop "$service_name" || true
  record_audit_event "service_stopped" "$service_name" "success" ""
  log "INFO" "Stopped service: $service_name"
}

restart_service() {
  local service_name="$1"

  systemctl --user restart "$service_name"
  record_audit_event "service_restarted" "$service_name" "success" ""
  log "INFO" "✅ Restarted service: $service_name"
}

status_service() {
  local service_name="$1"

  local status=$(systemctl --user is-active "$service_name" 2>/dev/null || echo "inactive")
  local enabled=$(systemctl --user is-enabled "$service_name" 2>/dev/null || echo "disabled")
  local restart_count=$(systemctl --user show -p NRestarts "$service_name" | cut -d= -f2 || echo "0")

  echo "Service: $service_name"
  echo "  Status: $status"
  echo "  Enabled: $enabled"
  echo "  Restart Count: $restart_count"

  # Get active duration
  if [[ "$status" == "active" ]]; then
    local active_since=$(systemctl --user show -p ActiveEnterTimestamp "$service_name" | cut -d= -f2-)
    echo "  Active Since: $active_since"
  fi
}

# =============================================================================
# HEALTH CHECKS & MONITORING
# =============================================================================

health_check_all_services() {
  log "INFO" "Running health check on all services..."

  local all_healthy=true
  local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  local health_report="{\"timestamp\": \"$timestamp\", \"services\": {}}"

  for service_name in "${SERVICES[@]}"; do
    local status=$(systemctl --user is-active "$service_name" 2>/dev/null || echo "inactive")
    local enabled=$(systemctl --user is-enabled "$service_name" 2>/dev/null || echo "disabled")

    if [[ "$status" != "active" ]]; then
      all_healthy=false
      log "WARN" "❌ Service unhealthy: $service_name (status: $status)"
      health_report=$(echo "$health_report" | jq ".services.\"$service_name\" = {status: \"$status\", enabled: \"$enabled\", healthy: false}")
    else
      log "INFO" "✅ Service healthy: $service_name"
      health_report=$(echo "$health_report" | jq ".services.\"$service_name\" = {status: \"$status\", enabled: \"$enabled\", healthy: true}")
    fi
  done

  # Update state file
  state_file_data=$(cat "$state_file" | jq ".last_health_check = \"$timestamp\" | .service_status = $health_report")
  echo "$state_file_data" > "$state_file"

  if [[ "$all_healthy" == true ]]; then
    log "INFO" "✅ All services healthy"
    return 0
  else
    log "WARN" "⚠️  Some services unhealthy - remediation required"
    return 1
  fi
}

enable_user_lingering() {
  # Enable lingering so services run even when user is not logged in
  loginctl enable-linger "$USER" 2>/dev/null || {
    log "WARN" "Could not enable user lingering (may require sudo)"
  }
  log "INFO" "User lingering configured for 24/7 monitoring"
}

# =============================================================================
# MONITORING & LOGS
# =============================================================================

view_service_logs() {
  local service_name="$1"
  local lines="${2:-50}"

  log "INFO" "Fetching last $lines log lines for $service_name..."
  journalctl --user -u "$service_name" -n "$lines" --no-pager
}

watch_service_logs() {
  local service_name="$1"

  log "INFO" "Watching live logs for $service_name (Ctrl+C to exit)..."
  journalctl --user -u "$service_name" -f --no-pager
}

get_service_statistics() {
  local service_name="$1"

  echo "📊 Service Statistics: $service_name"
  echo "─────────────────────────────────────"

  # Uptime
  local active_since=$(systemctl --user show -p ActiveEnterTimestamp "$service_name" | cut -d= -f2-)
  echo "Active Since: $active_since"

  # Restart count
  local restart_count=$(systemctl --user show -p NRestarts "$service_name" | cut -d= -f2 || echo "0")
  echo "Total Restarts: $restart_count"

  # Memory usage
  local memory=$(systemctl --user show -p MemoryCurrent "$service_name" | cut -d= -f2)
  if [[ -n "$memory" && "$memory" != "0" ]]; then
    local memory_mb=$((memory / 1024 / 1024))
    echo "Memory Usage: ${memory_mb}MB"
  fi

  # CPU usage (via systemd-cgtop if available)
  echo "CPU Usage: (run 'systemd-cgtop' for real-time view)"
}

# =============================================================================
# COMMANDS
# =============================================================================

cmd_install() {
  log "INFO" "Installing all ElevatedIQ systemd services..."
  init_state_file
  enable_user_lingering

  for service_name in "${SERVICES[@]}"; do
    install_service "$service_name" || {
      log "ERROR" "Failed to install $service_name"
      return 1
    }
  done

  log "INFO" "✅ All services installed successfully"
  sleep 2
  cmd_status
}

cmd_start() {
  log "INFO" "Starting all ElevatedIQ systemd services..."

  for service_name in "${SERVICES[@]}"; do
    start_service "$service_name" || {
      log "ERROR" "Failed to start $service_name"
      return 1
    }
  done

  sleep 2
  log "INFO" "✅ All services started"
}

cmd_stop() {
  log "INFO" "Stopping all ElevatedIQ systemd services..."

  for service_name in "${SERVICES[@]}"; do
    stop_service "$service_name"
  done

  log "INFO" "All services stopped"
}

cmd_restart() {
  log "INFO" "Restarting all ElevatedIQ systemd services..."

  for service_name in "${SERVICES[@]}"; do
    restart_service "$service_name"
  done

  sleep 2
  cmd_status
}

cmd_status() {
  echo ""
  echo "╔─────────────────────────────────────────╗"
  echo "║  🔧 EIQ Systemd Service Status Report   ║"
  echo "╚─────────────────────────────────────────╝"
  echo ""

  for service_name in "${SERVICES[@]}"; do
    status_service "$service_name"
    echo ""
  done
}

cmd_health() {
  echo ""
  echo "╔──────────────────────────────────────────┐"
  echo "║  🏥 Service Health Check                 │"
  echo "╚──────────────────────────────────────────┘"
  echo ""

  health_check_all_services || true

  echo ""
  echo "Detailed report saved to: $state_file"
}

cmd_logs() {
  local service="$1"
  local lines="${2:-50}"

  if [[ -z "$service" ]]; then
    echo "Usage: $0 logs <service> [lines]"
    echo "Services: ${!SERVICES[@]}"
    return 1
  fi

  view_service_logs "$service" "$lines"
}

cmd_watch() {
  local service="$1"

  if [[ -z "$service" ]]; then
    echo "Usage: $0 watch <service>"
    echo "Services: ${!SERVICES[@]}"
    return 1
  fi

  watch_service_logs "$service"
}

cmd_stats() {
  local service="$1"

  if [[ -z "$service" ]]; then
    echo "Usage: $0 stats <service>"
    echo "Services: ${!SERVICES[@]}"
    return 1
  fi

  get_service_statistics "$service"
}

cmd_uninstall() {
  log "WARN" "Uninstalling ElevatedIQ systemd services..."

  for service_name in "${SERVICES[@]}"; do
    systemctl --user stop "$service_name" || true
    systemctl --user disable "$service_name" || true
    rm -f "$SYSTEMD_USER_DIR/$service_name"
    record_audit_event "service_uninstalled" "$service_name" "success" ""
    log "INFO" "Uninstalled service: $service_name"
  done

  systemctl --user daemon-reload
  log "INFO" "All services uninstalled"
}

# =============================================================================
# MAIN
# =============================================================================

main() {
  local command="${1:-status}"

  mkdir -p "$(dirname "$log_file")"
  mkdir -p "$(dirname "$state_file")"

  case "$command" in
    install)
      cmd_install
      ;;
    start)
      cmd_start
      ;;
    stop)
      cmd_stop
      ;;
    restart)
      cmd_restart
      ;;
    status)
      cmd_status
      ;;
    health)
      cmd_health
      ;;
    logs)
      cmd_logs "${2:-}" "${3:-50}"
      ;;
    watch)
      cmd_watch "${2:-}"
      ;;
    stats)
      cmd_stats "${2:-}"
      ;;
    uninstall)
      cmd_uninstall
      ;;
    *)
      cat <<EOF
🔧 ElevatedIQ Systemd Service Manager v${VERSION}

Usage: $0 <command> [args]

Commands:
  install              Install and enable all services
  start                Start all services
  stop                 Stop all services
  restart              Restart all services
  status               Show service status (default)
  health               Run health check on all services
  logs <service>       View service logs (default: 50 lines)
  watch <service>      Watch live service logs
  stats <service>      Show service statistics
  uninstall            Uninstall all services

Examples:
  $0 install                              # First-time setup
  $0 watch devenv-monitor                 # Watch live logs
  $0 logs governance-monitor 100          # View last 100 lines
  $0 health                               # System health check

Compliance: NIST CM-3 (Change Control), AU-2 (Audit Event Generation)
EOF
      return 1
      ;;
  esac
}

main "$@"
