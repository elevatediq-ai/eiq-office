#!/usr/bin/env python3
"""🔒 NIST-CM-3 Compliance Checker - FedRAMP High Readiness.

Purpose: Validate issue compliance with mandatory taxonomy and governance rules.
FedRAMP: CM-3 (Configuration Change Control), PM-5 (Project Management)
"""

import json
import subprocess
import sys
from pathlib import Path


class ComplianceChecker:
    """Utilities for validating and remediating GitHub issue governance."""


class ComplianceChecker:
    """ComplianceChecker class."""

    def __init__(self):
        self.repo_root = Path(__file__).parent.parent.parent
        self.required_labels = {
            "type": [
                "type: bug",
                "type: feature",
                "type: enhancement",
                "type: task",
                "type: security",
                "type: docs",
                "type: ops",
                "type: incident",
                "type: infrastructure",
                "type: epic",
            ],
            "priority": [
                "priority: P0",
                "priority: P1",
                "priority: P2",
                "priority: P3",
            ],
            "status": [
                "status: planning",
                "status: in-progress",
                "status: blocked",
                "status: review",
                "status: completed",
                "status: deprecated",
            ],
        }

    def check_issue_compliance(self, issue_number: int) -> dict[str, any]:
        """Check if an issue complies with governance rules."""
        try:
            # Get issue labels
            result = subprocess.run(
                [
                    "gh",
                    "issue",
                    "view",
                    str(issue_number),
                    "--repo",
                    "kushin77/ElevatedIQ-Mono-Repo",
                    "--json",
                    "labels",
                ],
                capture_output=True,
                text=True,
                cwd=self.repo_root,
                check=False,
            )

            if result.returncode != 0:
                return {
                    "compliant": False,
                    "errors": [f"Failed to fetch issue: {result.stderr}"],
                }

            issue_data = json.loads(result.stdout)
            labels = [label["name"] for label in issue_data.get("labels", [])]

        except Exception as exc:
            return {"compliant": False, "errors": [f"Error fetching issue: {exc}"]}

        errors = []
        warnings = []

        # Check required label categories
        for category, required_labels in self.required_labels.items():
            category_labels = [label for label in labels if label.startswith(f"{category}:")]
            if len(category_labels) == 0:
                errors.append(f"Missing {category} label (required: {', '.join(required_labels)})")
            elif len(category_labels) > 1:
                warnings.append(f"Multiple {category} labels found: {', '.join(category_labels)}")

        # Check for deprecated labels
        deprecated_labels = [
            "status-in-progress",
            "status-completed",
            "priority-p0",
            "priority-p1",
            "priority-p2",
            "priority-p3",
        ]
        for label in deprecated_labels:
            if label in labels:
                errors.append(f"Deprecated label '{label}' found - use standardized format")

        # Check for phase labels on epics
        if "type: epic" in labels:
            phase_labels = [label for label in labels if label.startswith("phase:")]
            if not phase_labels:
                warnings.append("Epic missing phase label")

        compliant = len(errors) == 0

        return {
            "compliant": compliant,
            "errors": errors,
            "warnings": warnings,
            "current_labels": labels,
        }

    def remediate_issue(self, issue_number: int, dry_run: bool = True) -> dict[str, any]:
        """Attempt to auto-remediate compliance issues."""
        compliance = self.check_issue_compliance(issue_number)

        if compliance["compliant"]:
            return {"remediated": True, "actions": []}

        actions = []

        # For missing type labels, we can't auto-determine, so just report
        # For missing priority, default to P2
        if not any(label.startswith("priority:") for label in compliance["current_labels"]):
            actions.append("Add label 'priority: P2'")

        # For missing status, default to planning
        if not any(label.startswith("status:") for label in compliance["current_labels"]):
            actions.append("Add label 'status: planning'")

        # Remove deprecated labels
        deprecated_labels = [
            "status-in-progress",
            "status-completed",
            "priority-p0",
            "priority-p1",
            "priority-p2",
            "priority-p3",
        ]
        for label in deprecated_labels:
            if label in compliance["current_labels"]:
                actions.append(f"Remove deprecated label '{label}'")

        if not dry_run and actions:
            # Apply remediation
            for action in actions:
                if action.startswith("Add label"):
                    label = action.split("'")[1]
                    subprocess.run(
                        [
                            "gh",
                            "issue",
                            "edit",
                            str(issue_number),
                            "--repo",
                            "kushin77/ElevatedIQ-Mono-Repo",
                            "--add-label",
                            label,
                        ],
                        cwd=self.repo_root,
                        check=False,
                    )
                elif action.startswith("Remove"):
                    label = action.split("'")[1]
                    subprocess.run(
                        [
                            "gh",
                            "issue",
                            "edit",
                            str(issue_number),
                            "--repo",
                            "kushin77/ElevatedIQ-Mono-Repo",
                            "--remove-label",
                            label,
                        ],
                        cwd=self.repo_root,
                        check=False,
                    )

        return {"remediated": len(actions) > 0, "actions": actions, "dry_run": dry_run}


def main():
    """Main function."""
    if len(sys.argv) < 2:
        print("Usage: python compliance_checker.py <issue_number> [--remediate]")
        sys.exit(1)

    issue_number = int(sys.argv[1])
    remediate = "--remediate" in sys.argv

    checker = ComplianceChecker()

    # Check compliance
    compliance = checker.check_issue_compliance(issue_number)

    print(f"🔒 Compliance Check for Issue #{issue_number}")
    print(f"Compliant: {'✅' if compliance['compliant'] else '❌'}")

    if compliance["errors"]:
        print("\nErrors:")
        for error in compliance["errors"]:
            print(f"  ❌ {error}")

    if compliance["warnings"]:
        print("\nWarnings:")
        for warning in compliance["warnings"]:
            print(f"  ⚠️  {warning}")

    print(f"\nCurrent Labels: {', '.join(compliance['current_labels'])}")

    # Remediate if requested
    if remediate and not compliance["compliant"]:
        print("\n🔧 Attempting Remediation...")
        remediation = checker.remediate_issue(issue_number, dry_run=False)
        if remediation["remediated"]:
            print("✅ Remediation applied:")
            for action in remediation["actions"]:
                print(f"  ✓ {action}")
        else:
            print("❌ No auto-remediation possible")


if __name__ == "__main__":
    main()
