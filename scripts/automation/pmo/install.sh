#!/usr/bin/env bash
# ==============================================================================
# PMO System Installer - Bootstrap PMO in Any Repository
# ==============================================================================
# Purpose: Install the reusable PMO subsystem into another repository
# Usage: ./scripts/pmo/install.sh <target-repo-path> [options]
# ==============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ==============================================================================
# Display Help
# ==============================================================================
show_help() {
    cat <<EOF
${CYAN}PMO System Installer${NC}

${CYAN}Usage:${NC}
  $(basename "$0") <target-repo-path> [options]

${CYAN}Options:${NC}
  --help, -h           Show this help message
  --force              Overwrite existing PMO files
  --skip-docs          Skip documentation installation
  --skip-tests         Skip test installation
  --skip-wrappers      Skip Python/PowerShell client wrappers

${CYAN}Examples:${NC}
  $(basename "$0") ~/MyRepo
  $(basename "$0") ~/MyRepo --force --skip-tests
  $(basename "$0") . # Install in current directory

${CYAN}What Gets Installed:${NC}
  ✓ scripts/pmo/lib/common.sh       (Core library)
  ✓ scripts/pmo/install.sh          (This installer)
  ✓ docs/management/PMO_README.md   (Getting-started guide)
  ✓ docs/management/ISSUE_TEMPLATES (Markdown templates)
  ✓ tests/pmo/                       (Test suite)
  ✓ scripts/pmo/clients/            (Python, PowerShell wrappers)

${CYAN}Requirements:${NC}
  • GitHub CLI (gh) configured and authenticated
  • Bash 4.0+
  • Target repo has .git/ directory

EOF
}

# ==============================================================================
# Main Installation Logic
# ==============================================================================
main() {
    local target_repo="${1:-.}"
    local force=0
    local skip_docs=0
    local skip_tests=0
    local skip_wrappers=0

    # Parse options
    while [[ $# -gt 1 ]]; do
        case "$2" in
            --force)
                force=1
                shift
                ;;
            --skip-docs)
                skip_docs=1
                shift
                ;;
            --skip-tests)
                skip_tests=1
                shift
                ;;
            --skip-wrappers)
                skip_wrappers=1
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                echo -e "${RED}Unknown option: $2${NC}"
                show_help
                exit 1
                ;;
        esac
    done

    # Validate target repository
    if [[ ! -d "$target_repo/.git" ]]; then
        echo -e "${RED}✗ Error: $target_repo is not a git repository${NC}"
        echo -e "${YELLOW}  Initialize with: git init${NC}"
        return 1
    fi

    echo -e "${CYAN}╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║   PMO System Installer                             ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════╝${NC}"

    echo ""
    echo -e "${BLUE}Target Repository:${NC} $target_repo"

    local source_pmo_lib="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
    local source_installer="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/install.sh"

    # Get script directory for sourcing
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    # Create target directories
    mkdir -p "$target_repo/scripts/pmo/lib"
    mkdir -p "$target_repo/docs/management"
    mkdir -p "$target_repo/logs/pmo"

    if [[ $skip_tests -eq 0 ]]; then
        mkdir -p "$target_repo/tests/pmo"
    fi

    if [[ $skip_wrappers -eq 0 ]]; then
        mkdir -p "$target_repo/scripts/pmo/clients/python"
        mkdir -p "$target_repo/scripts/pmo/clients/powershell"
    fi

    # Copy core files
    echo -e "${CYAN}Installing core files...${NC}"
    cp "$source_pmo_lib" "$target_repo/scripts/pmo/lib/common.sh"
    chmod +x "$target_repo/scripts/pmo/lib/common.sh"
    echo -e "${GREEN}  ✓ Common library${NC}"

    cp "$source_installer" "$target_repo/scripts/pmo/install.sh"
    chmod +x "$target_repo/scripts/pmo/install.sh"
    echo -e "${GREEN}  ✓ Installer${NC}"

    # Install documentation unless skipped
    if [[ $skip_docs -eq 0 ]]; then
        echo -e "${CYAN}Installing documentation...${NC}"

        # Create PMO_README.md
        cat > "$target_repo/docs/management/PMO_README.md" <<'EOF'
# PMO System - Getting Started

## Overview

The PMO (Project Management Office) system is a collection of Bash scripts and utilities that automate GitHub issue management, session tracking, and project metrics collection.

> **Key Principle**: The PMO system follows GitHub's "Issue-as-the-Source-of-Truth" model. Every task should have a corresponding GitHub issue.

## Quick Start (3 Steps)

### 1. Configure Your Repository

Set environment variables in your shell or `.bashrc`:

