#!/usr/bin/env python3
"""📊 Compliance Scorecard & SLA Tracker
Part of ElevatedIQ 10X Governance Strategy.

Tracks remediation SLAs (NIST CM-3, CM-5) and provides team-level scorecards.
"""

import json
import os
from datetime import datetime


class ComplianceScorecard:
    """ComplianceScorecard class."""

    def __init__(self, issue_db="logs/governance/governance_issues.json"):
        self.issue_db = issue_db
        self.slas = {"P0": 24, "P1": 72, "P2": 168}  # hours

    def _load_issues(self):
        if not os.path.exists("logs/governance"):
            os.makedirs("logs/governance")
        if not os.path.exists(self.issue_db):
            return []
        with open(self.issue_db) as f:
            return json.load(f)

    def generate_scorecard(self):
        """generate_scorecard method."""
        issues = self._load_issues()
        now = datetime.now()

        report = {
            "generated_at": now.isoformat(),
            "summary": {
                "total_violations": len(issues),
                "breached_slas": 0,
                "avg_remediation_time_hrs": 0,
            },
            "team_performance": {},
            "priority_distribution": {"P0": 0, "P1": 0, "P2": 0},
        }

        remediation_times = []

        for issue in issues:
            priority = issue.get("priority", "P2")
            report["priority_distribution"][priority] += 1

            created_at = datetime.fromisoformat(issue["created_at"])

            if issue.get("resolved_at"):
                resolved_at = datetime.fromisoformat(issue["resolved_at"])
                duration = (resolved_at - created_at).total_seconds() / 3600
                remediation_times.append(duration)
            else:
                # Check for SLA breach
                age = (now - created_at).total_seconds() / 3600
                if age > self.slas.get(priority, 168):
                    report["summary"]["breached_slas"] += 1

        if remediation_times:
            report["summary"]["avg_remediation_time_hrs"] = round(sum(remediation_times) / len(remediation_times), 2)

        return report


if __name__ == "__main__":
    tracker = ComplianceScorecard()
    print(json.dumps(tracker.generate_scorecard(), indent=2))
