#!/bin/bash
#
# Portal Integration Task Coordinator
# Manages parallel execution of 6 integration tasks (Feb 24-28)
#
# Usage: ./pmo/integration_coordinator.sh [status|start|update|report]

set -euo pipefail

REPO="kushin77/ElevatedIQ-Mono-Repo"
TASKS=(5439 5440 5441 5442 5443 5444)
COORDINATOR_LOG="docs/management/INTEGRATION_COORDINATOR_LOG_20260224.md"

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo_info() { echo -e "${BLUE}ℹ️  $*${NC}"; }
echo_success() { echo -e "${GREEN}✅ $*${NC}"; }
echo_warning() { echo -e "${YELLOW}⚠️  $*${NC}"; }
echo_error() { echo -e "${RED}❌ $*${NC}"; }

# Initialize coordinator log
init_log() {
  cat > "$COORDINATOR_LOG" <<'EOF'
## Portal Integration Task Coordinator

**Session Start:** 2026-02-24 09:00 UTC
**Coordination Mode:** Parallel (6 tasks)
**Target Completion:** 2026-02-28 17:00 UTC

### Task Execution Matrix

| Task # | Title | Team | Duration | Status | Commits |
|--------|-------|------|----------|--------|---------|
| #5439 | Auth Integration | Frontend | 1 day | ⏳ Queued | - |
| #5440 | RBAC Integration | Frontend | 1 day | ⏳ Queued | - |
| #5441 | Operations Integration | Backend | 1.5 days | ⏳ Queued | - |
| #5442 | Metrics Integration | Backend | 1.5 days | ⏳ Queued | - |
| #5443 | Load Testing | QA/DevOps | 2 days | ⏳ Queued | - |
| #5444 | Security Testing | SecOps | 2 days | ⏳ Queued | - |

### Daily Standup Schedule

**Mon 2/24 @ 09:00 UTC:** Kickoff + Task #5439/#5440 start
**Tue 2/25 @ 09:00 UTC:** Task #5441/#5442 start + #5439/#5440 progress
**Wed 2/26 @ 09:00 UTC:** Task #5443/#5444 start + ops progress
**Thu 2/27 @ 09:00 UTC:** Final validation + deployment prep
**Fri 2/28 @ 09:00 UTC:** Go/no-go decision + production deployment

### Execution Timeline (Detailed)

EOF
  echo_success "Coordinator log initialized: $COORDINATOR_LOG"
}

# Check task status
check_status() {
  echo_info "Checking status of all 6 integration tasks..."

  for task_id in "${TASKS[@]}"; do
    status=$(gh issue view "$task_id" --repo "$REPO" --json state --jq '.state')
    echo "  Task #$task_id: $status"
  done
}

# Start a task (assign to user)
start_task() {
  local task_id=$1
  local assignee=$2

  echo_info "Starting task #$task_id (assigning to $assignee)..."

  gh issue edit "$task_id" --repo "$REPO" \
    --add-assignee "$assignee" \
    --add-label "in-progress"

  echo_success "Task #$task_id assigned to $assignee"
}

# Report progress
report_progress() {
  echo ""
  echo_info "Integration Task Coordinator Report"
  echo_info "====================================="
  echo ""

  local total=0
  local closed=0
  local in_progress=0

  for task_id in "${TASKS[@]}"; do
    state=$(gh issue view "$task_id" --repo "$REPO" --json state --jq '.state')
    title=$(gh issue view "$task_id" --repo "$REPO" --json title --jq '.title')

    total=$((total + 1))

    if [ "$state" = "CLOSED" ]; then
      closed=$((closed + 1))
      echo_success "#$task_id: $title (CLOSED)"
    elif grep -q "in-progress" <<< "$(gh issue view "$task_id" --repo "$REPO" --json labels --jq '.labels[].name')" 2>/dev/null; then
      in_progress=$((in_progress + 1))
      echo_warning "#$task_id: $title (IN PROGRESS)"
    else
      echo_info "#$task_id: $title (OPEN)"
    fi
  done

  echo ""
  echo "Progress: $closed/$total closed, $in_progress in-progress"
}

# Main dispatcher
case "${1:-status}" in
  init)
    init_log
    ;;
  start)
    if [ $# -lt 3 ]; then
      echo_error "Usage: $0 start <task_id> <assignee>"
      exit 1
    fi
    start_task "$2" "$3"
    ;;
  status)
    check_status
    ;;
  report)
    report_progress
    ;;
  *)
    echo_error "Unknown command: $1"
    echo "Usage: $0 [init|start|status|report]"
    exit 1
    ;;
esac
