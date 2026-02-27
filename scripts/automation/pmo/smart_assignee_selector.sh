#!/bin/bash
##############################################################################
# Smart Assignee Selector - AI-Native Intelligent Issue Assignee Classifier
# Purpose: Analyze git history and issue context to identify optimal assignees
# Session: 20260216-ASSIGNEE-AUTOMATION-HARDENING
# Issue: #3286
# FedRAMP: [NIST-CM-3] Configuration change control with audit trail
# Features:
#   - Git blame analysis (recent commits)
#   - PR author history (related PRs)
#   - Issue keywords (domain expertise detection)
#   - Team structure (balanced assignment)
#   - Max 5 assignees per issue (optimal review load)
##############################################################################

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

REPO="${1:-kushin77/ElevatedIQ-Mono-Repo}"
ISSUE_NUMBER="${2:-}"
ISSUE_TITLE="${3:-}"
ISSUE_BODY="${4:-}"
FILES_CHANGED="${5:-}"

# How many commits to analyze for history
COMMIT_COUNT=50

# Expertise keywords mapped to likely assignees (domain detection)
declare -A EXPERTISE_KEYWORDS=(
    [security]="security,auth,fedramp,nist,cve,vulnerability,encryption,secrets"
    [ai]="ai,ml,llm,embedding,model,training,inference,agent,vectordb"
    [infrastructure]="infra,terraform,k8s,kubernetes,deployment,provisioning,iac"
    [finops]="cost,finops,budget,billing,optimization,forecast,roi"
    [observability]="monitor,logging,metrics,traces,observability,dashboard,alerts"
    [platform]="platform,core,engine,orchestrator,control-plane,hub,api"
    [devops]="devops,ci,cd,pipeline,workflow,automation,github,actions"
)

# ============================================================================
# FUNCTIONS
# ============================================================================

# Source centralized logging lib for consistent helpers
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${script_dir}/../lib/logging.sh" ]]; then
    # shellcheck source=/dev/null
    source "${script_dir}/../lib/logging.sh"
else
    # Fallback minimal logger
    log_info() { echo "ℹ️  $*" >&2; }
    log_warn() { echo "⚠️  $*" >&2; }
    log_error() { echo "❌ $*" >&2; }
    log_debug() { echo "🔍 $*" >&2; }
    log_success() { echo "✅ $*" >&2; }
fi

# Extract assignees from git blame of related files
get_assignees_from_git_history() {
    local files="$1"
    local -a candidates=()

    if [[ -z "$files" ]]; then
        log_debug "No files provided for git history analysis"
        return
    fi

    # Analyze each file
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        [[ ! -f "$file" ]] && continue

        # Get recent authors from git blame
        git blame "$file" 2>/dev/null | awk '{print $2}' | sed 's/[()]//g' | \
        sort | uniq -c | sort -rn | head -10 | awk '{print $NF}' || true

    done <<< "$files"
}

# Extract assignees from related PRs
get_assignees_from_related_prs() {
    local title="$1"
    local -a keywords=()

    [[ -z "$title" ]] && return

    # Extract keywords from title
    keywords=($(echo "$title" | tr '[:upper:]' '[:lower:]' | grep -oE '\b[a-z]{4,}\b' | head -5))

    log_debug "Searching for PRs with keywords: ${keywords[*]}"

    # Search for related PRs
    for keyword in "${keywords[@]}"; do
        gh pr list --repo "$REPO" --search "state:closed $keyword" --limit 20 --json "author" 2>/dev/null | \
        jq -r '.[].author.login' 2>/dev/null || true
    done
}

# Extraction: Analyze user workload to prevent bottlenecks [NIST-AC-2]
# This hardening ensures we don't over-burden a single developer
check_user_workload() {
    local user="$1"
    local limit="${MAX_LOAD_PER_USER:-15}"

    # Fast check via GH CLI
    local count=$(gh issue list --repo "$REPO" --assignee "$user" --state open --limit 100 --json number --jq 'length' 2>/dev/null || echo 0)

    if [[ "$count" -ge "$limit" ]]; then
        log_debug "User @$user is at capacity ($count/$limit). Reducing rank."
        return 1
    fi
    return 0
}

# Analyze issue keywords to detect domain expertise needed
get_assignees_by_expertise() {
    local title="$1"
    local body="$2"
    local combined_text="${title} ${body}"

    # Convert to lowercase for keyword matching
    combined_text=$(echo "$combined_text" | tr '[:upper:]' '[:lower:]')

    # Check each expertise category
    for domain in "${!EXPERTISE_KEYWORDS[@]}"; do
        keywords="${EXPERTISE_KEYWORDS[$domain]}"

        # Split keywords and check each one
        IFS=',' read -ra keyword_array <<< "$keywords"
        for keyword in "${keyword_array[@]}"; do
            if echo "$combined_text" | grep -qi "\b$keyword\b"; then
                log_debug "Detected domain: $domain (keyword: $keyword)"

                # Query issues labeled with this domain to find experts
                local dynamic_experts
                dynamic_experts=$(gh api "repos/$REPO/issues?labels=$domain&state=all&per_page=30" --jq '.[].assignees? // [] | .[].login' 2>/dev/null | sort | uniq -c | sort -rn | head -5 | awk '{print $NF}' || true)

                if [[ -n "$dynamic_experts" ]]; then
                    echo "$dynamic_experts"
                else
                    log_debug "Dynamic lookup failed for $domain, using fallback experts"
                    echo "${DOMAIN_EXPERTS[$domain]:-}" | tr ',' '\n'
                fi
                break
            fi
        done
    done
}

