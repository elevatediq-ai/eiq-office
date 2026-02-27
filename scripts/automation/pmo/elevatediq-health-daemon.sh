#!/bin/bash
##############################################################################
# ElevatedIQ Health Daemon - Continuous Service Recovery
# Purpose: Monitor critical ports and auto-restart failed services (< 5 seconds)
# NIST Controls: CP-10 (Information System Recovery), SI-4 (System Monitoring)
##############################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Configuration
# RCA-FIX 2026-02-26: Changed from 5s to 60s.
# 5s spawned top/free/df/nc 12x/min = 50+ subprocesses/min on workstation .31,
# contributing to CPU starvation. 60s is sufficient for service health checks.
CHECK_INTERVAL=60         # Check every 60 seconds — was 5, see RCA: docs/ops/RCA_VSCODE_RECONNECT_2026-02-26.md
LOG_FILE="/var/log/elevatediq/health-daemon.log"
METRICS_FILE="/var/lib/elevatediq/health-metrics.json"
MAX_RESTART_STORMS=3      # Max restarts per service in 60s window

# Service→Port mapping
declare -A SERVICES=(
    ["pgbouncer.service"]="127.0.0.1:6432"
    ["elevatediq-web.service"]="127.0.0.1:4000"
)

declare -A RESTART_TIMES  # Track recent restarts
declare -A LAST_CHECK     # Track last check time

# Logging function
log() {
    echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] $*" | tee -a "$LOG_FILE"
}

# Metrics function
record_metric() {
    local event=$1
    local service=$2
    local status=$3

    jq -n \
        --arg ts "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
        --arg event "$event" \
        --arg service "$service" \
        --arg status "$status" \
        '{timestamp: $ts, event: $event, service: $service, status: $status}' >> "$METRICS_FILE" 2>/dev/null || true
}

# Port check function
check_port() {
    local host_port=$1
    local IFS=':'
    read -r host port <<< "$host_port"

    if timeout 2 bash -c "echo >/dev/tcp/$host/$port" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Service restart function
restart_service() {
    local service=$1
    local current_time=$(date +%s)

    # Check for restart storms (prevent infinite restart loops)
    if [[ -n "${RESTART_TIMES[$service]}" ]]; then
        local last_restart=${RESTART_TIMES[$service]}
        local time_diff=$((current_time - last_restart))

        # If restarted more than MAX_RESTART_STORMS times in 60s, skip
        if [[ $time_diff -lt 60 ]]; then
            log "⚠ WARNING: Restart storm detected for $service (last restart ${time_diff}s ago)"
            record_metric "restart_storm" "$service" "storm_detected"
            return 1
        fi
    fi

    log "🔄 RESTARTING: $service"

    # Perform restart via systemctl
    if sudo systemctl restart "$service" 2>/dev/null; then
        RESTART_TIMES[$service]=$current_time
        log "✅ RECOVERED: $service restarted successfully"
        record_metric "service_recovery" "$service" "restarted"

        # Wait for service to stabilize
        sleep 2
        return 0
    else
        log "❌ ERROR: Failed to restart $service"
        record_metric "restart_failure" "$service" "failed"
        return 1
    fi
}

# Resource monitoring
check_resources() {
    # CPU usage check
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print int($2)}')
    if [[ $cpu_usage -gt 200 ]]; then
        log "⚠ HIGH CPU: ${cpu_usage}% - might need service restart"
        # Optional: trigger graceful service restart
    fi

    # Memory check
    local mem_usage=$(free | awk '/^Mem:/ {printf "%.0f", ($3/$2) * 100}')
    if [[ $mem_usage -gt 90 ]]; then
        log "⚠ HIGH MEMORY: ${mem_usage}% - consider cleanup"
    fi

    # Disk usage check
    local disk_usage=$(df / | awk 'NR==2 {print int($5)}')
    if [[ $disk_usage -gt 90 ]]; then
        log "⚠ HIGH DISK USAGE: ${disk_usage}%"
        # Auto-cleanup strategy
        docker system prune -f --filter "until=24h" 2>/dev/null || true
        find "$LOG_FILE" -mtime +7 -delete 2>/dev/null || true
        record_metric "disk_cleanup" "system" "cleaned"
    fi
}

# Main health check loop
health_check_loop() {
    log "🚀 ElevatedIQ Health Daemon Starting"
    log "   Check interval: ${CHECK_INTERVAL}s"
    log "   Services monitored: ${#SERVICES[@]}"
    log "   Restart storm threshold: ${MAX_RESTART_STORMS} in 60s"

    # Initialize metrics file
    mkdir -p "$(dirname "$METRICS_FILE")" "$(dirname "$LOG_FILE")"
    touch "$METRICS_FILE"
    record_metric "daemon_start" "health-daemon" "started"

    while true; do
        # Check each service
        for service in "${!SERVICES[@]}"; do
            port_spec="${SERVICES[$service]}"

            if ! check_port "$port_spec"; then
                log "❌ SERVICE DOWN: $service (port $port_spec unresponsive)"
                record_metric "port_failure" "$service" "down"

                # Attempt recovery
                if restart_service "$service"; then
                    # Verify recovery
                    sleep 1
                    if check_port "$port_spec"; then
                        log "✅ VERIFIED: $service recovered and listening"
                        record_metric "recovery_verified" "$service" "up"
                    else
                        log "⚠ CAUTION: $service restarted but still not responding"
                        record_metric "recovery_timeout" "$service" "timeout"
                    fi
                fi
            else
                LAST_CHECK[$service]=$(date +%s)
            fi
        done

        # Check system resources
        check_resources

        # Sleep before next check
        sleep "$CHECK_INTERVAL"
    done
}

# Trap signals for graceful shutdown
cleanup() {
    log "🛑 Health Daemon shutting down..."
    record_metric "daemon_stop" "health-daemon" "stopped"
    exit 0
}

trap cleanup SIGTERM SIGINT

# Start daemon
health_check_loop
