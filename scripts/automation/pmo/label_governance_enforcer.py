#!/usr/bin/env python3
import json
import subprocess

CONFIG_PATH = "configs/pmo/governance.json"
REPO = "kushin77/ElevatedIQ-Mono-Repo"


def load_config():
    """load_config function."""
    with open(CONFIG_PATH) as f:
        return json.load(f)


def run_gh_command(args, is_search=False):
    """run_gh_command function."""
    try:
        if is_search:
            result = subprocess.check_output(["gh"] + args, text=True)
            return json.loads(result)
        else:
            subprocess.check_call(["gh"] + args)
            return True
    except Exception as e:
        print(f"Error: {e}")
        return None


def get_open_milestones():
    """Fetch open milestones using GitHub API."""
    try:
        result = subprocess.check_output(
            [
                "gh",
                "api",
                f"repos/{REPO}/milestones",
                "--jq",
                '.[] | select(.state=="open") | .title',
            ],
            text=True,
        )
        return result.strip().split("\n") if result.strip() else []
    except Exception as e:
        print(f"Error fetching milestones: {e}")
        return []


def enforce_governance():
    """enforce_governance function."""
    config = load_config()
    required = config["labels"]["required_categories"]
    defaults = config["labels"]["defaults"]
    milestone_req = config["thresholds"]["milestone_required"]

    print("🔖 Starting Governance Scan (Labels & Milestones)...")
    print("📋 Scanning: Open + Closed issues (all states)")

    # Scan ALL issues (open + closed)
    issues = run_gh_command(
        [
            "issue",
            "list",
            "--repo",
            REPO,
            "--state",
            "all",
            "--limit",
            "1000",
            "--json",
            "number,state,labels,milestone",
        ],
        is_search=True,
    )

    # Get default milestone once
    if milestone_req and not hasattr(enforce_governance, "_default_milestone"):
        open_milestones = get_open_milestones()
        enforce_governance._default_milestone = open_milestones[0] if open_milestones else "Project Eta: Backlog"

    remediated_count = 0
    for issue in issues:
        num = issue["number"]
        state = issue.get("state", "open")
        labels = [l["name"].lower() for l in issue["labels"]]
        missing_labels = []

        # 1. Label Check
        for req in required:
            found = False
            for label in labels:
                if req in label:
                    found = True
                    break
            if not found:
                missing_labels.append(defaults[req])

        # 2. Milestone Check
        update_args = []
        if missing_labels:
            update_args.extend(["--add-label", ",".join(missing_labels)])

        if milestone_req and not issue["milestone"]:
            default_milestone = getattr(enforce_governance, "_default_milestone", "Project Eta: Backlog")
            state_badge = f"[{state.upper()}] " if state == "closed" else ""
            print(f"📍 Milestone Remediation for #{num} {state_badge}: Setting to '{default_milestone}'")
            update_args.extend(["--milestone", default_milestone])

        if update_args:
            print(f"🔧 Remediation for #{num}: {update_args}")
            if run_gh_command(["issue", "edit", str(num), "--repo", REPO] + update_args):
                remediated_count += 1

    print(f"✅ Governance Enforcement Complete! {remediated_count} issues remediated.")


if __name__ == "__main__":
    enforce_governance()
    print("✅ Governance Enforcement (Open + Closed Issues) Complete.")
