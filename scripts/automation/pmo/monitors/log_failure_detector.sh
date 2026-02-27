#!/usr/bin/env bash
# Log Failure Detector & Auto-Issue Creator
# Monitors workspace logs for errors, failures, and security issues
# Automatically creates GitHub issues with proper PMO standards
# Usage: ./log_failure_detector.sh [--watch] [--dry-run]

set -euo pipefail

REPO_OWNER="kushin77"
REPO_NAME="ElevatedIQ-Mono-Repo"
WORKSPACE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOG_DIR="${WORKSPACE_ROOT}/logs"
MONITORING_DIR="${WORKSPACE_ROOT}/logs/monitoring"
LOG_SOURCES=(
    "${LOG_DIR}"
    "${MONITORING_DIR}"
    "/var/log/syslog"
    "/home/akushnir/.vscode-server/data/logs"
)
CACHE_DIR="${WORKSPACE_ROOT}/.pmo-cache"
PROCESSED_ISSUES="${CACHE_DIR}/processed_log_hashes.txt"
WATCH_MODE=false
DRY_RUN="${MONITOR_DRY_RUN:-true}"  # safe default: must be explicitly set to false to create issues

# ── Monitor guards (circuit breaker, sentinel, safe_log) ──────────────────────
MONITOR_SCRIPT_ID="log-failure-detector"
MONITOR_CB_LIMIT="${MONITOR_CB_LIMIT:-5}"
MONITOR_CB_WINDOW="${MONITOR_CB_WINDOW:-300}"
MONITOR_LOG_PREFIX="[LFD]"
LIB_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)/scripts/lib"
# shellcheck source=scripts/lib/monitor_guards.sh
if [[ -f "${LIB_PATH}/monitor_guards.sh" ]]; then
  source "${LIB_PATH}/monitor_guards.sh"
else
  # Fallback no-ops when lib is unavailable
  circuit_breaker_check() { return 0; }
  circuit_breaker_record() { :; }
fi

# Ensure cache directory exists
mkdir -p "${CACHE_DIR}"
[ -f "${PROCESSED_ISSUES}" ] || touch "${PROCESSED_ISSUES}"

# Colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# Pattern definitions for automatic issue detection
declare -A FAILURE_PATTERNS=(
    ["panic"]="severity:critical|type:crash|Cause: Unhandled panic in runtime"
    ["segfault"]="severity:critical|type:crash|Cause: Memory safety violation (segmentation fault)"
    ["terraform_error"]="severity:high|type:iac|Cause: Terraform plan or apply failed"
    ["security_vulnerability"]="severity:critical|type:security|Cause: Security vulnerability detected"
    ["auth_failure"]="severity:high|type:security|Cause: Authentication or authorization failure"
    ["db_connection_error"]="severity:high|type:infra|Cause: Database connection failure"
    ["timeout"]="severity:medium|type:reliability|Cause: Operation timeout exceeded"
    ["out_of_memory"]="severity:high|type:performance|Cause: Out of memory (OOM) error"
    ["permission_denied"]="severity:medium|type:security|Cause: Permission denied or access control violation"
    ["network_error"]="severity:medium|type:infra|Cause: Network connectivity or DNS resolution error"
    ["workspace_reload"]="severity:high|type:stability|Cause: VS Code window reload or extension host crash detected"
    ["inotify_limit"]="severity:high|type:stability|Cause: System inotify limit reached (Watcher failure)"
    ["indexer_bloat"]="severity:p0|type:performance|Cause: Massive folder detected (Indexer crash risk)"
    ["unauthorized_git_access"]="severity:critical|type:security|Cause: Potential unauthorized git activity detected"
    ["cloud_cost_spike"]="severity:high|type:finops|Cause: Cloud cost spike detected"
    # [DISABLED] Spam patterns - too many false positives
    # ["generic_error"]="severity:medium|type:bug|Cause: Generic ERROR log detected in system"
    # ["global_catchall"]="severity:high|type:monitoring|Cause: Global catch-all error logged in unified hub"
    ["high_resource_usage"]="severity:high|type:performance|Cause: System resource threshold reached"
)

