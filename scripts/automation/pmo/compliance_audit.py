#!/usr/bin/env python3
"""Elite PMO Compliance Auditor
Purpose: Scans GitHub issues for NIST 800-53 control mappings.
FedRAMP: CA-7 (Continuous Monitoring), PM-5 (Information Security Program).
"""

import json
import re
import subprocess

# Configuration
REPO = "kushin77/ElevatedIQ-Mono-Repo"
NIST_PATTERN = r"\[NIST-[A-Z]{2}-[0-9]+\]"


def get_open_issues():
    """get_open_issues function."""
    try:
        cmd = [
            "gh",
            "issue",
            "list",
            "--repo",
            REPO,
            "--state",
            "open",
            "--limit",
            "100",
            "--json",
            "number,title,body,labels",
        ]
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        return json.loads(result.stdout)
    except Exception as e:
        print(f"Error fetching issues: {e}")
        return []


def audit_compliance():
    """audit_compliance function."""
    issues = get_open_issues()
    if not issues:
        print("No issues found to audit.")
        return

    print(f"🔍 Auditing {len(issues)} issues for NIST 800-53 compliance mapping...")
    print("-" * 60)

    compliant_count = 0
    missing_count = 0

    for issue in issues:
        num = issue["number"]
        title = issue["title"]
        body = issue["body"] or ""

        # Check title or body for NIST pattern
        has_nist = re.search(NIST_PATTERN, title) or re.search(NIST_PATTERN, body)

        if has_nist:
            compliant_count += 1
            # print(f"✅ #{num} - Compliant")
        else:
            # Skip some types like documentation or sessions if they don't require NIST mapping
            labels = [l["name"].lower() for l in issue["labels"]]
            if any(l in labels for l in ["documentation", "pmo", "session"]):
                continue

            missing_count += 1
            print(f"❌ #{num} - MISSING NIST MAPPING: {title}")

    print("-" * 60)
    print("Audit Summary:")
    print(f"  Compliant: {compliant_count}")
    print(f"  Missing:   {missing_count}")
    print(
        f"  Accuracy:  {(compliant_count / (compliant_count + missing_count) * 100):.1f}%"
        if (compliant_count + missing_count) > 0
        else "N/A"
    )


if __name__ == "__main__":
    audit_compliance()
