#!/usr/bin/env python3
"""##############################################################################
# Elite PMO Dashboard Telemetry Daemon
# Purpose: Real-time collection of PMO metrics for auto-refreshing dashboard
# FedRAMP: [NIST-SI-4] Information System Monitoring
# Workstream: Phase 2 - Dashboard 10X Automation (#3486).
##############################################################################
"""

import json
import os
import subprocess
import time
from datetime import datetime

# ============================================================================
# CONFIGURATION
# ============================================================================

TELEMETRY_PATH = "docs/management/telemetry/pmo_state.json"
PMO_DASHBOARD_PATH = "docs/management/PMO_DASHBOARD.md"
SESSION_LOGS_PATH = "docs/management/SESSION_LOGS.md"
# RCA-FIX 2026-02-26: Changed from 5s to 300s (5 min).
# 5s fired 720 `gh issue list` + 720 `git rev-list` subprocesses/hour,
# hammering CPU and hitting GitHub rate limits. 5 min is sufficient for PMO dashboards.
REFRESH_INTERVAL = 300  # Seconds — was 5, see RCA: docs/ops/RCA_VSCODE_RECONNECT_2026-02-26.md

# ============================================================================
# METRICS COLLECTION
# ============================================================================


def get_issue_metrics():
    """Extract metrics from GitHub CLI."""
    try:
        # Get count of open issues
        result = subprocess.run(
            [
                "gh",
                "issue",
                "list",
                "--repo",
                "kushin77/ElevatedIQ-Mono-Repo",
                "--state",
                "open",
                "--json",
                "number",
            ],
            capture_output=True,
            text=True,
        )
        if result.returncode == 0:
            issues = json.loads(result.stdout)
            return len(issues)
    except Exception:
        return 0
    return 0


def get_git_metrics():
    """Extract metrics from git history."""
    try:
        # Get commit count for the day
        result = subprocess.run(
            ["git", "rev-list", "--count", "HEAD", "--since='midnight'"],
            capture_output=True,
            text=True,
        )
        if result.returncode == 0:
            return int(result.stdout.strip())
    except Exception:
        return 0
    return 0


def get_session_status():
    """Check if a session is currently active."""
    if os.path.exists(SESSION_LOGS_PATH):
        with open(SESSION_LOGS_PATH) as f:
            content = f.read()
            if "Status: Active" in content or "Status: In-Progress" in content:
                return "Active"
    return "Idle"


# ============================================================================
# MAIN LOOP
# ============================================================================


def main():
    """Main function."""
    print(f"🚀 PMO Telemetry Daemon started (Interval: {REFRESH_INTERVAL}s)")
    os.makedirs(os.path.dirname(TELEMETRY_PATH), exist_ok=True)

    while True:
        try:
            state = {
                "timestamp": datetime.utcnow().isoformat(),
                "status": get_session_status(),
                "metrics": {
                    "open_issues": get_issue_metrics(),
                    "commits_today": get_git_metrics(),
                    "last_refresh": time.time(),
                },
                "alerts": [],
            }

            with open(TELEMETRY_PATH, "w") as f:
                json.dump(state, f, indent=2)

            # print(f"[{state['timestamp']}] Telemetry updated.")

        except Exception as e:
            print(f"Error during telemetry update: {e}")

        time.sleep(REFRESH_INTERVAL)


if __name__ == "__main__":
    main()
