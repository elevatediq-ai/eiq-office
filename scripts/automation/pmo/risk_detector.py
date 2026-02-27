#!/usr/bin/env python3
"""Elite PMO Risk Detector - Phase 2 Advanced Automation
Scans for P0 issues that are stale, blocked, or have high aging.
"""

import json
import subprocess
import sys
from datetime import UTC, datetime


def get_issues():
    """get_issues function."""
    try:
        cmd = [
            "gh",
            "issue",
            "list",
            "--repo",
            "kushin77/ElevatedIQ-Mono-Repo",
            "--state",
            "open",
            "--json",
            "number,title,labels,updatedAt,createdAt",
        ]
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        return json.loads(result.stdout)
    except Exception as e:
        print(f"Error fetching issues: {e}", file=sys.stderr)
        return []


def analyze_risks(issues):
    """analyze_risks function."""
    risks = []
    now = datetime.now(UTC)

    for issue in issues:
        labels = [l["name"] for l in issue["labels"]]
        updated_at = datetime.fromisoformat(issue["updatedAt"].replace("Z", "+00:00"))
        created_at = datetime.fromisoformat(issue["createdAt"].replace("Z", "+00:00"))

        age_days = (now - created_at).days
        stale_days = (now - updated_at).days

        # Risk 1: Stale P0
        if "priority: P0" in labels and stale_days > 2:
            risks.append(
                {
                    "issue": f"#{issue['number']}",
                    "title": issue["title"],
                    "risk_type": "🔴 STALE P0",
                    "days": stale_days,
                    "impact": "CRITICAL",
                }
            )

        # Risk 2: Aging P1
        if "priority: P1" in labels and age_days > 7:
            risks.append(
                {
                    "issue": f"#{issue['number']}",
                    "title": issue["title"],
                    "risk_type": "🟡 AGING P1",
                    "days": age_days,
                    "impact": "MEDIUM",
                }
            )

        # Risk 3: Blocked
        if "status: blocked" in labels:
            risks.append(
                {
                    "issue": f"#{issue['number']}",
                    "title": issue["title"],
                    "risk_type": "🚧 BLOCKED",
                    "days": stale_days,
                    "impact": "HIGH",
                }
            )

    return risks


def main():
    """Main function."""
    issues = get_issues()
    risks = analyze_risks(issues)

    if not risks:
        print("✅ No critical PMO risks detected.")
        return

    print("### ⚠️ Active PMO Risks")
    print("| Issue | Title | Risk Type | Aging | Impact |")
    print("|-------|-------|-----------|-------|--------|")
    for r in risks:
        print(f"| {r['issue']} | {r['title']} | {r['risk_type']} | {r['days']}d | {r['impact']} |")


if __name__ == "__main__":
    main()