# Build final candidate list with deduplication and weighting
select_optimal_assignees() {
    local git_assignees="$1"
    local pr_assignees="$2"
    local expertise_assignees="$3"

    # Combine all candidates
    {
        [[ -n "$git_assignees" ]] && echo "$git_assignees" | sed 's/.*/& 3/'
        [[ -n "$pr_assignees" ]] && echo "$pr_assignees" | sed 's/.*/& 2/'
        [[ -n "$expertise_assignees" ]] && echo "$expertise_assignees" | sed 's/.*/& 1/'
    } | awk '$1 != "" {user=$1; points=$2; total[user]+=points; count[user]++}
         END {for (u in total) printf "%s %d\n", u, total[u]}' | \
    sort -k2 -rn | \
    head -5 | \
    awk '{print $1}'
}

# Validate assignees (ensure they're real users in the repo and not overloaded)
validate_assignees() {
    local assignees="$1"
    local -a valid=()
    local whitelist_file="docs/management/valid_assignees.txt"
    local MAX_LOAD=500

    # Ensure whitelist exists (cache if possible)
    if [[ ! -f "$whitelist_file" ]]; then
        gh api repos/"$REPO"/assignees --jq '.[].login' > "$whitelist_file" 2>/dev/null || true
    fi

    # Helper: valid GitHub username pattern (alnum + hyphen, no leading/trailing hyphen)
    local user_regex='^[a-zA-Z0-9][a-zA-Z0-9-]{0,38}$'

    while IFS= read -r user; do
        [[ -z "$user" ]] && continue

        # Strip common prefixes and stray characters
        user=$(echo "$user" | sed 's|^app/||; s|^@||; s|[^a-zA-Z0-9-]||g')

        # Reject obviously invalid / numeric-only tokens
        if [[ -z "$user" ]] || [[ "$user" =~ ^[0-9]+$ ]]; then
            log_debug "Rejecting candidate '$user' (invalid or numeric)"
            continue
        fi

        # Validate format
        if [[ ! "$user" =~ $user_regex ]]; then
            log_debug "Rejecting candidate '$user' (fails username pattern)"
            continue
        fi

        # Check against whitelist
        if grep -iqx "$user" "$whitelist_file" 2>/dev/null; then
            # Load check [NIST-AC-2]
            local load
            # Use search API for efficient total count retrieval
            load=$(gh api "search/issues?q=repo:$REPO+assignee:$user+is:open" --jq '.total_count' 2>/dev/null || echo 0)
            [[ -z "$load" ]] && load=0

            if [[ "$load" -lt "$MAX_LOAD" ]]; then
                valid+=("$user")
            else
                log_debug "Skipping @$user due to overload ($load active tasks)"
            fi
        else
            log_debug "Candidate '$user' not in repo assignees whitelist"
        fi
    done <<< "$assignees"

    # If none valid, return empty to force manual triage (safer than returning numeric or malformed tokens)
    if [[ ${#valid[@]} -eq 0 ]]; then
        log_debug "No valid candidates after validation — will require manual assignment."
        return 0
    fi

    # Print validated candidates (one per line)
    printf '%s\n' "${valid[@]}"
}

# Get issue number from search or return provided one
resolve_issue_number() {
    if [[ -n "$ISSUE_NUMBER" ]]; then
        echo "$ISSUE_NUMBER"
    else
        # If no issue number provided, get the most recent open issue
        gh issue list --repo "$REPO" --state open --limit 1 --json number | jq -r '.[0].number'
    fi
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    log_info "🚀 Smart Assignee Selector Initialized"
    log_info "Repository: $REPO"
    log_info "Issue: $ISSUE_NUMBER | Title: ${ISSUE_TITLE:0:40}..."

    if [[ -z "$ISSUE_NUMBER" ]] && [[ -z "$ISSUE_TITLE" ]]; then
        log_info "Usage: $0 <repo> <issue_number> [title] [body] [files]"
        log_info "Example: $0 kushin77/ElevatedIQ-Mono-Repo 42 'Fix auth bug' 'Body text' 'apps/auth/service.py'"
        exit 0
    fi

    # Step 1: Analyze git history for file contributors
    log_info "Step 1: Analyzing git history..."
    git_candidates=$(get_assignees_from_git_history "$FILES_CHANGED" || true)

    # Step 2: Find related PRs
    log_info "Step 2: Searching related pull requests..."
    pr_candidates=$(get_assignees_from_related_prs "$ISSUE_TITLE" || true)

    # Step 3: Match against domain expertise
    log_info "Step 3: Detecting domain expertise..."
    expertise_candidates=$(get_assignees_by_expertise "$ISSUE_TITLE" "$ISSUE_BODY" || true)

    # Step 4: Select optimal assignees
    log_info "Step 4: Selecting optimal assignees..."
    selected=$(select_optimal_assignees \
        "$git_candidates" \
        "$pr_candidates" \
        "$expertise_candidates" || true)

    # Step 5: Validate assignees
    log_info "Step 5: Validating assignees..."
    final_assignees=$(validate_assignees "$selected" || true)

    # Output results (double-validated and sanitized)
    if [[ -n "$final_assignees" ]]; then
        # Ensure only valid GitHub logins are returned (defensive filter)
        sanitized=$(echo "$final_assignees" | sed 's/^@//; s|^app/||' | grep -E '^[a-zA-Z0-9][a-zA-Z0-9-]{0,38}$' || true)

        if [[ -z "$sanitized" ]]; then
            log_info "Selected candidates were invalid after sanitization - no assignees will be returned."
            echo ""
            return 0
        fi

        log_success "Selected assignees:"
        echo "$sanitized" | nl -w2 -s'. ' >&2

        # Return comma-separated for use in other scripts
        echo "$sanitized" | paste -sd ',' -
    else
        log_info "No suitable assignees found. Issue will require manual assignment."
        echo ""
    fi
}

# Execute main function only when script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
