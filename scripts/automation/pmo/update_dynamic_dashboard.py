#!/usr/bin/env python3
"""##############################################################################
# Dynamic Dashboard Updater
# Purpose: Inject real-time telemetry into the PMO_DASHBOARD.md
# FedRAMP: [NIST-SI-4] Information System Monitoring
# Workstream: Phase 2 - Dashboard 10X Automation (#3486).
##############################################################################
"""

import json
import os

DASHBOARD_PATH = "docs/management/PMO_DASHBOARD.md"
TELEMETRY_PATH = "docs/management/telemetry/pmo_state.json"


def format_telemetry(data):
    """Format JSON telemetry into Markdown snippets."""
    ts = data.get("timestamp", "N/A")
    status = data.get("status", "Idle")
    m = data.get("metrics", {})

    status_emoji = "🟢 ACTIVE" if status == "Active" else "⚪ IDLE"

    return f"""
### 📊 REAL-TIME TELEMETRY (Auto-Generated)
- **Status:** {status_emoji}
- **Open Issues:** {m.get("open_issues", 0)}
- **Commits Today:** {m.get("commits_today", 0)}
- **Last Sync:** {ts}
"""


def main():
    """Main function."""
    if not os.path.exists(TELEMETRY_PATH):
        print("❌ Telemetry file not found.")
        return

    with open(TELEMETRY_PATH) as f:
        data = json.load(f)

    if not os.path.exists(DASHBOARD_PATH):
        print("❌ Dashboard file not found.")
        return

    with open(DASHBOARD_PATH) as f:
        lines = f.readlines()

    # Find the telemetry marker or append at the end of the header
    new_content = []
    found_marker = False

    telemetry_block = format_telemetry(data)

    for line in lines:
        if "### 📊 REAL-TIME TELEMETRY" in line:
            found_marker = True
            new_content.append(telemetry_block)
            continue

        # Skip lines until next section if we are in the telemetry block
        if found_marker and line.startswith("- **"):
            continue

        new_content.append(line)

    if not found_marker:
        # Insert after the main header
        for i, line in enumerate(new_content):
            if "# 📊 ELITE PMO DASHBOARD" in line:
                new_content.insert(i + 1, "\n" + telemetry_block + "\n---\n")
                break

    with open(DASHBOARD_PATH, "w") as f:
        f.writelines(new_content)

    print(f"✅ Dashboard updated with latest telemetry (Status: {data.get('status')})")


if __name__ == "__main__":
    main()
