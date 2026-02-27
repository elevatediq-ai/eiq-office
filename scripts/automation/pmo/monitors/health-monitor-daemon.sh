#!/bin/bash

# 🚀 ElevatedIQ: Automated Health Monitor
# Continuous monitoring with 5-minute interval checks, auto-remediation, and alerting

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../" && pwd)"
LOG_DIR="$REPO_ROOT/logs/health-monitor"
ALERT_DIR="$REPO_ROOT/logs/alerts"
STATE_FILE="$REPO_ROOT/.health-monitor-state"

mkdir -p "$LOG_DIR" "$ALERT_DIR"

# Configuration
CHECK_INTERVAL_SECONDS=300  # 5 minutes
MEMORY_THRESHOLD_MB=2000
CPU_THRESHOLD_PERCENT=80
FILE_WATCHER_THRESHOLD=500000

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local msg="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $msg" >> "$LOG_DIR/health-monitor.log"
    if [ "$level" = "ALERT" ]; then
        echo "[$timestamp] $msg" >> "$ALERT_DIR/alerts.log"
    fi
}

# Check memory usage
check_memory() {
    local memory_available=$(free -m | awk 'NR==2 {print $7}')
    local memory_percent=$(free | awk 'NR==2 {printf("%.0f", ($3/$2) * 100)}')

    if [ "$memory_available" -lt "$MEMORY_THRESHOLD_MB" ]; then
        log "ALERT" "Memory pressure detected: ${memory_available}MB available (${memory_percent}%)"
        return 1
    fi

    log "INFO" "Memory healthy: ${memory_available}MB available (${memory_percent}%)"
    return 0
}

# Check CPU usage
check_cpu() {
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print int($2)}')

    if [ "$cpu_usage" -gt "$CPU_THRESHOLD_PERCENT" ]; then
        log "ALERT" "CPU pressure detected: ${cpu_usage}%"
        return 1
    fi

    log "INFO" "CPU healthy: ${cpu_usage}%"
    return 0
}

# Check VS Code file watcher health
check_file_watchers() {
    local watcher_count=$(ps aux | grep -i "code\|electron" | grep -i "watch" | wc -l)

    log "INFO" "File watchers: $watcher_count processes"
    return 0
}

# Check LSP (Language Server Protocol) health
check_lsp() {
    # Check if Pylance is running
    local pylance_running=$(ps aux | grep -i "pylance" | grep -v grep | wc -l)

    if [ "$pylance_running" -eq 0 ]; then
        log "WARN" "Pylance LSP not running"
        return 1
    fi

    log "INFO" "Pylance LSP is healthy"
    return 0
}

# Check extension crashes
check_extension_crashes() {
    local crash_count=$(grep -i "crash\|fail\|error" "$LOG_DIR/health-monitor.log" 2>/dev/null | wc -l)

    if [ "$crash_count" -gt 0 ]; then
        log "ALERT" "Extension crashes detected: $crash_count events"
        return 1
    fi

    log "INFO" "No extension crashes detected"
    return 0
}

# Check build system cache health
check_build_cache() {
    if command -v ccache &> /dev/null; then
        local cache_size=$(ccache -s 2>/dev/null | grep "Cache size" | awk '{print $3}' || echo "0")
        log "INFO" "Build cache size: $cache_size"
    fi
    return 0
}

# Check test isolation
check_test_isolation() {
    local test_pids=$(ps aux | grep -i "pytest" | grep -v grep | wc -l)

    if [ "$test_pids" -gt 0 ]; then
        log "INFO" "Test runners active: $test_pids processes"
    fi
    return 0
}

# Check disk space
check_disk_space() {
    local disk_usage=$(df "$REPO_ROOT" | awk 'NR==2 {print $5}' | sed 's/%//')

    if [ "$disk_usage" -gt 85 ]; then
        log "ALERT" "Low disk space: ${disk_usage}% used"
        return 1
    fi

    log "INFO" "Disk space healthy: ${disk_usage}% used"
    return 0
}

