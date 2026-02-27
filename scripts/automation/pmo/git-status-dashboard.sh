#!/usr/bin/env bash
################################################################################
# 📊 Multi-User Git Status Dashboard
# Purpose: Track uncommitted files across all users and provide visibility
# Features:
# - Shows uncommitted/staged changes per user (via commit authors)
# - Displays repository health metrics
# - Identifies stale branches
# - Tracks build/test status
# - Integrates with PMO session tracking
# - Generates alerts for high-uncommitted-file counts
################################################################################

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
SESSION_LOGS="${REPO_ROOT}/docs/management/SESSION_LOGS.md"
GIT_DASHBOARD="${REPO_ROOT}/docs/management/GIT_DASHBOARD.md"
CURRENT_USER=$(git config user.name || echo "unknown")
CURRENT_EMAIL=$(git config user.email || echo "unknown@example.com")

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ️${NC} $1"; }
log_success() { echo -e "${GREEN}✅${NC} $1"; }
log_warn() { echo -e "${YELLOW}⚠️${NC} $1"; }
log_error() { echo -e "${RED}❌${NC} $1"; }

###############################################################################
# Data Collection Functions
###############################################################################

get_current_uncommitted() {
    # Get uncommitted files in current working tree
    git status --porcelain 2>/dev/null | wc -l
}

get_branches_with_commits() {
    # Get local branches ahead of main
    git for-each-ref --format='%(refname:short) %(push:track)' refs/heads/ 2>/dev/null | \
        grep -v "main" | \
        grep "\[ahead" || echo ""
}

get_stale_branches() {
    # Identify branches not updated in 30+ days
    local cutoff=$(date -d "30 days ago" +%s)
    git for-each-ref --format='%(refname:short) %(committerdate:unix)' refs/heads/ 2>/dev/null | \
        while read branch timestamp; do
            if [ "$timestamp" -lt "$cutoff" ]; then
                echo "$branch"
            fi
        done || echo ""
}

get_merge_ready_prs() {
    # Count PRs ready to merge (requires gh CLI)
    if command -v gh > /dev/null 2>&1; then
        gh pr list --repo kushin77/ElevatedIQ-Mono-Repo --state open --search "draft:false" --limit 100 2>/dev/null | wc -l || echo "0"
    else
        echo "N/A"
    fi
}

get_recent_commits() {
    # Get recent commits grouped by author
    git log --oneline -20 --format='%an|%s' 2>/dev/null || echo ""
}

###############################################################################
# Dashboard Generation
###############################################################################

