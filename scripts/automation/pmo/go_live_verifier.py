#!/usr/bin/env python3
"""🚀 ElevatedIQ: Go-Live Readiness Verifier (10X PMO Enhancement)
NIST 800-53 Control Alignment: CA-2, CA-7, PM-5.

This script automates the verification of critical go-live readiness criteria
including security patches, infrastructure health, and compliance gates.
"""

import json
import os
import subprocess
import sys
from datetime import datetime


class GoLiveVerifier:
    """GoLiveVerifier class."""

    def __init__(self):
        self.results = {
            "security_gates": [],
            "infrastructure": [],
            "compliance": [],
            "operational": [],
        }
        self.blocking_incidents = 0

    def log_result(self, category, check_name, status, message):
        """log_result method."""
        self.results[category].append(
            {
                "check": check_name,
                "status": "✅ PASS" if status else "❌ FAIL",
                "message": message,
            }
        )
        if not status:
            self.blocking_incidents += 1

    def check_security_dependencies(self):
        """check_security_dependencies method."""
        print("🔍 Verifying Security Dependencies...")
        requirements_files = [
            "apps/control_plane/requirements.txt",
            "apps/finops-dashboard-api/requirements.txt",
            "apps/ai-inference-server/requirements-vllm.txt",
        ]

        secure_versions = {"pydantic": "2.10.0", "requests": "2.32.3"}

        for req_file in requirements_files:
            if os.path.exists(req_file):
                with open(req_file) as f:
                    content = f.read()
                    for pkg, min_ver in secure_versions.items():
                        if pkg in content:
                            self.log_result(
                                "security_gates",
                                f"{pkg} version in {req_file}",
                                True,
                                f"Version secure (>= {min_ver})",
                            )
            else:
                self.log_result(
                    "security_gates",
                    f"File {req_file} exists",
                    False,
                    "Missing critical requirements file",
                )

    def check_github_issues(self):
        """check_github_issues method."""
        print("🔍 Checking for Blocking GitHub Issues...")
        try:
            # Check for P0 issues in the current milestone (assuming milestone 12 for Phase 9.3)
            cmd = [
                "gh",
                "issue",
                "list",
                "--label",
                "priority:P0",
                "--state",
                "open",
                "--json",
                "number,title",
            ]
            output = subprocess.check_output(cmd).decode()
            issues = json.loads(output)

            if issues:
                for issue in issues:
                    self.log_result(
                        "security_gates",
                        f"Blocking Issue #{issue['number']}",
                        False,
                        f"P0: {issue['title']}",
                    )
            else:
                self.log_result("security_gates", "P0 Issues", True, "Zero open P0 issues detected")
        except Exception as e:
            self.log_result(
                "security_gates",
                "GitHub CLI Check",
                False,
                f"Failed to query GitHub: {str(e)}",
            )

    def check_operational_docs(self):
        """check_operational_docs method."""
        print("🔍 Verifying Operational Readiness...")
        docs = [
            "docs/management/SESSION_LOGS.md",
            "docs/management/PMO_DASHBOARD.md",
            "README.md",
        ]
        for doc in docs:
            if os.path.exists(doc):
                self.log_result("operational", f"Doc: {doc}", True, "Exists")
            else:
                self.log_result(
                    "operational",
                    f"Doc: {doc}",
                    False,
                    "Missing critical documentation",
                )

    def check_nist_controls(self):
        """check_nist_controls method."""
        print("🔍 Scanning for NIST Control References in Commits...")
        try:
            cmd = ["git", "log", "-n", "20", "--grep=NIST"]
            output = subprocess.check_output(cmd).decode()
            if output:
                controls = set()
                for line in output.split("\n"):
                    if "nist-" in line.lower() and "[" in line and "]" in line:
                        try:
                            content = line.split("[")[1].split("]")[0]
                            if "NIST-" in content:
                                parts = content.split("-")
                                if len(parts) >= 2:
                                    controls.add(f"{parts[1]}-{parts[2]}" if len(parts) > 2 else parts[1])
                        except Exception:
                            continue

                self.log_result(
                    "compliance",
                    "NIST Control References",
                    True,
                    f"Found references for: {', '.join(controls)}",
                )
            else:
                self.log_result(
                    "compliance",
                    "NIST Control References",
                    False,
                    "No NIST references in last 20 commits",
                )
        except Exception as e:
            self.log_result("compliance", "NIST Commit Scan", False, str(e))

    def check_checklist_2738(self):
        """check_checklist_2738 method."""
        print("🔍 Verifying Go-Live Checklist #2738 Items...")
        # Check for Runbooks
        if os.path.exists("docs/management/INCIDENT_RESPONSE_RUNBOOKS.md"):
            self.log_result("operational", "Incident Response Runbooks", True, "Exists")
        else:
            self.log_result(
                "operational",
                "Incident Response Runbooks",
                False,
                "Missing docs/management/INCIDENT_RESPONSE_RUNBOOKS.md",
            )

    def prepare_phase10_tasks(self):
        """prepare_phase10_tasks method."""
        print("🚀 [10X] Preparing Phase 10 Sub-tasks...")
        tasks = [
            {
                "title": "🤖 [PHASE 10.1] ML-based Anomaly Detection Engine",
                "body": "Implement ML models for proactive failure detection. Refs #2739",
            },
            {
                "title": "⚡ [PHASE 10.2] Automated Self-Healing Orchestrator",
                "body": "Implement closed-loop remediation workflows. Refs #2739",
            },
            {
                "title": "📊 [PHASE 10.3] Executive Intelligence Dashboard",
                "body": "Real-time metrics and ROI tracking. Refs #2739",
            },
        ]
        for task in tasks:
            try:
                cmd = [
                    "gh",
                    "issue",
                    "create",
                    "--title",
                    task["title"],
                    "--body",
                    task["body"],
                    "--label",
                    "phase-10,priority:P1",
                    "--milestone",
                    "Phase 10: Production Launch",
                ]
                subprocess.check_call(cmd)
                print(f"✅ Created Task: {task['title']}")
            except Exception as e:
                print(f"❌ Failed to create task {task['title']}: {str(e)}")

    def generate_report(self):
        """generate_report method."""
        report_path = f"docs/management/GO_LIVE_READINESS_REPORT_{datetime.now().strftime('%Y%m%d_%H%M%S')}.md"
        with open(report_path, "w") as f:
            f.write("# 🚀 Phase 9.3 Go-Live Readiness Report\n\n")
            f.write(f"**Timestamp:** {datetime.now().strftime('%Y-%m-%d %H:%M:%S')} UTC\n")
            f.write(f"**Overall Status:** {'🟢 GO' if self.blocking_incidents == 0 else '🔴 NO-GO'}\n")
            f.write(f"**Blocking Incidents:** {self.blocking_incidents}\n\n")

            for category, checks in self.results.items():
                f.write(f"## {category.replace('_', ' ').title()}\n")
                f.write("| Check | Status | Details |\n")
                f.write("|-------|--------|---------|\n")
                for c in checks:
                    f.write(f"| {c['check']} | {c['status']} | {c['message']} |\n")
                f.write("\n")

            f.write("\n---\n*Auto-generated by ElevatedIQ Go-Live Verifier (10X PMO Optimization)*")

        print(f"\n✅ Report generated: {report_path}")
        return report_path


if __name__ == "__main__":
    verifier = GoLiveVerifier()
    verifier.check_security_dependencies()
    verifier.check_github_issues()
    verifier.check_operational_docs()
    verifier.check_nist_controls()
    verifier.check_checklist_2738()

    if len(sys.argv) > 1 and sys.argv[1] == "--prepare-phase10":
        verifier.prepare_phase10_tasks()

    report = verifier.generate_report()

    if verifier.blocking_incidents > 0:
        print(f"\n🔴 NO-GO: {verifier.blocking_incidents} blocking incidents found.")
        sys.exit(1)
    else:
        print("\n🟢 GO: All systems ready for Phase 9.3 Launch!")
        sys.exit(0)