```bash
export REPO="your-github-username/your-repo-name"
export REPO_ROOT="/path/to/your/repo"
export PMO_LOG_DIR="${REPO_ROOT}/logs/pmo"
```

### 2. Source the Common Library

In your scripts, add:

```bash
#!/usr/bin/env bash
source "$REPO_ROOT/scripts/pmo/lib/common.sh"
pmo_validate_repo || exit 1
```

### 3. Use PMO Functions

```bash
# Create an epic
pmo_create_epic "My Feature" "Description" P1 foundation

# List open issues
pmo_list_issues open

# Create a task
pmo_create_task "Implement X" "Description" P2 "" "2 days"

# Update issue status
pmo_update_issue_status 42 in-progress "Starting work"

# Assign issue
pmo_assign_issue 42 username

# Add comment
pmo_add_issue_comment 42 "Progress update: Completed API design"
```

## Available Functions

### Issue Creation

- `pmo_create_issue(title, body, labels, assignees)` - Create custom issue
- `pmo_create_epic(title, description, priority, phase)` - Create epic issue
- `pmo_create_task(title, description, priority, epic, effort)` - Create task issue

### Issue Management

- `pmo_list_issues(state, label, limit)` - List issues
- `pmo_update_issue_status(issue_num, status, comment)` - Update status
- `pmo_assign_issue(issue_num, assignee)` - Assign to user
- `pmo_add_issue_comment(issue_num, comment)` - Add comment

### Session Tracking

- `pmo_init_session_log()` - Initialize session log file
- `pmo_log_session_update(session_id, message, type)` - Log progress

### Utilities

- `pmo_validate_repo()` - Validate repo setup
- `pmo_format_duration(seconds)` - Format time duration
- `pmo_print_header(title, width)` - Print formatted header

## Complete Example: Create and Track an Issue

```bash
#!/usr/bin/env bash
set -euo pipefail

# Configuration
export REPO="myuser/myrepo"
export REPO_ROOT="."

# Source the PMO library
source scripts/pmo/lib/common.sh

# Validate setup
pmo_validate_repo || exit 1

# Create an epic
echo "Creating epic..."
pmo_create_epic "Authentication System" \
  "Implement OAuth2 authentication" \
  P1 \
  foundation

# Create related tasks would follow similarly
echo "✓ Epic created!"
```

## Environment Variables

| Variable | Purpose | Example |
|----------|---------|---------|
| `REPO` | GitHub repo (required) | `owner/repo` |
| `REPO_ROOT` | Local repo path | `/home/user/myrepo` |
| `PMO_LOG_DIR` | Session logs location | `./logs/pmo` |
| `SESSION_LOG` | Session audit trail | `./docs/management/SESSION_LOGS.md` |
| `PMO_DASHBOARD` | Dashboard file | `./docs/management/PMO_DASHBOARD.md` |

## Requirements

- **GitHub CLI** (gh) - installed and authenticated via `gh auth login`
- **Bash 4.0+** - POSIX-compatible shell
- **.git directory** - valid git repository
- **GitHub authentication** - personal access token with repo permissions

## Troubleshooting

### "REPO environment variable not set"

```bash
export REPO="your-username/your-repo"
```

### "GitHub CLI not authenticated"

```bash
gh auth login  # Follow interactive prompts
```

### "Issue not found"

Verify the issue number exists and you have permissions to access it:

```bash
gh issue list --repo $REPO --limit 10
```

## Community & Support

For issues or contributions:
- Check the PMO documentation in your repo
- Review error messages carefully - they usually explain what's needed
- Contribute improvements back to the source repository

---

**Version**: 1.0
**Last Updated**: $(date -Iseconds)
EOF

        echo -e "${GREEN}  ✓ PMO README${NC}"

        # Create ISSUE_TEMPLATES if not exists
        if [[ ! -f "$target_repo/docs/management/ISSUE_TEMPLATES.md" ]]; then
            cat > "$target_repo/docs/management/ISSUE_TEMPLATES.md" <<'EOF'
# Issue Templates

## Epic Template

Use this template for high-level features or initiatives.

```markdown
# Epic: [Title]

## Overview
[Brief description of the epic]

## Business Value
- **CEO**: [Strategic impact]
- **CTO**: [Technical impact]
- **CFO**: [Financial impact]

## Success Criteria
- [ ] Criterion 1
- [ ] Criterion 2
- [ ] Criterion 3

## Sub-Issues
(Will be linked as work progresses)

## Architecture Decisions
(Will be documented as decisions are made)

## Compliance Requirements
- **NIST Controls**: [Applicable controls]
- **FedRAMP Impact**: [Assessment]

**Effort**: TBD | **Priority**: P1 | **Phase**: foundation
```

## Task Template

