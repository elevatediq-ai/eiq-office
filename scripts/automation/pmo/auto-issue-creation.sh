#!/bin/bash

# 🚀 ElevatedIQ: Enhancement 1 - Smart Issue Auto-Creation
# Creates GitHub issues automatically from detected actionable patterns

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../" && pwd)"

# Configuration
ISSUE_CACHE="$REPO_ROOT/.pmo-cache/auto-issues"
LOG_FILE="$REPO_ROOT/logs/pmo/auto-issue-creation.log"

mkdir -p "$(dirname "$LOG_FILE")" "$ISSUE_CACHE"

# Logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Detect actionable patterns in text
detect_action_items() {
    local text="$1"
    local session_id="$2"

    # Action verbs: implement, add, fix, refactor, optimize, improve, enhance, create, build, design
    local patterns=(
        "implement|add|fix|refactor|optimize|improve|enhance|create|build|design"
    )

    # Match: VERB + NOUN patterns
    if echo "$text" | grep -i -E "(implement|add|fix|refactor|optimize|improve|enhance|create|build|design).{0,50}(for|in|to|with|using|via)" > /dev/null; then
        echo "1"  # Action detected
        return 0
    fi

    echo "0"  # No action detected
    return 1
}

# Extract issue title from text
extract_title() {
    local text="$1"

    # Remove leading/trailing whitespace
    text=$(echo "$text" | xargs)

    # Capitalize first letter
    text="$(tr '[:lower:]' '[:upper:]' <<< "${text:0:1}")${text:1}"

    # Limit to 80 characters
    echo "${text:0:80}"
}

# Determine issue type from text
detect_issue_type() {
    local text="$1"

    if echo "$text" | grep -i "fix\|bug\|error\|crash" > /dev/null; then
        echo "fix"
    elif echo "$text" | grep -i "optimize\|performance\|speed\|cache" > /dev/null; then
        echo "optimization"
    elif echo "$text" | grep -i "add\|implement\|feature\|new" > /dev/null; then
        echo "feat"
    elif echo "$text" | grep -i "refactor\|clean\|restructure" > /dev/null; then
        echo "refactor"
    else
        echo "feat"
    fi
}

# Detect priority from keywords
detect_priority() {
    local text="$1"

    if echo "$text" | grep -i "critical\|urgent\|blocking\|asap" > /dev/null; then
        echo "priority-p0"
    elif echo "$text" | grep -i "important\|high\|urgent" > /dev/null; then
        echo "priority-p1"
    else
        echo "priority-p2"
    fi
}

# Create GitHub issue via CLI
create_github_issue() {
    local title="$1"
    local description="$2"
    local type_label="$3"
    local priority="$4"
    local session_id="$5"

    if ! command -v gh &> /dev/null; then
        log "❌ GitHub CLI not found. Skipping issue creation."
        return 1
    fi

    # Build issue body with session context
    local body="## Context
Auto-created from action detection during session $session_id

### What
$title

### Why
Detected from chat/commit pattern

### Acceptance Criteria
- [ ] Implementation complete
- [ ] Tests passing
- [ ] Reviewed and approved

**Session**: $session_id
**Auto-created**: $(date '+%Y-%m-%d %H:%M:%S')
"

    # Create issue via Unified Issue Engine (UIE)
    local issue_url
    issue_url=$(bash "$(dirname "${BASH_SOURCE[0]}")/uie.sh" \
        --title "[${type_label}] $title" \
        --body "$body" \
        --labels "$type_label,$priority,auto-created" 2>&1)

    if [ $? -eq 0 ]; then
        local issue_num=$(echo "$issue_url" | grep -oP '/issues/\K[0-9]+' | head -1)
        log "✅ Created issue #$issue_num: $title"
        echo "$issue_num"

        # Cache issue
        echo "$issue_num:$title" >> "$ISSUE_CACHE/$(date +%Y%m%d).cache"
        return 0
    else
        log "❌ Failed to create issue: $title"
        return 1
    fi
}

# Main: Process input text and create issue if actionable
process_input() {
    local input_text="$1"
    local session_id="${2:-$(date +%s)}"

    log "📝 Processing: $input_text"

    # Detect if actionable
    if ! detect_action_items "$input_text"; then
        log "⏭️  Non-actionable. Skipping."
        return 0
    fi

    # Extract components
    local title=$(extract_title "$input_text")
    local type_label=$(detect_issue_type "$input_text")
    local priority=$(detect_priority "$input_text")

    log "🔍 Detected: type=$type_label, priority=$priority"

    # Create issue
    create_github_issue "$title" "$input_text" "$type_label" "$priority" "$session_id"
}

# Hook integration: Process git commit message
process_commit_message() {
    local commit_msg_file="$1"

    if [ ! -f "$commit_msg_file" ]; then
        return 0
    fi

    local msg=$(cat "$commit_msg_file" | head -1)

    # Only process if not already referencing an issue
    if echo "$msg" | grep -E "Closes #|Refs #" > /dev/null; then
        return 0
    fi

    # Try to auto-create issue for new work
    process_input "$msg" "git-commit"
}

# Main entry point
case "${1:-}" in
    "process")
        process_input "$2" "$3"
        ;;
    "commit")
        process_commit_message "$2"
        ;;
    "test")
        echo "🧪 Testing auto-issue creation..."

        test_cases=(
            "implement redis caching for API layer"
            "fix performance regression in query handler"
            "optimize database connection pooling"
        )

        for test in "${test_cases[@]}"; do
            echo "  Test: $test"
            process_input "$test" "test-session"
        done

        echo "✅ Tests complete"
        ;;
    *)
        cat << 'USAGE'
🚀 ElevatedIQ: Smart Issue Auto-Creation

Usage:
  process <text> [session_id]    Process text and create issue if actionable
  commit <msg_file>              Process git commit message
  test                           Run test cases

Examples:
  $0 process "implement redis caching for API layer"
  $0 commit /tmp/commit_msg
  $0 test
USAGE
        ;;
esac
