#!/usr/bin/env python3
"""Elite PMO ROI Engine - Phase 2 Advanced Automation
Calculates the Return on Investment for engineering efforts.
"""

import json
import subprocess
from datetime import UTC, datetime, timedelta

REPO = "kushin77/ElevatedIQ-Mono-Repo"


def get_closed_issues_count(days=30):
    """get_closed_issues_count function."""
    try:
        # Get count of issues closed in the last X days
        since = (datetime.now(UTC) - timedelta(days=days)).isoformat()
        cmd = [
            "gh",
            "issue",
            "list",
            "--repo",
            REPO,
            "--state",
            "closed",
            "--limit",
            "1000",
            "--json",
            "closedAt",
        ]
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        issues = json.loads(result.stdout)

        count = 0
        since_dt = datetime.fromisoformat(since)
        for issue in issues:
            if issue["closedAt"]:
                closed_at = datetime.fromisoformat(issue["closedAt"].replace("Z", "+00:00"))
                if closed_at > since_dt:
                    count += 1
        return count
    except Exception as e:
        print(f"Error fetching issues: {e}")
        return 0


def estimate_infrastructure_cost():
    """estimate_infrastructure_cost function."""
    # Mock cost estimation based on active terraform modules
    # In a real scenario, this would pull from GCP Billing API
    try:
        # Simple heuristic: count occurrences of "google_compute_instance" in terraform files
        cmd = ["grep", "-r", "google_compute_instance", "terraform/", "--include=*.tf"]
        result = subprocess.run(cmd, capture_output=True, text=True)
        instance_count = result.stdout.count('resource "google_compute_instance"')

        # Base cost $50/instance/month + $500 for platform services
        monthly_cost = (instance_count * 50) + 500
        return monthly_cost
    except Exception:
        return 1200  # Default if grep fails


def calculate_roi():
    """calculate_roi function."""
    issues_30d = get_closed_issues_count(30)
    monthly_cost = estimate_infrastructure_cost()

    if issues_30d == 0:
        cost_per_issue = monthly_cost
    else:
        cost_per_issue = monthly_cost / issues_30d

    # ROI Score: (Issues Closed / Cost) * 1000
    roi_score = (issues_30d / max(monthly_cost, 1)) * 1000

    return issues_30d, monthly_cost, cost_per_issue, roi_score


def main():
    """Main function."""
    issues, cost, cpi, score = calculate_roi()

    print("### 💰 Engineering ROI Analysis (Last 30 Days)")
    print("| Metric | Value | Insights |")
    print("|--------|-------|----------|")
    print(f"| Features/Fixes Delivered | {issues} | Total throughput |")
    print(f"| Est. Infrastructure Cost | ${cost:,.2f} | Monthly burn |")
    print(f"| Cost per Delivery | ${cpi:,.2f} | Efficiency metric |")
    print(f"| **ROI Efficiency Score** | **{score:.2f}** | Throughput/Cost Index |")


if __name__ == "__main__":
    main()
