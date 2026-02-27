#!/bin/bash
##############################################################################
# PR Reviewer Selector - Intelligent Reviewer Discovery Engine
# Purpose: Identify optimal reviewers based on file authorship & expertise
# FedRAMP: [NIST-AC-2, CM-3] Access control and change oversight
##############################################################################

set -euo pipefail

REPO="${1:-kushin77/ElevatedIQ-Mono-Repo}"
PR_NUMBER="${2:-}"

# ============================================================================
# CONFIGURATION
# ============================================================================
MAX_REVIEWERS=2
MAX_LOAD=5

log_info() { echo -e "ℹ️  $*" >&2; }
log_success() { echo -e "✅ $*" >&2; }
log_warn() { echo -e "⚠️  $*" >&2; }

# Get files changed in the PR
get_pr_files() {
    gh pr view "$PR_NUMBER" --repo "$REPO" --json files --jq '.files[].path' 2>/dev/null || echo ""
}

# Identify experts via git blame or directory history
get_authors_from_files() {
    local files="$1"
    local -a authors=()

    for file in $files; do
        if [[ -f "$file" ]]; then
            # Get authors of the file itself
            local file_authors=$(git blame "$file" 2>/dev/null | awk '{print $2}' | sed 's/[()]//g' | sort | uniq -c | sort -rn | head -2 | awk '{print $NF}')
            authors+=($file_authors)
        else
            # Try getting the directory if it's a new file
            local dir=$(dirname "$file")
            while [[ "$dir" != "." ]]; do
                if [[ -d "$dir" ]]; then
                     local dir_authors=$(git log --format='%an' -- "$dir" 2>/dev/null | head -20 | sort | uniq -c | sort -rn | head -2 | awk '{print $NF}')
                     authors+=($dir_authors)
                     break
                fi
                dir=$(dirname "$dir")
            done
        fi
    done

    printf '%s\n' "${authors[@]}" | sort | uniq -c | sort -rn | awk '{print $NF}'
}

# Check reviewer load [NIST-AC-2]
check_reviewer_load() {
    local user="$1"
    local load=$(gh pr list --repo "$REPO" --search "reviewer:$user state:open" --json number --jq 'length' 2>/dev/null || echo 0)

    if [[ "$load" -ge "$MAX_LOAD" ]]; then
        return 1
    fi
    return 0
}

main() {
    log_info "🚀 PR Reviewer Selector Initialized for PR #$PR_NUMBER"

    local files=$(get_pr_files)
    if [[ -z "$files" ]]; then
        log_warn "No files found for PR #$PR_NUMBER"
        exit 0
    fi

    log_info "Analyzing file authorship..."
    local candidates=$(get_authors_from_files "$files")

    local -a selected=()
    local whitelist_file="docs/management/valid_assignees.txt"

    # Filter candidates
    while IFS= read -r user; do
        [[ -z "$user" ]] && continue

        # Don't assign the PR author as reviewer
        local pr_author=$(gh pr view "$PR_NUMBER" --repo "$REPO" --json author --jq '.author.login' 2>/dev/null)
        [[ "$user" == "$pr_author" ]] && continue

        # Check against whitelist
        if grep -qx "$user" "$whitelist_file" 2>/dev/null; then
            if check_reviewer_load "$user"; then
                selected+=("$user")
            fi
        fi

        [[ ${#selected[@]} -ge $MAX_REVIEWERS ]] && break
    done <<< "$candidates"

    if [[ ${#selected[@]} -gt 0 ]]; then
        log_success "Found optimal reviewers: ${selected[*]}"
        echo "${selected[*]}" | tr ' ' ','
    else
        log_warn "No suitable reviewers found under load limit. Fallback to repository owners."
        # Fallback logic could be added here
    fi
}

main "$@"
