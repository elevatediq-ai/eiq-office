#!/usr/bin/env python3
"""🚀 Developer Governance Profiles (DGP) V1
Part of ElevatedIQ 10X Governance Strategy: Enhancement #8.

Implements Behavioral Analytics for developer contributions to identify
risk patterns, excellence metrics, and NIST-PM-5 (Security Authorization).
"""

import json
import subprocess
from typing import Any


class DeveloperGovernanceProfiles:
    """DeveloperGovernanceProfiles class."""

    def __init__(self, repo_path: str = "."):
        self.repo_path = repo_path
        self.nist_pattern = r"\[NIST-[A-Z]{2,3}-\d+\]"

    def _get_git_log(self, limit: int = 500) -> list[dict[str, Any]]:
        """Fetch git logs with author and subject info."""
        format_str = "%H|%an|%ae|%at|%s"
        cmd = ["git", "log", f"-n {limit}", f"--pretty=format:{format_str}"]
        try:
            output = subprocess.check_output(cmd, encoding="utf-8")
            commits = []
            for line in output.strip().split("\n"):
                if not line:
                    continue
                parts = line.split("|", 4)
                if len(parts) == 5:
                    commits.append(
                        {
                            "hash": parts[0],
                            "author": parts[1],
                            "email": parts[2],
                            "timestamp": int(parts[3]),
                            "subject": parts[4],
                        }
                    )
            return commits
        except Exception:
            return []

    def analyze_profiles(self) -> dict[str, Any]:
        """analyze_profiles method."""
        commits = self._get_git_log()
        profiles = {}

        for commit in commits:
            author = commit["author"]
            if author not in profiles:
                profiles[author] = {
                    "total_commits": 0,
                    "nist_compliance_count": 0,
                    "subjects": [],
                    "latest_activity": 0,
                    "risk_score": 0.0,
                    "excellence_tier": "N/A",
                }

            p = profiles[author]
            p["total_commits"] += 1
            import re

            if re.search(self.nist_pattern, commit["subject"]):
                p["nist_compliance_count"] += 1

            p["subjects"].append(commit["subject"])
            p["latest_activity"] = max(p["latest_activity"], commit["timestamp"])

        # Finalize Metrics
        for author, p in profiles.items():
            # Compliance Rate
            compliance_rate = (p["nist_compliance_count"] / p["total_commits"]) * 100 if p["total_commits"] > 0 else 0
            p["compliance_rate"] = round(compliance_rate, 2)

            # Risk Scoring (Inverse of compliance + activity decay)
            p["risk_score"] = round(100 - compliance_rate, 2)

            # Excellence Tiers (NIST-PM-5 aligned)
            if compliance_rate >= 95:
                p["excellence_tier"] = "🥇 Arch-Governance Elite"
            elif compliance_rate >= 80:
                p["excellence_tier"] = "🥈 FedRAMP Compliant"
            elif compliance_rate >= 50:
                p["excellence_tier"] = "🥉 Governance Practitioner"
            else:
                p["excellence_tier"] = "⚠️ Training Required"

        return profiles


if __name__ == "__main__":
    dgp = DeveloperGovernanceProfiles()
    results = dgp.analyze_profiles()

    # Check for --json flag or output to stdout
    print(json.dumps(results, indent=2))