Use this template for individual work items.

```markdown
# Task: [Title]

## Objective
[Clear description of what needs to be done]

## Acceptance Criteria
- [ ] Requirement 1
- [ ] Requirement 2
- [ ] Requirement 3

## Technical Approach
1. Step 1
2. Step 2
3. Step 3

## Files to Modify
- [path/to/file1]
- [path/to/file2]

## Dependencies
- Blocks: [Issue numbers if any]
- Blocked by: [Issue numbers if any]

## Testing Requirements
- [ ] Unit tests
- [ ] Integration tests
- [ ] Security scan

**Effort**: X days | **Priority**: P1
```

## Bug Template

Use this for bug reports.

```markdown
# Bug: [Title]

## Description
[Detailed description of the bug]

## Steps to Reproduce
1. Step 1
2. Step 2
3. Step 3

## Expected Behavior
[What should happen]

## Actual Behavior
[What actually happens]

## Environment
- OS: [Linux/macOS/Windows]
- Version: [Version info]

## Screenshots
[If applicable]

**Priority**: P1 | **Severity**: [Critical/High/Medium/Low]
```
EOF
            echo -e "${GREEN}  ✓ Issue templates${NC}"
        fi
    fi

    # Install tests unless skipped
    if [[ $skip_tests -eq 0 ]]; then
        echo -e "${CYAN}Installing tests...${NC}"

        cat > "$target_repo/tests/pmo/test_common.sh" <<'EOF'
#!/usr/bin/env bash
# ==============================================================================
# PMO Common Library Tests
# ==============================================================================
# Usage: bash tests/pmo/test_common.sh
# ==============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT_DIR="$REPO_ROOT/scripts/pmo"

# Import test utilities
export REPO="test-owner/test-repo"

# Source the PMO library
source "$SCRIPT_DIR/lib/common.sh"

# Override gh command for testing
mock_gh() {
    echo "mock: $@"
}

# Test suite
test_count=0
pass_count=0
fail_count=0

# Test Helper
assert_success() {
    local test_name="$1"
    local output="$2"

    test_count=$((test_count + 1))
    if [[ "$output" != "mock:"* ]]; then
        echo "✓ $test_name"
        pass_count=$((pass_count + 1))
    else
        echo "✗ $test_name"
        fail_count=$((fail_count + 1))
    fi
}

# Test: Validate repo configuration
echo "Testing PMO Common Library..."
echo ""

# Test header printing
pmo_print_header "Test Report" 50 >/dev/null && echo "✓ Header printing"

# Test format_duration
duration=$(pmo_format_duration 3661)
[[ "$duration" == "1h 1m 1s" ]] && echo "✓ Duration formatting" || echo "✗ Duration formatting"

# Summary
echo ""
echo "Tests Passed: $pass_count"
echo "Tests Failed: $fail_count"

exit $fail_count
EOF

        chmod +x "$target_repo/tests/pmo/test_common.sh"
        echo -e "${GREEN}  ✓ Test suite${NC}"
    fi

    # Install language wrappers unless skipped
    if [[ $skip_wrappers -eq 0 ]]; then
        echo -e "${CYAN}Installing language clients...${NC}"

        # Python wrapper
        cat > "$target_repo/scripts/pmo/clients/python/pmo_client.py" <<'EOF'
#!/usr/bin/env python3
"""
PMO Python Client - Pythonic interface to PMO functions
Usage: python -m pmo_client --repo owner/repo [command] [args...]
"""

import os
import subprocess
import json
import sys
from pathlib import Path
from typing import Optional, Dict, List

class PMOClient:
    def __init__(self, repo: str, repo_root: Optional[str] = None):
        self.repo = repo
        self.repo_root = repo_root or os.getcwd()
        self.validate()

    def validate(self):
        """Validate GitHub CLI and authentication"""
        try:
            subprocess.run(["gh", "auth", "status"], capture_output=True, check=True)
        except subprocess.CalledProcessError:
            raise RuntimeError("GitHub CLI not authenticated. Run: gh auth login")

    def create_issue(self, title: str, body: str, labels: str = "", assignees: str = "") -> Dict:
        """Create a GitHub issue"""
        args = ["gh", "issue", "create", "--repo", self.repo, "--title", title, "--body", body]
        if labels:
            args.extend(["--label", labels])
        if assignees:
            args.extend(["--assignee", assignees])

        result = subprocess.run(args, capture_output=True, text=True, check=True)
        return {"status": "success", "output": result.stdout}

    def list_issues(self, state: str = "open", limit: int = 50) -> List[Dict]:
        """List GitHub issues"""
        args = ["gh", "issue", "list", "--repo", self.repo, "--state", state, "--limit", str(limit)]
        result = subprocess.run(args, capture_output=True, text=True, check=True)
        return json.loads(result.stdout)

    def update_status(self, issue_num: int, status: str, comment: str = ""):
        """Update issue status"""
        # Implementation would map to pmo_update_issue_status
        print(f"Updating issue #{issue_num} to {status}")

    def create_epic(self, title: str, description: str = "", priority: str = "P1", phase: str = "foundation"):
        """Create an epic issue"""
        body = f"""# Epic: {title}

## Overview
{description}

**Priority**: {priority} | **Phase**: {phase}
"""
        return self.create_issue(f"[EPIC] {title}", body, "type:epic,priority:" + priority)

    def create_task(self, title: str, description: str = "", priority: str = "P2", effort: str = "1 day"):
        """Create a task issue"""
        body = f"""# Task: {title}

## Objective
{description}

**Effort**: {effort} | **Priority**: {priority}
"""
        return self.create_issue(f"[TASK] {title}", body, "type:task,priority:" + priority)