# Search patterns (grep -E compatible)
declare -A SEARCH_PATTERNS=(
    ["panic"]="panic:|fatal error:|stack trace:"
    ["segfault"]="segmentation fault|SIGSEGV"
    ["terraform_error"]="Error: [^ ]* resource|Terraform failed"
    ["security_vulnerability"]="vulnerability:|CVE-|critical security"
    ["auth_failure"]="Invalid token|Authentication failed|Unauthorized access"
    ["db_connection_error"]="Connection refused|DB connection error|failed to connect to host"
    ["timeout"]="context deadline exceeded|request timeout|ETIMEDOUT"
    ["out_of_memory"]="OOM|out of memory"
    ["permission_denied"]="Permission denied|EACCES"
    ["network_error"]="DNS resolution failed|no such host|network is unreachable"
    ["workspace_reload"]="Extension host terminated unexpectedly|window reloaded"
    ["unauthorized_git_access"]="git_events.jsonl.*unauthorized|unexpected git author"
    # [DISABLED] Spam patterns - use specific error patterns instead
    # ["generic_error"]="ERROR|CRITICAL"
    # ["global_catchall"]="[ERROR]|[FATAL]"
    ["high_resource_usage"]="\"disk_pct\":[9][0-9]|\"cpu_load\":[9][0-9]|\"mem_mb\":[max]"
)

# Patterns to ignore to prevent false positives (e.g. Terraform configs)
declare -a EXCLUSION_PATTERNS=(
    "timeout_seconds"
    "auth_failures"
    "auth_failure_rate"
    "metric.type"
    "resource.type"
    "variable "
    "output "
    "terraform will perform the following actions"
    "plan:"
    "apply complete"
    "refreshing state"
    "Creating GitHub issue"
    "Issue already exists"
    "Found Global Catch-all"
    "Found generic_error"
    "GitHub issue created"
    "Detected issue:"
    "Classification:"
    "Duplicate error"
    "Duplicate issue"
    "portal-monitored"
    "Portal Debug Monitor"
    "Auto-Detected Error"
    "APMA failed to execute"
    "generic_error"
    "global_catchall"
    "^\s*[+-~]"            # Terraform plan diff lines ( +, -, ~ )
    "^\s*#"                # Commented lines / hashes
    "^\{"                 # JSON start (metrics/config blobs)
    "aws_access_key_id"     # AWS credential placeholders
    "aws_secret_access_key"
    "secret\s*key"
    "base64,?\s*data"      # inline base64 blobs
    "BEGIN RSA PRIVATE KEY"
)

# File path patterns to skip entirely (e.g., Terraform state/plan outputs)
declare -a FILE_EXCLUSION_PATHS=(
    "/terraform/"
    ".*\.tfvars"
    ".*\.tf"
    "plan\.out"
    "state\\\.*tfstate"
    "failure_detector\.log"
    "session_tracker\.sh"
    # Portal debug monitor logs -- these are internal PMO meta-logs, not application errors.
    # Scanning them causes a feedback loop: monitor logs its own 'issue created' lines,
    # which get detected as new errors, creating infinite duplicate issues.
    "/logs/portal/"
    "portal/monitor"
    "portal/rag"
    "monitor_start_"
    "rag_start_"
)

# Generate unique hash for log entry to avoid duplicates
generate_hash() {
    # Include file path and line number in the hash when provided (args: log_entry|file|line)
    local log_entry="$1"
    local file_path="${2:-}"
    local line_no="${3:-}"
    # Normalize whitespace, remove variable values and truncate long blobs to reduce duplicate noise
    local normalized
    normalized=$(echo -n "${log_entry}" | tr -s '[:space:]' ' ' | sed -E 's/([A-Za-z0-9_\-]+)=([A-Za-z0-9_\-\/\.=]+) /\1=<redacted> /g' | sed -E 's/[A-Za-z0-9+/]{40,}/<blob>/g')
    echo -n "${file_path}:${line_no}:${normalized}" | sha256sum | awk '{print $1}'
}