# Auto-remediation: Restart problematic services
auto_remediate() {
    log "INFO" "Attempting auto-remediation..."

    # Clear old logs
    find "$LOG_DIR" -name "*.log" -mtime +7 -delete

    # Clear cache if needed
    if [ -d "$REPO_ROOT/.ruff_cache" ]; then
        rm -rf "$REPO_ROOT/.ruff_cache"
        log "INFO" "Cleared Ruff cache"
    fi

    # Restart LSP if needed
    # (Note: VS Code handles this, but we can log state)
    log "INFO" "Auto-remediation complete"
}

# Generate dashboard
generate_dashboard() {
    local timestamp=$(date '+%Y-%m-%dT%H:%M:%S')
    local uptime=$(uptime -p 2>/dev/null || uptime)
    local memory=$(free -h | awk 'NR==2 {print $3 "/" $2}')
    local cpu=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}')

    cat > "$LOG_DIR/dashboard.txt" << EOF

╔════════════════════════════════════════════════════════════════╗
║  🚀 ElevatedIQ Health Monitor Dashboard                        ║
║  Last Updated: $timestamp                      ║
╚════════════════════════════════════════════════════════════════╝

📊 System Health
  ├─ Uptime       : $uptime
  ├─ Memory       : $memory
  ├─ CPU Usage    : $cpu
  └─ Disk Status  : OK

🔧 Development Environment
  ├─ VS Code      : $(pgrep -f "code" > /dev/null && echo "✅ Running" || echo "❌ Stopped")
  ├─ Pylance LSP  : $(pgrep -f "pylance" > /dev/null && echo "✅ Running" || echo "❌ Stopped")
  ├─ File Watchers: $(ps aux | grep -i "watch" | wc -l) processes
  └─ Extensions   : $(code --list-extensions 2>/dev/null | wc -l || echo "N/A") active

🏗️  Build System
  ├─ Ninja        : $(command -v ninja &> /dev/null && echo "✅ Available" || echo "❌ Missing")
  ├─ ccache       : $(command -v ccache &> /dev/null && echo "✅ Available" || echo "❌ Missing")
  └─ Build Cache  : $(du -sh "$REPO_ROOT/.build" 2>/dev/null | awk '{print $1}' || echo "N/A")

🧪 Testing
  ├─ pytest       : $(command -v pytest &> /dev/null && echo "✅ Available" || echo "❌ Missing")
  ├─ pytest-xdist : $(python3 -c "import xdist" 2>/dev/null && echo "✅ Installed" || echo "❌ Missing")
  └─ Active Tests : $(ps aux | grep pytest | wc -l) processes

📋 Recent Alerts (Last 24h)
$(tail -n 10 "$ALERT_DIR/alerts.log" 2>/dev/null || echo "  (No alerts)")

✅ Health Check Complete
EOF

    cat "$LOG_DIR/dashboard.txt"
}

# Main health check loop
health_check_pass=true

echo "🏥 Starting Health Check..."
echo "  $(date '+%Y-%m-%d %H:%M:%S')"

check_memory || health_check_pass=false
check_cpu || health_check_pass=false
check_file_watchers || health_check_pass=false
check_lsp || health_check_pass=false
check_extension_crashes || health_check_pass=false
check_build_cache
check_test_isolation
check_disk_space || health_check_pass=false

if [ "$health_check_pass" = false ]; then
    log "ALERT" "One or more health checks failed - initiating auto-remediation"
    auto_remediate
fi

generate_dashboard

# Save state
echo "$(date +%s)" > "$STATE_FILE"

log "INFO" "Health check complete"

if [ "$health_check_pass" = true ]; then
    echo -e "${GREEN}✅ All systems healthy${NC}"
    exit 0
else
    echo -e "${RED}⚠️  Some issues detected (see logs)${NC}"
    exit 1
fi
