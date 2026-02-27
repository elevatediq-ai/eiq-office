#!/usr/bin/env python3
"""🔗 Cross-System Correlation Engine (CSCE)
Part of ElevatedIQ 10X Governance Strategy.

Correlates: Git Commits -> Governance Audit (FAS) -> GitHub Issues.
NIST Controls: AU-12, AU-6, PM-5, SI-4
"""

import json
import os
import re
import subprocess
from datetime import datetime, timedelta
from typing import Any


class CrossSystemCorrelationEngine:
    """CrossSystemCorrelationEngine class."""

    def __init__(self, fas_path="logs/governance/FEDERAL_AUDIT_STREAM.log"):
        self.fas_path = fas_path
        self.repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), "../../../"))

    def _read_fas(self) -> list[dict[str, Any]]:
        if not os.path.exists(self.fas_path):
            return []
        events = []
        with open(self.fas_path) as f:
            for line in f:
                if line.strip():
                    try:
                        events.append(json.loads(line))
                    except Exception:
                        continue
        return events

    def _get_git_history(self, days=30) -> list[dict[str, str]]:
        since_date = (datetime.now() - timedelta(days=days)).strftime("%Y-%m-%d")
        cmd = [
            "git",
            "log",
            "--since",
            since_date,
            "--pretty=format:%H|%s|%an",
            "--date=iso",
        ]
        try:
            output = subprocess.check_output(cmd, cwd=self.repo_root, text=True)
            commits = []
            for line in output.strip().split("\n"):
                if not line:
                    continue
                parts = line.split("|")
                if len(parts) >= 3:
                    commits.append({"hash": parts[0], "subject": parts[1], "author": parts[2]})
            return commits
        except Exception:
            return []

    def correlate(self):
        """Correlate method."""
        self._read_fas()
        git_commits = self._get_git_history()

        # Mapping Issue Numbers to Commits and Violations
        correlation_matrix = {}

        issue_pattern = r"(?:Refs|Closes|Fixes)\s+#(\d+)"
        nist_pattern = r"\[(NIST-[A-Z]+-[0-9]+)\]"

        for commit in git_commits:
            # Extract issue mentions
            issues = re.findall(issue_pattern, commit["subject"], re.IGNORECASE)
            nist_tags = re.findall(nist_pattern, commit["subject"])

            for issue in issues:
                if issue not in correlation_matrix:
                    correlation_matrix[issue] = {
                        "issue_id": issue,
                        "commits": [],
                        "violations": [],
                        "nist_controls": set(),
                        "author": commit["author"],
                    }

                correlation_matrix[issue]["commits"].append(commit["hash"][:8])
                for tag in nist_tags:
                    correlation_matrix[issue]["nist_controls"].add(tag)

        # Re-encode sets for JSON serialization
        for issue in correlation_matrix:
            correlation_matrix[issue]["nist_controls"] = list(correlation_matrix[issue]["nist_controls"])

        return {
            "timestamp": datetime.now().isoformat(),
            "data": list(correlation_matrix.values()),
            "summary": {
                "correlated_issues": len(correlation_matrix),
                "total_tracked_commits": len(git_commits),
            },
        }


if __name__ == "__main__":
    engine = CrossSystemCorrelationEngine()
    result = engine.correlate()
    print(json.dumps(result, indent=2))
