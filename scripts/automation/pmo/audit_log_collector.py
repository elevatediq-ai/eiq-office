#!/usr/bin/env python3
"""🚀 ElevatedIQ: NIST AU-2 Audit Log Collector
Consolidates session logs, git activity, and issue updates into a compliant audit trail.
Aligned with FedRAMP High and NIST 800-53 standards.
"""

import json
import os
import re
import subprocess
from datetime import datetime, timedelta

# Configuration
REPO_ROOT = "/home/akushnir/ElevatedIQ-Mono-Repo"
OUTPUT_DIR = os.path.join(REPO_ROOT, "docs/compliance/audit_trail")
SESSION_LOGS = os.path.join(REPO_ROOT, "docs/management/SESSION_LOGS.md")
COMPLIANCE_DIR = os.path.join(REPO_ROOT, "docs/compliance")


class AuditLogCollector:
    """AuditLogCollector class."""

    def __init__(self):
        self.audit_trail = []
        os.makedirs(OUTPUT_DIR, exist_ok=True)

    def _run_cmd(self, cmd: list) -> str:
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, check=True, cwd=REPO_ROOT)
            return result.stdout.strip()
        except Exception as e:
            return f"Error: {e}"

    def collect_git_logs(self, days=1):
        """Collects git commit history for auditing [NIST-AU-2]."""
        since = (datetime.now() - timedelta(days=days)).isoformat()
        logs = self._run_cmd(["git", "log", "--since", since, "--pretty=format:%h|%an|%ad|%s"])

        for line in logs.split("\n"):
            if not line:
                continue
            parts = line.split("|")
            if len(parts) >= 4:
                self.audit_trail.append(
                    {
                        "timestamp": parts[2],
                        "type": "GIT_COMMIT",
                        "actor": parts[1],
                        "id": parts[0],
                        "message": parts[3],
                        "control": "NIST-CM-3",
                    }
                )

    def collect_session_logs(self):
        """Parses SESSION_LOGS.md for recent activities [NIST-AU-2]."""
        if not os.path.exists(SESSION_LOGS):
            return

        with open(SESSION_LOGS) as f:
            content = f.read()

        # Simple regex to find session entries
        # Looking for timestamps in SESSION_LOGS.md
        matches = re.findall(r"(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})", content)
        for ts in matches:
            self.audit_trail.append(
                {
                    "timestamp": ts,
                    "type": "SESSION_MARKER",
                    "actor": "Copilot",
                    "message": "Session activity logged",
                    "control": "NIST-AU-2",
                }
            )

    def collect_github_activity(self):
        """Collects recent issue/PR activity via gh CLI [NIST-AU-2]."""
        issues_json = self._run_cmd(
            [
                "gh",
                "issue",
                "list",
                "--repo",
                "kushin77/ElevatedIQ-Mono-Repo",
                "--state",
                "all",
                "--json",
                "number,title,updatedAt,author",
                "--limit",
                "20",
            ]
        )
        try:
            issues = json.loads(issues_json)
            for issue in issues:
                self.audit_trail.append(
                    {
                        "timestamp": issue["updatedAt"],
                        "type": "GITHUB_ISSUE",
                        "actor": (issue["author"]["login"] if issue.get("author") else "unknown"),
                        "id": str(issue["number"]),
                        "message": f"Issue Activity: {issue['title']}",
                        "control": "NIST-PM-5",
                    }
                )
        except Exception as e:
            print(f"GH Error: {e}")

    def export(self):
        """Exports the consolidated audit trail to JSON and Markdown."""
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        json_file = os.path.join(OUTPUT_DIR, f"audit_trail_{timestamp}.json")
        md_file = os.path.join(OUTPUT_DIR, f"audit_trail_{timestamp}.md")
        latest_json = os.path.join(COMPLIANCE_DIR, "audit_trail_latest.json")

        self.audit_trail.sort(key=lambda x: x["timestamp"], reverse=True)

        with open(json_file, "w") as f:
            json.dump(self.audit_trail, f, indent=2)

        with open(latest_json, "w") as f:
            json.dump(self.audit_trail, f, indent=2)

        with open(md_file, "w") as f:
            f.write("# 🛡️ NIST AU-2 Consolidated Audit Trail\n")
            f.write(f"Generated: {datetime.now().isoformat()}\n\n")
            f.write("| Timestamp | Type | Actor | Message | NIST Control |\n")
            f.write("|-----------|------|-------|---------|--------------|\n")
            for entry in self.audit_trail[:100]:
                f.write(
                    f"| {entry['timestamp']} | {entry['type']} | {entry['actor']} | {entry['message']} | {entry['control']} |\n"
                )

        return md_file


if __name__ == "__main__":
    collector = AuditLogCollector()
    collector.collect_git_logs()
    collector.collect_session_logs()
    collector.collect_github_activity()
    report_path = collector.export()
    print(f"✅ Audit trail consolidated: {report_path}")
