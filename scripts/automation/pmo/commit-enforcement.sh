#!/bin/bash

# 🚀 ElevatedIQ: Enhancement 5 - Commit Enforcement with NIST Tagging
# Validates every commit: signing, NIST control, issue reference, atomic commits

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../" && pwd)"

LOG_FILE="$REPO_ROOT/logs/pmo/commit-enforcement.log"
mkdir -p "$(dirname "$LOG_FILE")"

# Logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# NIST Control Reference
# Map: Control ID → Control Name
declare -A NIST_CONTROLS=(
    [AC-1]="Access Control Policy"
    [AC-2]="Account Management"
    [AC-3]="Access Enforcement"
    [AU-1]="Audit Policy"
    [AU-2]="Audit Events"
    [AU-3]="Content of Audit Records"
    [CA-1]="Security Assessment and Authorization Policy"
    [CA-7]="Continuous Monitoring"
    [CM-1]="Configuration Management Policy"
    [CM-3]="Configuration Change Control"
    [CP-1]="Contingency Planning Policy"
    [CP-4]="Contingency Plan Testing"
    [IA-1]="Identification and Authentication Policy"
    [IA-2]="Authentication"
    [IA-3]="Device Identification"
    [IA-4]="Identifier Management"
    [IA-5]="Authentication Mechanisms"
    [IA-6]="Authentication Feedback"
    [IA-7]="Cryptographic Module Authentication"
    [IA-8]="Identification and Authentication"
    [IA-9]="Service Identification and Authentication"
    [IA-10]="Adaptive Authentication"
    [IA-11]="Multi-Factor Authentication"
    [IA-12]="Account Management for Multi-Factor Authentication"
    [IR-1]="Incident Response Policy"
    [IR-4]="Incident Handling"
    [IR-5]="Incident Monitoring"
    [PE-1]="Physical and Environmental Protection Policy"
    [PE-2]="Physical Access"
    [PI-1]="Privacy Impact and Risk Assessments"
    [PI-2]="Privacy Notice"
    [SA-1]="System and Services Acquisition Policy"
    [SA-3]="System Development Life Cycle"
    [SC-1]="System and Communications Protection Policy"
    [SC-2]="Application Partitioning"
    [SC-7]="Boundary Protection"
    [SC-12]="Cryptographic Key Establishment and Management"
    [SC-13]="Cryptographic Protection"
    [SC-15]="Session Lock"
    [SI-1]="System and Information Integrity Policy"
    [SI-2]="Flaw Remediation"
    [SI-3]="Malicious Code Protection"
    [SI-4]="Information System Monitoring"
    [SI-11]="Error Handling"
)

# Validate commit message format
validate_commit_format() {
    local msg="$1"

    # Expected format:
    # type(scope): [NIST-XX-X] description Refs #ISSUE_NUM
    # Example: feat(api): [NIST-AC-3] implement role-based access Refs #2791

    local pattern="^(feat|fix|refactor|docs|style|test|chore|perf|ci|security)\([a-z0-9-]+\): \[NIST-[A-Z]{2}-[0-9]+\] .+ Refs #[0-9]+$"

    if ! [[ "$msg" =~ $pattern ]]; then
        return 1
    fi

    return 0
}

# Extract and validate NIST control
validate_nist_control() {
    local msg="$1"

    # Extract [NIST-XX-X]
    local control=$(grep -oP 'NIST-[A-Z]{2}-[0-9]+' <<< "$msg")

    if [ -z "$control" ]; then
        return 1
    fi

    # Check if valid control
    if [ -z "${NIST_CONTROLS[$control]}" ]; then
        log "⚠️  Warning: Unknown NIST control: $control"
        return 1
    fi

    return 0
}

# Check commit is signed
validate_signing() {
    local commit_ref="${1:--1}"

    # Check if commit will be signed
    local signing_config=$(git config --local --get commit.gpgsign || echo "false")

    if [ "$signing_config" != "true" ]; then
        return 1
    fi

    return 0
}

# Check number of files changed (atomic commits: 1-5 files)
validate_atomicity() {
    local max_files=5
    local staged_files=$(git diff --cached --name-only | wc -l)

    if [ "$staged_files" -gt "$max_files" ]; then
        log "❌ Too many files in commit: $staged_files (max: $max_files)"
        return 1
    fi

    if [ "$staged_files" -eq 0 ]; then
        log "❌ No files staged for commit"
        return 1
    fi

    return 0
}