# Check if issue has already been created for this log entry
is_already_processed() {
    local hash="$1"
    grep -q "^${hash}$" "${PROCESSED_ISSUES}" 2>/dev/null || return 1
}

# Mark issue as processed
mark_processed() {
    local hash="$1"
    echo "${hash}" >> "${PROCESSED_ISSUES}"
}

# Create GitHub issue for detected failure
create_failure_issue() {
    local pattern="$1"
    local log_entry="$2"
    local file_path="$3"
    local line_number="$4"

    local hash=$(generate_hash "${log_entry}" "${file_path}" "${line_number}")

    if is_already_processed "${hash}"; then
        log_info "Issue already exists for this failure (hash: ${hash:0:8})"
        return 0
    fi

    # Parse pattern metadata
    local severity=$(echo "${FAILURE_PATTERNS[$pattern]}" | cut -d'|' -f1 | cut -d':' -f2)
    local type=$(echo "${FAILURE_PATTERNS[$pattern]}" | cut -d'|' -f2 | cut -d':' -f2)
    local cause=$(echo "${FAILURE_PATTERNS[$pattern]}" | cut -d'|' -f3 | cut -d':' -f2-)

    # Build priority label
    local priority_label="priority-p2"
    [ "${severity}" = "critical" ] && priority_label="priority-p0"
    [ "${severity}" = "high" ] && priority_label="priority-p1"

    # Map internal type to existing repository labels
    local label_type="bug"
    case "${type}" in
        security) label_type="security" ;;
        infra|iac) label_type="infrastructure" ;;
        reliability|performance) label_type="resilience" ;;
        stability) label_type="resilience" ;;
        crash) label_type="bug" ;;
        *) label_type="bug" ;;
    esac

    # Construct GitHub issue body
    local issue_body="## 🚨 Automated Failure Detection

**Severity**: ${severity}
**Type**: ${type}
**Detected At**: $(date -u +%Y-%m-%dT%H:%M:%SZ)

### Cause
${cause}

