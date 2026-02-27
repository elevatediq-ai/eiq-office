#!/usr/bin/env python3
"""Elite PMO Predictive Velocity Engine - Phase 2 Advanced Automation
Calculates issue closure velocity and forecasts sprint completion.
"""

import json
import subprocess
from datetime import UTC, datetime, timedelta

REPO = "kushin77/ElevatedIQ-Mono-Repo"
# Target Launch for Project Beta
LAUNCH_DATE = datetime(2026, 3, 1, 0, 0, 0, tzinfo=UTC)


def fetch_issue_data():
    """fetch_issue_data function."""
    try:
        cmd = [
            "gh",
            "issue",
            "list",
            "--repo",
            REPO,
            "--state",
            "all",
            "--limit",
            "100",
            "--json",
            "number,state,createdAt,closedAt,labels",
        ]
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        return json.loads(result.stdout)
    except Exception as e:
        print(f"Error: {e}")
        return []


def calculate_velocity(issues):
    """calculate_velocity function."""
    closed_last_7d = []
    now = datetime.now(UTC)
    one_week_ago = now - timedelta(days=7)

    total_ttc_seconds = 0
    closed_count = 0

    for issue in issues:
        if issue["state"] == "CLOSED" and issue["closedAt"]:
            closed_at = datetime.fromisoformat(issue["closedAt"].replace("Z", "+00:00"))
            created_at = datetime.fromisoformat(issue["createdAt"].replace("Z", "+00:00"))

            if closed_at > one_week_ago:
                closed_last_7d.append(issue)
                ttc = (closed_at - created_at).total_seconds()
                total_ttc_seconds += ttc
                closed_count += 1

    avg_ttc_hours = (total_ttc_seconds / closed_count / 3600) if closed_count > 0 else 0
    issues_per_day = closed_count / 7

    return issues_per_day, avg_ttc_hours


def forecast(issues, issues_per_day):
    """Forecast function."""
    open_issues = [i for i in issues if i["state"] == "OPEN"]
    num_open = len(open_issues)

    now = datetime.now(UTC)
    hours_to_launch = (LAUNCH_DATE - now).total_seconds() / 3600
    days_to_launch = hours_to_launch / 24

    projected_closures = issues_per_day * days_to_launch

    risk_level = "🟢 LOW"
    if num_open > projected_closures:
        risk_level = "🔴 HIGH"
    elif num_open > projected_closures * 0.8:
        risk_level = "🟡 MEDIUM"

    return num_open, projected_closures, risk_level, hours_to_launch


def main():
    """Main function."""
    issues = fetch_issue_data()
    if not issues:
        print("No issue data found.")
        return

    velocity, avg_ttc = calculate_velocity(issues)
    num_open, projected, risk, hours = forecast(issues, velocity)

    print("### 🔮 Predictive Velocity Insights")
    print("| Metric | Value | Breakdown |")
    print("|--------|-------|-----------|")
    print(f"| Issue Velocity | {velocity:.1f} issues/day | Based on last 7 days |")
    print(f"| Avg. Time to Close | {avg_ttc:.1f} hours | Efficiency metric |")
    print(f"| Open Backlog | {num_open} issues | Remaining tasks |")
    print(f"| Launch Countdown | {hours:.1f} hours | T-Minus |")

    # NIST AU-2: Log insights to PMO Audit Database
    try:
        import sys
        from pathlib import Path

        repo_root = Path(__file__).parent.parent.parent.parent.parent
        db_script = repo_root / "scripts/pmo/lib/db.py"
        env_file = repo_root / ".pmo/current_session.env"

        session_id = "ANALYTICS-VELOCITY"
        if env_file.exists():
            with open(env_file) as f:
                for line in f:
                    if line.startswith('SESSION_ID='):
                        session_id = line.split('=')[1].strip().strip('"')

        msg = f"[VELOCITY] Issues/Day: {velocity:.1f} | Risk: {risk} | Countdown: {hours:.1f}h"

        if db_script.exists():
            subprocess.run([sys.executable, str(db_script), "update", "--session-id", session_id, "--type", "decision", "--message", msg], check=True)
    except Exception as e:
        print(f"Failed to log to DB: {e}")
    print(f"| Projected Closures | {projected:.1f} issues | Capacity till launch |")
    print(f"| **Launch Risk** | **{risk}** | Capacity vs Backlog |")


if __name__ == "__main__":
    main()
