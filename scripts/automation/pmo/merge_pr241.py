#!/usr/bin/env python3
"""PMO-Compliant PR Merge & Issue Closure Automation
Executes PR #241 merge and Issue #233 closure with full NIST audit trail.
"""

import json
import subprocess
import sys
from datetime import datetime


class PMOMergeExecutor:
    """PMOMergeExecutor class."""

    def __init__(self):
        self.repo = "kushin77/ElevatedIQ-Mono-Repo"
        self.pr_number = 241
        self.issue_number = 233
        self.timestamp = datetime.now().isoformat()
        self.operations_log = []

    def log_operation(self, op_type: str, status: str, details: str):
        """Log operation for audit trail (NIST-AU-3)."""
        entry = {
            "timestamp": datetime.now().isoformat(),
            "operation": op_type,
            "status": status,
            "details": details,
            "nist_control": "AU-3",
        }
        self.operations_log.append(entry)
        print(f"[{op_type}] {status}: {details}")

    def execute_merge(self) -> tuple[bool, str]:
        """Execute PR #241 merge with PMO-compliant message."""
        try:
            # Command to merge PR
            cmd = [
                "gh",
                "pr",
                "merge",
                str(self.pr_number),
                "--repo",
                self.repo,
                "--merge",
                "--delete-branch",
                "--auto",
            ]

            result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)

            if result.returncode == 0:
                self.log_operation("PR_MERGE", "SUCCESS", f"PR #{self.pr_number} merged to main")
                return True, result.stdout
            else:
                # If auto-merge fails, try with --yes flag
                cmd[-1] = "--yes"
                result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
                if result.returncode == 0:
                    self.log_operation(
                        "PR_MERGE",
                        "SUCCESS",
                        f"PR #{self.pr_number} merged (with --yes)",
                    )
                    return True, result.stdout
                else:
                    self.log_operation("PR_MERGE", "FAILED", f"Error: {result.stderr}")
                    return False, result.stderr

        except Exception as e:
            self.log_operation("PR_MERGE", "ERROR", str(e))
            return False, str(e)

    def close_issue(self, reason: str) -> tuple[bool, str]:
        """Close issue #233 with PMO-standard reason."""
        try:
            cmd = [
                "gh",
                "issue",
                "close",
                str(self.issue_number),
                "--repo",
                self.repo,
                "--reason",
                "completed",
            ]

            # Add comment before closing (for audit trail)
            comment_cmd = [
                "gh",
                "issue",
                "comment",
                str(self.issue_number),
                "--repo",
                self.repo,
                "--body",
                f"## Issue #233 Closed - NIST Compliant\n\n**Closure Reason**: {reason}\n**Timestamp**: {self.timestamp}\n**NIST Control**: AU-3, CM-3, CM-5\n\n---\n*Closed per PMO standards with full audit trail.*",
            ]

            # Add final comment
            result = subprocess.run(comment_cmd, capture_output=True, text=True, timeout=30)
            if result.returncode != 0:
                self.log_operation("ISSUE_COMMENT", "WARNING", f"Comment failed: {result.stderr}")

            # Close the issue
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)

            if result.returncode == 0:
                self.log_operation("ISSUE_CLOSE", "SUCCESS", f"Issue #{self.issue_number} closed")
                return True, result.stdout
            else:
                self.log_operation("ISSUE_CLOSE", "FAILED", f"Error: {result.stderr}")
                return False, result.stderr

        except Exception as e:
            self.log_operation("ISSUE_CLOSE", "ERROR", str(e))
            return False, str(e)

    def get_pr_merge_commit(self) -> str | None:
        """Retrieve merged commit SHA."""
        try:
            cmd = [
                "gh",
                "pr",
                "view",
                str(self.pr_number),
                "--repo",
                self.repo,
                "--json",
                "mergeCommit",
            ]

            result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
            if result.returncode == 0:
                data = json.loads(result.stdout)
                return data.get("mergeCommit", {}).get("oid")
            return None
        except Exception as e:
            self.log_operation("GET_COMMIT", "ERROR", str(e))
            return None

    def execute_all(self) -> bool:
        """Execute full PMO merge workflow."""
        print("\n" + "=" * 70)
        print("PMO-COMPLIANT PR MERGE & ISSUE CLOSURE")
        print("=" * 70 + "\n")

        # Step 1: Merge PR
        print("📋 Step 1: Executing PR #241 merge...")
        merge_success, merge_output = self.execute_merge()

        if not merge_success:
            print(f"❌ Merge failed. Output:\n{merge_output}")
            return False

        print("✅ PR #241 merged successfully\n")

        # Step 2: Get merge commit
        print("📋 Step 2: Retrieving merge commit SHA...")
        commit_sha = self.get_pr_merge_commit()
        if commit_sha:
            print(f"✅ Merge commit: {commit_sha[:7]}\n")
            self.log_operation("GET_COMMIT", "SUCCESS", f"Commit SHA: {commit_sha}")

        # Step 3: Close issue
        print("📋 Step 3: Closing Issue #233...")
        close_reason = f"Resolved by PR #241 merge (commit {commit_sha[:7] if commit_sha else 'unknown'})"
        close_success, close_output = self.close_issue(close_reason)

        if not close_success:
            print(f"⚠️ Issue close failed: {close_output}")
            # Don't return False - closing is secondary
        else:
            print("✅ Issue #233 closed\n")

        # Print audit trail
        print("\n" + "=" * 70)
        print("AUDIT TRAIL (NIST-AU-3)")
        print("=" * 70)
        for entry in self.operations_log:
            print(f"{entry['timestamp']}: [{entry['operation']}] {entry['status']} - {entry['details']}")

        print("\n" + "=" * 70)
        print("✅ PMO WORKFLOW COMPLETE")
        print("=" * 70 + "\n")

        return merge_success


if __name__ == "__main__":
    executor = PMOMergeExecutor()
    success = executor.execute_all()
    sys.exit(0 if success else 1)
