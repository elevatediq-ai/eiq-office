#!/usr/bin/env python3
import json
import os
import subprocess
import sys
from datetime import UTC, datetime


def run_command(cmd, cwd=None):
    """run_command function."""
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True, cwd=cwd)
        return result.returncode == 0, result.stdout.strip(), result.stderr.strip()
    except Exception as e:
        return False, "", str(e)


def get_repo_root():
    """get_repo_root function."""
    # Get the absolute path to the repo root
    script_dir = os.path.dirname(os.path.abspath(__file__))
    return os.path.dirname(os.path.dirname(script_dir))  # Go up two levels from scripts/pmo


def check_aws_readiness(repo_root):
    """check_aws_readiness function."""
    print("Checking AWS Terraform (WS1-VPC-Peering)...")
    aws_dir = os.path.join(repo_root, "infra", "phase-6.3", "ws1-vpc-peering")
    success, stdout, stderr = run_command("terraform plan -lock=false -no-color", cwd=aws_dir)
    if "Plan: " in stdout:
        return (
            True,
            "✅ AWS Plan generated successfully (Resources: " + stdout.split("Plan: ")[1].split(".")[0] + ")",
        )
    if "No changes." in stdout:
        return True, "✅ AWS Infrastructure is already IN-SYNC (No changes needed)"
    return False, "❌ AWS Plan failed or has blockers: " + stderr


def check_gcp_readiness(repo_root):
    """check_gcp_readiness function."""
    print("Checking GCP Terraform Validation...")
    # Cloud Functions
    gcp_dir = os.path.join(repo_root, "infra", "phase-6.3", "gcp", "cloud-functions")
    success, _, stderr = run_command("terraform validate", cwd=gcp_dir)
    if not success:
        return False, "❌ GCP Cloud Functions validation failed: " + stderr
    return True, "✅ GCP Cloud Functions validation PASSED"


def check_github_assignments():
    """check_github_assignments function."""
    print("Checking GitHub Issue Assignments...")
    success, stdout, stderr = run_command(
        "gh issue list --repo kushin77/ElevatedIQ-Mono-Repo --json number,assignees --state open"
    )
    if not success:
        return False, "❌ GitHub CLI error: " + stderr
    issues = json.loads(stdout)
    unassigned = [i["number"] for i in issues if not i["assignees"]]
    if unassigned:
        return False, f"❌ Unassigned critical issues found: {unassigned}"
    return True, "✅ All open issues have assignees (100% Personnel Readiness)"


def main():
    """Main function."""
    print("🚀 ElevatedIQ: Phase 6.3 Technical Readiness Gate")
    print("=" * 60)

    repo_root = get_repo_root()

    report = {"timestamp": datetime.now(UTC).isoformat() + "Z", "checks": []}

    checks = [
        ("AWS Infrastructure Planning", lambda: check_aws_readiness(repo_root)),
        ("GCP Service Validation", lambda: check_gcp_readiness(repo_root)),
        ("Personnel Assignment Compliance", check_github_assignments),
    ]

    all_passed = True
    for name, func in checks:
        passed, msg = func()
        report["checks"].append({"name": name, "passed": passed, "message": msg})
        print(msg)
        if not passed:
            all_passed = False

    status = "GO" if all_passed else "NO-GO"
    print("\n" + "=" * 60)
    print(f"🏁 FINAL STATUS: {status}")
    print("=" * 60)

    with open("phase_6_3_readiness_gate.json", "w") as f:
        json.dump(report, f, indent=2)
    print("\nReport saved to: phase_6_3_readiness_gate.json")

    if not all_passed:
        sys.exit(1)


if __name__ == "__main__":
    main()
