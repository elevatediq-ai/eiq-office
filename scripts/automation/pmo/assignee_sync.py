#!/usr/bin/env python3
"""Assignee Sync Tool - Automated Issue Assignee Update
Session: 20260212-ASSIGNEE-SYNC
Logic: For every issue, identify users who 'worked' on it (Author, Commenters, PR Authors)
and ensure they are added as assignees (limit 10).
"""

import json
import subprocess

REPO = "kushin77/ElevatedIQ-Mono-Repo"


def run_gh_command(args):
    """Run a gh command and return the JSON output."""
    cmd = ["gh"] + args + ["--repo", REPO]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"Error running {' '.join(cmd)}: {result.stderr}")
        return None
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError:
        return result.stdout


def get_issues(state="all", limit=100):
    """Get list of issues with basic info."""
    return run_gh_command(
        [
            "issue",
            "list",
            "--state",
            state,
            "--limit",
            str(limit),
            "--json",
            "number,author,assignees",
        ]
    )


def get_issue_details(number):
    """Get comments and other details for an issue."""
    return run_gh_command(["issue", "view", str(number), "--json", "comments,author,assignees"])


def update_assignees(number, assignees):
    """Update assignees for an issue."""
    if not assignees:
        return
    assignee_str = ",".join(assignees)
    subprocess.run(
        [
            "gh",
            "issue",
            "edit",
            str(number),
            "--add-assignee",
            assignee_str,
            "--repo",
            REPO,
        ]
    )


def sync_all_issues(limit=100):
    """sync_all_issues function."""
    print(f"🚀 Starting Assignee Sync for {REPO} (Limit: {limit})")
    issues = get_issues(limit=limit)
    if not issues:
        return

    for issue in issues:
        number = issue["number"]
        current_author = issue["author"]["login"]
        current_assignees = [a["login"] for a in issue["assignees"]]

        print(f"🔍 Processing #{number}...")

        details = get_issue_details(number)
        if not details:
            continue

        # Collect all users who worked on it
        worked_on_by = {current_author}
        for comment in details.get("comments", []):
            worked_on_by.add(comment["user"]["login"])

        # Filter out users who are already assignees
        to_add = worked_on_by - set(current_assignees)

        # GitHub has a limit of 10 assignees
        list(worked_on_by)[:10]

        if to_add:
            print(f"  + Adding: {', '.join(to_add)}")
            update_assignees(number, list(to_add))
        else:
            print("  ✓ Already synced")


if __name__ == "__main__":
    import sys

    limit = 100
    if len(sys.argv) > 1:
        limit = int(sys.argv[1])
    sync_all_issues(limit)
