#!/usr/bin/env python3
"""🚀 Predictive Governance Engine (PGE) V2
Part of ElevatedIQ 10X Governance Strategy.

Analyzes temporal and behavioral patterns to forecast compliance risks.
NIST Controls: AU-2, AU-3, PM-5, SI-4
"""

import json
import re
import subprocess
from datetime import datetime
from typing import Any


class PredictiveGovernanceEngine:
    """PredictiveGovernanceEngine class."""

    def __init__(self, repo_path: str = "."):
        self.repo_path = repo_path
        # Use refined patterns from POLICIES.gpl
        self.patterns = {
            "nist_tag": r"\[NIST-[A-Z]{2,3}-\d+\]",
            "conventional": r"^(feat|fix|chore|docs|test|refactor|style|security)\(.+\):",
        }

    def _run_git_command(self, args: list[str]) -> str:
        try:
            result = subprocess.run(
                ["git"] + args,
                cwd=self.repo_path,
                capture_output=True,
                text=True,
                check=True,
            )
            return result.stdout
        except Exception:
            return ""

    def get_history(self, days: int = 90) -> list[dict[str, Any]]:
        """get_history method."""
        format_str = "%H|%an|%ai|%s"
        output = self._run_git_command(["log", f"--since={days}.days.ago", f"--pretty=format:{format_str}"])

        commits = []
        for line in output.strip().split("\n"):
            if not line:
                continue
            parts = line.split("|", 3)
            if len(parts) >= 4:
                commits.append(
                    {
                        "hash": parts[0],
                        "author": parts[1],
                        "date": datetime.fromisoformat(parts[2]),
                        "subject": parts[3],
                    }
                )
        return commits

    def analyze_risk(self) -> dict[str, Any]:
        """analyze_risk method."""
        commits = self.get_history()
        if not commits:
            return {"status": "NO_DATA"}

        stats = {
            "total_commits": len(commits),
            "violations": 0,
            "temporal_risk": {"days": [0] * 7, "hours": [0] * 24},
            "author_risk": {},
            "author_total": {},
        }

        for c in commits:
            has_nist = bool(re.search(self.patterns["nist_tag"], c["subject"]))
            has_conv = bool(re.search(self.patterns["conventional"], c["subject"]))

            author = c["author"]
            stats["author_total"][author] = stats["author_total"].get(author, 0) + 1

            if not has_nist or not has_conv:
                stats["violations"] += 1
                dt = c["date"]
                stats["temporal_risk"]["days"][dt.weekday()] += 1
                stats["temporal_risk"]["hours"][dt.hour] += 1
                stats["author_risk"][author] = stats["author_risk"].get(author, 0) + 1

        return self._generate_forecast(stats)

    def _generate_forecast(self, stats: dict[str, Any]) -> dict[str, Any]:
        # Identify High Risk Windows
        days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        max_day_idx = stats["temporal_risk"]["days"].index(max(stats["temporal_risk"]["days"]))
        max_hour = stats["temporal_risk"]["hours"].index(max(stats["temporal_risk"]["hours"]))

        # Identify At-Risk Authors (Ratio of violations to total commits)
        reliability = {}
        for author, total in stats["author_total"].items():
            viols = stats["author_risk"].get(author, 0)
            score = round((1 - (viols / total)) * 100, 2)
            reliability[author] = score

        forecast = {
            "timestamp": datetime.now().isoformat(),
            "metrics": {
                "overall_compliance_rate": round(100 - (stats["violations"] / stats["total_commits"] * 100), 2),
                "high_risk_day": days[max_day_idx],
                "high_risk_hour": f"{max_hour}:00",
                "predicted_violation_probability_next_24h": self._calc_prob(stats),
            },
            "author_reliability_scores": dict(sorted(reliability.items(), key=lambda x: x[1])[:5]),  # Bottom 5
            "recommendations": [
                f"Increase automated scanning during {days[max_day_idx]} peak hours ({max_hour}:00).",
                "Target sub-80% reliability authors for automated policy training.",
            ],
        }
        return forecast

    def _calc_prob(self, stats: dict[str, Any]) -> float:
        # Simple heuristic: violation rate modified by current time context
        now = datetime.now()
        base_rate = stats["violations"] / stats["total_commits"]
        hour_factor = (
            (stats["temporal_risk"]["hours"][now.hour] / max(stats["temporal_risk"]["hours"]))
            if max(stats["temporal_risk"]["hours"]) > 0
            else 1
        )
        return round(min(base_rate * hour_factor * 1.5, 1.0) * 100, 2)


if __name__ == "__main__":
    pge = PredictiveGovernanceEngine()
    forecast = pge.analyze_risk()
    print(json.dumps(forecast, indent=2))