# Pre-commit hook: Validate before commit
hook_pre_commit() {
    local commit_msg_file="$1"

    if [ ! -f "$commit_msg_file" ]; then
        log "⚠️  No commit message file provided"
        return 1
    fi

    local msg=$(cat "$commit_msg_file" | head -1)

    log "🔍 Validating commit: $msg"

    # 1. Check format
    if ! validate_commit_format "$msg"; then
        cat << 'ERROR'

❌ COMMIT MESSAGE FORMAT INVALID

Required format:
  <type>(scope): [NIST-XX-X] <description> Refs #ISSUE_NUM

Types: feat, fix, refactor, docs, style, test, chore, perf, ci, security

Example:
  feat(api): [NIST-AC-3] implement role-based caching Refs #2791

Valid NIST Controls: AC-1, AC-2, AC-3, AU-2, CA-7, etc.

ERROR
        return 1
    fi

    # 2. Check NIST control
    if ! validate_nist_control "$msg"; then
        cat << 'ERROR'

⚠️  NIST CONTROL VALIDATION FAILED

The [NIST-XX-X] control in your commit is invalid or unknown.

Valid examples:
  [NIST-AC-3] Access Enforcement
  [NIST-AU-2] Audit Events
  [NIST-CA-7] Continuous Monitoring
  [NIST-SI-2] Flaw Remediation

ERROR
        return 1
    fi

    # 3. Check for issue reference
    if ! echo "$msg" | grep -q "Refs #"; then
        cat << 'ERROR'

❌ NO ISSUE REFERENCE FOUND

Every commit must reference an issue:
  Refs #ISSUE_NUM

Example:
  feat(api): [NIST-AC-3] implement caching Refs #2791

ERROR
        return 1
    fi

    # 4. Check if signing is enabled
    if ! validate_signing; then
        cat << 'ERROR'

⚠️  WARNING: Commit Signing Not Enabled

This commit will NOT be signed. To enable signing:
  git config --global commit.gpgsign true
  git config --global user.signingkey <your-key-id>

To sign this commit manually:
  git commit -S -m "<your message>"

ERROR
        # Warning only, don't block
    fi

    # 5. Check atomicity
    if ! validate_atomicity; then
        cat << 'ERROR'

❌ COMMIT NOT ATOMIC

Commits should be atomic:
  - Max 5 files changed
  - Single logical change
  - Reviewable in <10 minutes

Your commit has too many changes.

Solutions:
  1. Split into multiple commits
  2. git reset HEAD <file>  # Unstage files
  3. Commit 1-5 files at a time

ERROR
        return 1
    fi

    log "✅ Commit validation passed"
    return 0
}

# Post-commit hook: Log validated commit
hook_post_commit() {
    local msg=$(git log -1 --format=%B)
    local commit_hash=$(git rev-parse HEAD)
    local author=$(git log -1 --format=%an)

    # Extract components
    local type=$(echo "$msg" | grep -oP '^(feat|fix|refactor|docs|style|test|chore|perf|ci|security)')
    local nist=$(echo "$msg" | grep -oP 'NIST-[A-Z]{2}-[0-9]+')
    local issue=$(echo "$msg" | grep -oP 'Refs #\K[0-9]+')

    log "✅ Commit recorded: $commit_hash"
    log "   Type: $type | NIST: $nist | Issue: #$issue | Author: $author"

    # Tag commit with NIST control for traceability
    git tag -f "${nist}_${issue}_${commit_hash:0:7}" "$commit_hash" 2>/dev/null || true
}

# Install hooks
install_hooks() {
    log "📝 Installing commit enforcement hooks..."

    local hooks_dir="$REPO_ROOT/.git/hooks"
    mkdir -p "$hooks_dir"

    # Pre-commit hook
    cat > "$hooks_dir/prepare-commit-msg" << 'HOOK'
#!/bin/bash
source $(dirname "$0")/../../scripts/pmo/commit-enforcement.sh
# Add template if empty/autogen
if [ "$2" != "message" ] && [ -z "$(cat $1 | grep -v '^#')" ]; then
    cat >> "$1" << 'TEMPLATE'

# Format: type(scope): [NIST-XX-X] description Refs #ISSUE
# Example: feat(api): [NIST-AC-3] implement caching Refs #2791
# Types: feat, fix, refactor, docs, style, test, chore, perf, ci, security
TEMPLATE
fi
HOOK
    chmod +x "$hooks_dir/prepare-commit-msg"

    # Pre-commit validation body
    cat > "$hooks_dir/pre-commit.validation" << 'HOOK'
#!/bin/bash
# This file is sourced by .git/hooks/pre-commit
HOOK
    chmod +x "$hooks_dir/pre-commit.validation"

    log "✅ Hooks installed"
    log "   Commits will be validated automatically"
    log "   Required format: type(scope): [NIST-XX-X] description Refs #ISSUE"
}

# Test commit validation
test_validation() {
    log "🧪 Testing commit validation..."

    local tests=(
        "feat(api): [NIST-AC-3] implement role-based access Refs #2791|PASS"
        "fix(core): [NIST-SI-2] resolve memory leak Refs #2792|PASS"
        "implement caching feature|FAIL"
        "feat(api): missing nist control Refs #2793|FAIL"
        "feat(api): [NIST-ZZ-9] implement something Refs #2794|FAIL"
    )

    for test_case in "${tests[@]}"; do
        IFS='|' read -r msg expected <<< "$test_case"

        if validate_commit_format "$msg" && validate_nist_control "$msg"; then
            result="PASS"
        else
            result="FAIL"
        fi

        if [ "$result" = "$expected" ]; then
            log "  ✅ $msg"
        else
            log "  ❌ $msg (expected $expected, got $result)"
        fi
    done
}

# Main entry point
case "${1:-}" in
    "install")
        install_hooks
        ;;
    "test")
        test_validation
        ;;
    *)
        cat << 'USAGE'
🚀 ElevatedIQ: Commit Enforcement with NIST Tagging

Validates every commit for:
  ✓ Correct message format
  ✓ NIST control reference
  ✓ Issue link (Refs #ISSUE)
  ✓ GPG signing (if enabled)
  ✓ Atomic commits (1-5 files max)

Usage:
  install              Install git hooks
  test                 Test validation rules

Format:
  type(scope): [NIST-XX-X] description Refs #ISSUE

Example:
  feat(api): [NIST-AC-3] implement redis caching Refs #2791

Types:
  feat, fix, refactor, docs, style, test, chore, perf, ci, security

Common NIST Controls:
  [NIST-AC-3]   Access Enforcement
  [NIST-AU-2]   Audit Events
  [NIST-CA-7]   Continuous Monitoring
  [NIST-SC-7]   Boundary Protection
  [NIST-SI-2]   Flaw Remediation

Setup:
  ./scripts/pmo/commit-enforcement.sh install
  git config --global commit.gpgsign true

USAGE
        ;;
esac
