#!/usr/bin/env python3
"""📊 Governance Debt Tracker (GDT)
Part of ElevatedIQ 10X Governance Strategy.

Analyzes git history, identifies non-compliant commits (using Policy Engine),
and calculates a "Compliance Debt Score" for the repository.
NIST Controls: AU-2, AU-6, AU-12, PM-5
"""

import importlib.util
import json
import os
import subprocess
from datetime import datetime, timedelta

# Adjust path to include the enhancements dir
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))


def load_policy_engine():
    """load_policy_engine function."""
    module_name = "policy_engine"
    file_path = os.path.join(SCRIPT_DIR, "05_policy_engine.py")
    spec = importlib.util.spec_from_file_location(module_name, file_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.PolicyEngine


PolicyEngine = load_policy_engine()


class GovernanceDebtTracker:
    """GovernanceDebtTracker class."""

    def __init__(self, days=30):
        self.days = days
        self.engine = PolicyEngine()
        self.repo_root = os.path.abspath(os.path.join(SCRIPT_DIR, "../../../"))
        self.report_dir = os.path.join(self.repo_root, "docs/management/governance_reports")

    def _get_git_log(self) -> list[dict[str, str]]:
        since_date = (datetime.now() - timedelta(days=self.days)).strftime("%Y-%m-%d")
        cmd = [
            "git",
            "log",
            "--since",
            since_date,
            "--pretty=format:%H|%an|%ad|%s",
            "--date=iso",
        ]
        try:
            output = subprocess.check_output(cmd, cwd=self.repo_root, text=True)
            commits = []
            for line in output.strip().split("\n"):
                if not line:
                    continue
                parts = line.split("|")
                if len(parts) >= 4:
                    commits.append(
                        {
                            "hash": parts[0],
                            "author": parts[1],
                            "date": parts[2],
                            "subject": parts[3],
                        }
                    )
            return commits
        except Exception:
            return []

    def calculate_debt(self):
        """calculate_debt method."""
        commits = self._get_git_log()
        if not commits:
            return {
                "summary": "NO_COMMITS",
                "score": 0,
                "total_commits": 0,
                "violations": 0,
            }

        total_violations = 0
        severity_weights = {"CRITICAL": 10, "HIGH": 5, "MEDIUM": 2, "LOW": 1}
        debt_score = 0
        violation_details = []

        for commit in commits:
            violations = self.engine.validate_text(commit["subject"], "git.commit.message")
            if violations:
                total_violations += 1
                commit_debt = 0
                for v in violations:
                    weight = severity_weights.get(v.get("severity", "LOW"), 1)
                    commit_debt += weight

                debt_score += commit_debt
                violation_details.append(
                    {
                        "hash": commit["hash"][:8],
                        "author": commit["author"],
                        "violations": len(violations),
                        "debt": commit_debt,
                    }
                )

        norm_score = round((debt_score / len(commits)) * 10, 2) if commits else 0

        report = {
            "timestamp": datetime.now().isoformat(),
            "period_days": self.days,
            "total_commits": len(commits),
            "compliant_commits": len(commits) - total_violations,
            "violation_rate_pct": (round((total_violations / len(commits)) * 100, 2) if commits else 0),
            "raw_debt_score": debt_score,
            "governance_risk_index": norm_score,
            "top_violators": self._get_top_violators(violation_details),
            "summary": self._get_status_label(norm_score),
        }

        self._save_report(report)
        return report

    def _get_top_violators(self, details: list[dict]) -> list[dict]:
        authors = {}
        for d in details:
            authors[d["author"]] = authors.get(d["author"], 0) + 1
        return sorted(
            [{"author": k, "violations": v} for k, v in authors.items()],
            key=lambda x: x["violations"],
            reverse=True,
        )[:5]

    def _get_status_label(self, score) -> str:
        if score < 5:
            return "✅ EXCELLENT (Elite Governance)"
        if score < 15:
            return "⚖️ STABLE (Minor Governance Drift)"
        if score < 30:
            return "⚠️ WARNING (Significant Compliance Debt)"
        return "🚨 CRITICAL (Governance Failure - Immediate Remediation Required)"

    def _save_report(self, report):
        os.makedirs(self.report_dir, exist_ok=True)
        filename = f"GOVERNANCE_DEBT_{datetime.now().strftime('%Y%m%d')}.json"
        with open(os.path.join(self.report_dir, filename), "w") as f:
            json.dump(report, f, indent=2)


if __name__ == "__main__":
    tracker = GovernanceDebtTracker(days=30)
    result = tracker.calculate_debt()
    print(json.dumps(result, indent=2))