generate_dashboard() {
    local uncommitted=$(get_current_uncommitted)
    local branches_ahead=$(get_branches_with_commits | wc -l)
    local stale_branches=$(get_stale_branches | wc -l)
    local merge_ready=$(get_merge_ready_prs)

    cat > "${GIT_DASHBOARD}" << EOF
# 📊 Git Repository Status Dashboard

**Generated**: $(date -Iseconds)
**Repository**: \`${REPO_ROOT##*/}\`
**Current Branch**: \`$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")\`
**Current User**: \`${CURRENT_USER}\`

---

## 🔍 Repository Health Status

| Metric | Value | Status |
|--------|-------|--------|
| Uncommitted files | $uncommitted | $([ "$uncommitted" -eq 0 ] && echo "✅ CLEAN" || echo "⚠️ NEEDS ATTENTION") |
| Branches ahead of main | $branches_ahead | $([ "$branches_ahead" -le 3 ] && echo "✅ OK" || echo "⚠️ MANY") |
| Stale branches (30+ days) | $stale_branches | $([ "$stale_branches" -eq 0 ] && echo "✅ CLEAN" || echo "⚠️ CLEANUP NEEDED") |
| PRs ready to merge | $merge_ready | $([ "$merge_ready" != "0" ] && echo "🔄 IN PROGRESS" || echo "✅ SYNCED") |

---

## 👥 User Activity (Last 20 Commits)

\`\`\`
Author                    | Recent Commits
--------------------------|-----------------------------------
EOF

    git log --oneline -20 --format='%an' 2>/dev/null | sort | uniq -c | sort -rn | \
        while read count author; do
            printf "%-24s | %d commits\n" "$author" "$count" >> "${GIT_DASHBOARD}"
        done

    cat >> "${GIT_DASHBOARD}" << 'EOF'
```

---

## 🌿 Branch Status

### Branches Ahead of Main
```
EOF

    local branches=$(get_branches_with_commits)
    if [ -z "$branches" ]; then
        echo "None - all branches synced" >> "${GIT_DASHBOARD}"
    else
        echo "$branches" >> "${GIT_DASHBOARD}"
    fi

    cat >> "${GIT_DASHBOARD}" << 'EOF'
```

### Stale Branches (30+ days old)
```
EOF

    local stale=$(get_stale_branches)
    if [ -z "$stale" ]; then
        echo "None - all branches current" >> "${GIT_DASHBOARD}"
    else
        echo "$stale" >> "${GIT_DASHBOARD}"
    fi

    cat >> "${GIT_DASHBOARD}" << 'EOF'
```

---

## 📈 Statistics

- **Total commits**: $(git rev-list --count HEAD 2>/dev/null || echo "?")
- **Remote URL**: $(git config --get remote.origin.url 2>/dev/null || echo "?")
- **Last fetch**: $(stat --format=%y .git/FETCH_HEAD 2>/dev/null | cut -d. -f1 || echo "?")
- **Current HEAD**: $(git rev-parse --short HEAD 2>/dev/null || echo "?")

---

## 🔒 Security Status

- **Unsigned commits**: $(git log --pretty=format:%G? -20 | grep -v G | wc -l) (should be 0)
- **Secrets detected**: $(if command -v gitleaks >/dev/null; then gitleaks detect --source git --exit-code 0 2>/dev/null | wc -l; else echo "unknown"; fi)

---

## ⚡ Quick Actions

\`\`\`bash
# View detailed status
git status

# Auto-commit uncommitted changes
./scripts/pmo/auto-commit-enforcer.sh

# Validate repository health
./scripts/pmo/git_workflow_optimizer.sh validate

# Clean up stale branches
git branch --delete <branch-name>

# Refresh this dashboard
./scripts/pmo/git-status-dashboard.sh
\`\`\`

---

**Last Updated**: $(date)
EOF

    log_success "Dashboard generated: $GIT_DASHBOARD"
}

###############################################################################
# Display Functions
###############################################################################

display_terminal() {
    local uncommitted=$(get_current_uncommitted)
    local branches_ahead=$(get_branches_with_commits | wc -l)

    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║          📊 Git Repository Status Dashboard                    ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""

    echo "Repository:       ${REPO_ROOT##*/}"
    echo "Branch:           $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
    echo "User:             ${CURRENT_USER}"
    echo "Email:            ${CURRENT_EMAIL}"
    echo ""

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Health Status:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if [ "$uncommitted" -eq 0 ]; then
        log_success "Repository is clean (0 uncommitted files)"
    else
        log_warn "Uncommitted files detected: $uncommitted"
    fi

    if [ "$branches_ahead" -eq 0 ]; then
        log_success "All branches synchronized with main"
    else
        log_warn "Branches ahead of main: $branches_ahead"
    fi

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Recent Activity (Last 5 commits):"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    git log --oneline -5 2>/dev/null | sed 's/^/  /'

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

###############################################################################
# Main
###############################################################################

log_info "Generating Git Status Dashboard"
echo ""

# Display terminal version
display_terminal

# Generate markdown dashboard
generate_dashboard

# Log to PMO session
if [ -f "$SESSION_LOGS" ]; then
    UNCOMMITTED=$(get_current_uncommitted)
    echo "- **[$(date +%H:%M:%S)]** GIT_DASHBOARD: User=$CURRENT_USER | Uncommitted=$UNCOMMITTED" >> "$SESSION_LOGS"
fi

log_success "Dashboard complete"
echo ""