### Failure Details
\`\`\`
${log_entry}
\`\`\`

### Location
- **File**: \`${file_path}\`
- **Line**: ${line_number}
- **Hash**: \`${hash:0:16}\`

### Reproduction
1. Review the log entry above
2. Navigate to the file location
3. Investigate the error condition

### Next Steps
- [ ] Investigate root cause
- [ ] Create fix branch (e.g., \`fix/${type}-${hash:0:8}\`)
- [ ] Add regression test
- [ ] Update monitoring/alerting if needed

---
_Auto-generated by \`log_failure_detector.sh\` | [Session Log](#)_"

    # include short file context in title when available
    local short_file=""
    [ -n "${file_path}" ] && short_file=" (${file_path##*/}:${line_number})"
    local title="[${severity^^}] ${type}${short_file}: ${log_entry:0:60}..."

    if [ "${DRY_RUN}" = "true" ]; then
        log_warn "[DRY-RUN] Would create issue:"
        log_warn "Title: ${title}"
        log_warn "Labels: ${priority_label}, ${label_type}, type:bug"
        return 0
    fi

    # Trigger APMA (Automated Post-Mortem Agent)
    log_info "Triggering APMA for context capture..."
    local metadata_json="{\"pattern\": \"$pattern\", \"log_entry\": \"$(echo "$log_entry" | sed 's/\"/\\\"/g')\", \"file\": \"$file_path\", \"line\": \"$line_number\"}"
    export PYTHONPATH="${PYTHONPATH:-}:${WORKSPACE_ROOT}"
    python3 -m libs.pmo_core.remediation.apma "$pattern" "$metadata_json" > /tmp/apma_output.txt 2>&1 || log_warn "APMA failed to execute"

    local apma_report=""
    if [ -f /tmp/apma_output.txt ]; then
        apma_report=$(grep "Post-Mortem:" /tmp/apma_output.txt | cut -d':' -f2- | xargs)
        [ -n "${apma_report}" ] && issue_body="${issue_body}\n\n### 🧠 AI Post-Mortem Agent\n- **Context Snapshot**: \`${apma_report}\`"
    fi

    log_info "Creating GitHub issue for ${pattern}..."

    # Circuit breaker: halt runaway issue storms before calling UIE
    circuit_breaker_check || { log_warn "[CIRCUIT-BREAKER] Issue creation suppressed (rate limit hit)"; return 0; }

    # 10X ENHANCEMENT: Use Unified Issue Engine (UIE) for mandatory standards
    if bash "${WORKSPACE_ROOT}/scripts/pmo/uie.sh" \
        --title "${title}" \
        --body "${issue_body}" \
        --labels "${priority_label},${label_type},type:bug"; then

        circuit_breaker_record
        log_info "✅ Issue created successfully via UIE"
        mark_processed "${hash}"
        return 0
    else
        log_error "Failed to create issue for pattern: ${pattern}"
        return 1
    fi
}

# Scan log files for failures
scan_logs() {
    log_info "Scanning unified log sources [NIST-AU-6]..."

    local issue_count=0
    set +e

    for current_source in "${LOG_SOURCES[@]}"; do
        if [ ! -d "${current_source}" ] && [ ! -f "${current_source}" ]; then
            continue
        fi

        log_info "Scanning source: ${current_source}"

        # Find files modify in the last 60 minutes to reduce scan overhead in high-frequency mode
        local find_cmd="find \"${current_source}\" \( -name \"*.log\" -o -name \"*.err\" -o -name \"*.json\" -o -name \"*.jsonl\" \) -mmin -60"

        while IFS= read -r log_file; do
            # ... existing logic ...
            local line_num=0
            while IFS= read -r line; do
                ((line_num++))

                local is_excluded=false
                for p in "${FILE_EXCLUSION_PATHS[@]}"; do
                    if echo "${log_file}" | grep -Ei "${p}" >/dev/null 2>&1; then
                        is_excluded=true
                        break
                    fi
                done
                [ "${is_excluded}" = "true" ] && continue

                for excl in "${EXCLUSION_PATTERNS[@]}"; do
                    if echo "${line}" | grep -Eiq "${excl}" >/dev/null 2>&1; then
                        is_excluded=true
                        break
                    fi
                done
                [ "${is_excluded}" = "true" ] && continue

                # Advanced Pattern Matching: Check against SEARCH_PATTERNS
                for pattern in "${!SEARCH_PATTERNS[@]}"; do
                    if echo "${line}" | grep -Eiq "${SEARCH_PATTERNS[$pattern]}"; then
                        log_warn "Found ${pattern} [10X] at ${log_file}:${line_num}"
                        if create_failure_issue "${pattern}" "${line}" "${log_file}" "${line_num}"; then
                            ((issue_count++))
                        fi
                        break # Only create one issue per line
                    fi
                done
            done < "${log_file}"
        done < <(eval "${find_cmd}")
    done
    set -e

    log_info "Scan complete. ${issue_count} new issues created."
    return 0
}

# Watch mode: continuous monitoring
watch_mode() {
    log_info "Starting log failure detector in WATCH mode..."
    log_info "Monitoring: ${LOG_DIR}"
    log_info "Check interval: 60s | Press Ctrl+C to stop"

    while true; do
        scan_logs
        sleep 60
    done
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --watch)
            WATCH_MODE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help|-h)
            echo "Usage: ./log_failure_detector.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --watch      Continuous monitoring mode (runs every 60s)"
            echo "  --dry-run    Show what would be created without actually creating issues"
            echo "  --help       Show this help message"
            echo ""
            echo "Examples:"
            echo "  ./log_failure_detector.sh                 # Single scan"
            echo "  ./log_failure_detector.sh --watch         # Continuous monitoring"
            echo "  ./log_failure_detector.sh --dry-run       # Preview what would be detected"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Main execution
if [ "${WATCH_MODE}" = "true" ]; then
    watch_mode
else
    scan_logs
fi
