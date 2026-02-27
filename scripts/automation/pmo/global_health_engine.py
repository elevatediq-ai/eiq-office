#!/usr/bin/env python3
import json
import subprocess
from datetime import datetime

# Path Config
CONFIG_PATH = "configs/pmo/governance.json"
REPO = "kushin77/ElevatedIQ-Mono-Repo"
OUTPUT_REPORT = "docs/management/GLOBAL_HEALTH_REPORT.md"


def load_config():
    """load_config function."""
    with open(CONFIG_PATH) as f:
        return json.load(f)


def run_gh_command(args):
    """run_gh_command function."""
    try:
        result = subprocess.check_output(["gh"] + args, text=True)
        return json.loads(result)
    except Exception as e:
        print(f"Error running gh command: {e}")
        return []


def calculate_health():
    """calculate_health function."""
    config = load_config()
    weights = config["weights"]

    print("🚀 Fetching Issue Inventory...")
    # Get all active issues (limit 1000 for safety)
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
            "number,state,assignees,milestone,labels,updatedAt",
        ]
    )

    open_issues = [i for i in issues if i["state"] == "OPEN"]
    total_open = len(open_issues)

    if total_open == 0:
        return 100, {"message": "No open issues found."}

    # 1. Assignee Coverage
    assigned = len([i for i in open_issues if i["assignees"]])
    assignee_score = (assigned / total_open) * 100

    # 2. Milestone Coverage
    milestoned = len([i for i in open_issues if i["milestone"]])
    milestone_score = (milestoned / total_open) * 100

    # 3. Label Compliance
    required = config["labels"]["required_categories"]
    compliant_labels = 0
    for issue in open_issues:
        categories_found = set()
        for label in issue["labels"]:
            name = label["name"].lower()
            for req in required:
                if req in name:
                    categories_found.add(req)
        if len(categories_found) >= len(required):
            compliant_labels += 1
    label_score = (compliant_labels / total_open) * 100

    # 4. Staleness
    stale_days = config["thresholds"]["stale_days"]
    now = datetime.now()
    non_stale = 0
    for issue in open_issues:
        updated_at = datetime.fromisoformat(issue["updatedAt"].replace("Z", "+00:00"))
        days_since = (now.replace(tzinfo=updated_at.tzinfo) - updated_at).days
        if days_since <= stale_days:
            non_stale += 1
    stale_score = (non_stale / total_open) * 100

    # Final Weighted Calculation
    global_score = (
        (assignee_score * weights["assignee_coverage"])
        + (milestone_score * weights["milestone_coverage"])
        + (label_score * weights["label_compliance"])
        + (stale_score * weights["staleness_penalty"])
    )

    report_data = {
        "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S UTC"),
        "global_score": round(global_score, 2),
        "total_open": total_open,
        "metrics": {
            "assignee_coverage": {"score": round(assignee_score, 2), "count": assigned},
            "milestone_coverage": {
                "score": round(milestone_score, 2),
                "count": milestoned,
            },
            "label_compliance": {
                "score": round(label_score, 2),
                "count": compliant_labels,
            },
            "staleness_index": {"score": round(stale_score, 2), "count": non_stale},
        },
    }

    return report_data


def generate_markdown(data):
    """generate_markdown function."""
    # Color logic
    score = data["global_score"]
    color = "green" if score >= 90 else "yellow" if score >= 70 else "red"

    md = f"""# 🌏 Global PMO Governance Health Report

**Status:** ![#{color}](https://via.placeholder.com/15/{color}/000000?text=+) **{score}% HEALTHY**
**Generated:** {data["timestamp"]}
**Governance Version:** 2.0.0 (10X Enhanced)

---

## 📈 Executive Summary

The Global Workspace Health Score (GWHS) is a weighted calculation of all active work items against NIST-800-53 and FedRAMP governance standards.

| Metric | Score | Status |
| :--- | :--- | :--- |
| **Global Health Score** | **{score}%** | {"✅ Pass" if score >= 85 else "⚠️ Warning" if score >= 70 else "🚨 Critical"} |
| Total Open Issues | {data["total_open"]} | Active Workload |

---

## 🔬 Sub-Metric Analytics

### 1. Assignee Coverage ({data["metrics"]["assignee_coverage"]["score"]}%)
- **Target:** 100%
- **Actual:** {data["metrics"]["assignee_coverage"]["count"]} / {data["total_open"]}
- **Status:** {"✅ Optimized" if data["metrics"]["assignee_coverage"]["score"] > 95 else "🔧 Automating"}

### 2. Milestone Alignment ({data["metrics"]["milestone_coverage"]["score"]}%)
- **Target:** 100%
- **Actual:** {data["metrics"]["milestone_coverage"]["count"]} / {data["total_open"]}
- **Status:** {"✅ Aligned" if data["metrics"]["milestone_coverage"]["score"] > 90 else "⚠️ Significant Drift"}

### 3. Label Compliance ({data["metrics"]["label_compliance"]["score"]}%)
- **Target:** 100% (Type, Priority, Phase required)
- **Actual:** {data["metrics"]["label_compliance"]["count"]} / {data["total_open"]}
- **Status:** {"✅ Governed" if data["metrics"]["label_compliance"]["score"] > 90 else "🚨 metadata leakage detected"}

### 4. Continuous Velocity / Staleness ({data["metrics"]["staleness_index"]["score"]}%)
- **Target:** <14 days activity
- **Actual:** {data["metrics"]["staleness_index"]["count"]} / {data["total_open"]} update frequency
- **Status:** {"✅ Fluid" if data["metrics"]["staleness_index"]["score"] > 80 else "🐌 Stagnation detected"}

---

## 🛡️ NIST 800-53 Control Mapping
- **PM-5**: System Inventory (Issue Tracking)
- **CM-3**: Configuration Change Control (Labeling & State)
- **AC-2**: Account Management (Assignee Control)

---

_Produced by ElevatedIQ 10X Governance Engine_
"""
    with open(OUTPUT_REPORT, "w") as f:
        f.write(md)
    print(f"✅ Global Health Report generated at {OUTPUT_REPORT}")


if __name__ == "__main__":
    data = calculate_health()
    generate_markdown(data)