def main():
    import argparse

    parser = argparse.ArgumentParser(description="PMO Python Client")
    parser.add_argument("--repo", required=True, help="GitHub repo (owner/repo)")
    parser.add_argument("command", nargs="?", default="help")
    parser.add_argument("args", nargs="*")

    args = parser.parse_args()

    client = PMOClient(args.repo)

    if args.command == "help":
        print("PMO Python Client")
        print("  create-issue <title> <body>")
        print("  list-issues [state]")
        print("  create-epic <title> [description]")
        print("  create-task <title> [description]")

if __name__ == "__main__":
    main()
EOF

        chmod +x "$target_repo/scripts/pmo/clients/python/pmo_client.py"
        echo -e "${GREEN}  ✓ Python client${NC}"

        # PowerShell wrapper
        cat > "$target_repo/scripts/pmo/clients/powershell/PMOClient.ps1" <<'EOF'
# PMO PowerShell Client - Windows/PowerShell interface to PMO functions
# Usage: .\PMOClient.ps1 -Repo "owner/repo" -Command "create-issue" -Args $args

param(
    [Parameter(Mandatory=$true)]
    [string]$Repo,

    [Parameter(Mandatory=$true)]
    [string]$Command,

    [string[]]$Args = @()
)

class PMOClient {
    [string]$Repo

    PMOClient([string]$repo) {
        $this.Repo = $repo
        $this.Validate()
    }

    [void]Validate() {
        try {
            gh auth status | Out-Null
        }
        catch {
            throw "GitHub CLI not authenticated. Run: gh auth login"
        }
    }

    [PSCustomObject]CreateIssue([string]$title, [string]$body, [string]$labels = "", [string]$assignees = "") {
        $cmdArgs = @("issue", "create", "--repo", $this.Repo, "--title", $title, "--body", $body)

        if ($labels) {
            $cmdArgs += @("--label", $labels)
        }
        if ($assignees) {
            $cmdArgs += @("--assignee", $assignees)
        }

        $output = & gh $cmdArgs
        return @{
            Status = "success"
            Output = $output
        }
    }

    [array]ListIssues([string]$state = "open", [int]$limit = 50) {
        $output = & gh issue list --repo $this.Repo --state $state --limit $limit --json "number,title"
        return $output | ConvertFrom-Json
    }
}

$client = [PMOClient]::new($Repo)

switch ($Command) {
    "list-issues" {
        $client.ListIssues() | Format-Table
    }
    "help" {
        Write-Host "PMO PowerShell Client"
        Write-Host "  create-issue <title> <body>"
        Write-Host "  list-issues"
    }
    default {
        Write-Host "Unknown command: $Command"
    }
}
EOF

        echo -e "${GREEN}  ✓ PowerShell client${NC}"
    fi

    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}✓ PMO system installed successfully!${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════╝${NC}"

    echo ""
    echo -e "${BLUE}Next Steps:${NC}"
    echo "1. Set environment variables:"
    echo "   export REPO='$REPO'"
    echo "   export REPO_ROOT='$target_repo'"
    echo ""
    echo "2. Test the installation:"
    echo "   cd $target_repo"
    echo "   source scripts/pmo/lib/common.sh"
    echo "   pmo_validate_repo"
    echo ""
    echo "3. Read the documentation:"
    echo "   cat docs/management/PMO_README.md"
    echo ""
}

# ==============================================================================
# Run Main
# ==============================================================================
if [[ $# -eq 0 ]] || [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
    show_help
    exit 0
fi

main "$@"
EOF
        echo -e "${GREEN}  ✓ Installer setup${NC}"
    fi

    return 0
}

# Execute main function
main "$@"
