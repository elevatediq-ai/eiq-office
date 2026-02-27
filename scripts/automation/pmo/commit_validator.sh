#!/bin/bash

# Elite PMO Commit Message Validator
# Enforces Conventional Commits with Issue References & NIST Controls

set -euo pipefail

# Format: <type>(scope): [NIST-XX-X[/YY-Z...]] <description> Refs|Closes #<issue>
pattern="^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert|security|iac|gov)(\(.+\))?: (\[NIST-[A-Z]{2}-[0-9]+(/[A-Z]{2}-[0-9]+)*\] )?.+ (Refs|Closes) #[0-9]+$"
baseline_file="${COMMIT_VALIDATOR_BASELINE_FILE:-.pmo/commit_validator_baseline.ref}"
allowlist_file="${COMMIT_VALIDATOR_ALLOWLIST_FILE:-.pmo/commit_validator_allowlist.txt}"

validate_msg() {
    local msg="$1"
        local type_prefix='^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert|security|iac|gov)(\(.+\))?: '

        if [[ "$msg" =~ ${type_prefix}\[ ]] \
            && [[ ! "$msg" =~ ${type_prefix}\[NIST-[A-Z]{2}-[0-9]+(/[A-Z]{2}-[0-9]+)*\][[:space:]] ]]; then
        echo "❌ ERROR: Malformed NIST control tag in commit message: \"$msg\""
        echo "Expected NIST tag format: [NIST-XX-X] or [NIST-XX-X/YY-Z/... ]"
        return 1
    fi

    if [[ ! "$msg" =~ $pattern ]]; then
        echo "❌ ERROR: Invalid commit message format: \"$msg\""
        echo "Expected format: <type>(scope): [NIST-XX-X[/YY-Z...]] <description> Refs #<issue>"
        return 1
    fi
    return 0
}

is_allowlisted_commit() {
    local commit_hash="$1"

    [[ -f "$allowlist_file" ]] || return 1

    grep -Eq "^${commit_hash}([[:space:]]|$)" "$allowlist_file"
}

run_validation_window() {
    local label="$1"
    shift

    local checked_count=0
    local skipped_count=0
    local invalid_count=0

    echo "🔍 Checking ${label}..."

    while IFS=$'\x1f' read -r commit_hash commit_subject; do
        if [[ -z "$commit_hash" || -z "$commit_subject" ]]; then
            continue
        fi

        if is_allowlisted_commit "$commit_hash"; then
            skipped_count=$((skipped_count + 1))
            continue
        fi

        checked_count=$((checked_count + 1))
        if ! validate_msg "$commit_subject"; then
            invalid_count=$((invalid_count + 1))
        fi
    done < <(git log "$@" --format='%H%x1f%s')

    if [[ $invalid_count -gt 0 ]]; then
        echo "❌ Found $invalid_count invalid commit message(s) out of $checked_count checked commit(s), with $skipped_count allowlisted commit(s)."
        return 1
    fi

    echo "✅ All checked commits are valid ($checked_count checked, $skipped_count allowlisted)."
    return 0
}

if [[ "${1:-}" == "--check-all" ]]; then
    log_args=(-10)
    using_baseline=false

    if [[ -f "$baseline_file" ]]; then
        baseline_ref=$(tr -d '[:space:]' < "$baseline_file")
        if [[ -z "$baseline_ref" ]]; then
            echo "❌ ERROR: Baseline file '$baseline_file' is empty."
            exit 1
        fi
        if ! git rev-parse --verify -q "${baseline_ref}^{commit}" >/dev/null; then
            echo "❌ ERROR: Baseline ref '$baseline_ref' from '$baseline_file' is not a valid commit."
            exit 1
        fi
        if ! git merge-base --is-ancestor "$baseline_ref" HEAD; then
            echo "❌ ERROR: Baseline ref '$baseline_ref' must be an ancestor of HEAD."
            exit 1
        fi

        echo "🔍 Checking commits in range ${baseline_ref}..HEAD..."
        log_args=("${baseline_ref}..HEAD")
        using_baseline=true
    else
        echo "🔍 Checking last 10 commits..."
    fi

    checked_count=$(git log "${log_args[@]}" --format=%s | sed '/^$/d' | wc -l)
    if [[ $checked_count -eq 0 && "$using_baseline" == "true" ]]; then
        echo "⚠️ Baseline range contains 0 commits; falling back to last 10 commits to avoid false-green."
        run_validation_window "last 10 commits fallback" -10
        exit $?
    fi

    run_validation_window "selected commit window" "${log_args[@]}"
    exit $?
fi

commit_msg_file="${1:-}"
if [[ -z "$commit_msg_file" || ! -f "$commit_msg_file" ]]; then
    echo "❌ ERROR: commit message file path is required."
    exit 1
fi

commit_msg=$(cat "$commit_msg_file")

if ! validate_msg "$commit_msg"; then
    echo "Examples:"
    echo "  feat(iac): [NIST-SC-7] add waf rules Refs #42"
    echo "  feat(core): [NIST-SC-8/SI-4/CA-7] harden policy checks Refs #100"
    echo "  fix(core): [NIST-AC-3] resolve permission bug Closes #15"
    echo ""
    echo "Allowed types: feat, fix, docs, style, refactor, perf, test, build, ci, chore, revert, security, iac, gov"
    exit 1
fi

echo "✅ Commit message validated."
exit 0
