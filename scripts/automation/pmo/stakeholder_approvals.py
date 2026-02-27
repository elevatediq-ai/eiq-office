#!/usr/bin/env python3
"""ElevatedIQ Stakeholder Approval Checklist Generator
Phase 4.4 Week 3: Security Validation & Testing.

This script generates stakeholder approval checklists and tracks approval status
for go-live readiness assessment.

Usage:
    python scripts/pmo/stakeholder_approvals.py --generate --phase golive

Requirements:
    - PyYAML
    - requests
"""

import argparse
import json
import logging
import sys
from datetime import datetime

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s",
    handlers=[
        logging.FileHandler("logs/pmo/stakeholder_approvals.log"),
        logging.StreamHandler(sys.stdout),
    ],
)
logger = logging.getLogger(__name__)


class StakeholderApprovalManager:
    """Manages stakeholder approvals for ElevatedIQ go-live readiness."""

    def __init__(self):
        self.stakeholders = {
            "engineering": {
                "name": "Engineering Team",
                "contacts": ["lead-engineer@elevatediq.com", "devops@elevatediq.com"],
                "approvals_required": [
                    "code_review_completed",
                    "unit_tests_passed",
                    "integration_tests_passed",
                    "performance_tests_passed",
                    "security_scan_clean",
                    "infrastructure_provisioned",
                    "monitoring_configured",
                ],
            },
            "security": {
                "name": "Security Team",
                "contacts": ["ciso@elevatediq.com", "security-lead@elevatediq.com"],
                "approvals_required": [
                    "penetration_test_completed",
                    "vulnerability_assessment_done",
                    "nist_compliance_verified",
                    "access_controls_reviewed",
                    "encryption_implemented",
                    "incident_response_ready",
                    "security_monitoring_active",
                ],
            },
            "operations": {
                "name": "Operations Team",
                "contacts": ["ops-lead@elevatediq.com", "sre@elevatediq.com"],
                "approvals_required": [
                    "infrastructure_monitoring_setup",
                    "backup_procedures_tested",
                    "disaster_recovery_tested",
                    "runbooks_documented",
                    "oncall_rotation_established",
                    "capacity_planning_done",
                    "rollback_procedures_ready",
                ],
            },
            "business": {
                "name": "Business Stakeholders",
                "contacts": [
                    "product-owner@elevatediq.com",
                    "business-lead@elevatediq.com",
                ],
                "approvals_required": [
                    "requirements_validated",
                    "user_acceptance_testing_done",
                    "business_continuity_reviewed",
                    "compliance_requirements_met",
                    "go_live_schedule_approved",
                    "communication_plan_ready",
                    "success_metrics_defined",
                ],
            },
        }

    def generate_checklist(self, phase: str = "golive") -> dict:
        """Generate stakeholder approval checklist."""
        logger.info(f"Generating stakeholder approval checklist for phase: {phase}")

        checklist = {
            "generated_at": datetime.utcnow().isoformat(),
            "phase": phase,
            "version": "1.0",
            "stakeholders": {},
            "summary": {},
            "next_steps": [],
        }

        for stakeholder_key, stakeholder_info in self.stakeholders.items():
            checklist["stakeholders"][stakeholder_key] = {
                "name": stakeholder_info["name"],
                "contacts": stakeholder_info["contacts"],
                "approvals_required": stakeholder_info["approvals_required"],
                "approval_status": {approval: "pending" for approval in stakeholder_info["approvals_required"]},
                "approved_by": None,
                "approved_at": None,
                "comments": "",
                "overall_status": "pending",
            }

        checklist["summary"] = self._calculate_summary(checklist)
        checklist["next_steps"] = self._generate_next_steps(checklist)

        return checklist

    def update_approval(
        self,
        checklist: dict,
        stakeholder: str,
        approval_item: str,
        status: str,
        approved_by: str | None = None,
        comments: str | None = None,
    ) -> dict:
        """Update approval status for a specific item."""
        if stakeholder not in checklist["stakeholders"]:
            raise ValueError(f"Unknown stakeholder: {stakeholder}")

        stakeholder_data = checklist["stakeholders"][stakeholder]

        if approval_item not in stakeholder_data["approvals_required"]:
            raise ValueError(f"Unknown approval item: {approval_item}")

        # Update approval status
        stakeholder_data["approval_status"][approval_item] = status

        # Update overall stakeholder status
        all_approved = all(s == "approved" for s in stakeholder_data["approval_status"].values())
        any_rejected = any(s == "rejected" for s in stakeholder_data["approval_status"].values())

        if any_rejected:
            stakeholder_data["overall_status"] = "rejected"
        elif all_approved:
            stakeholder_data["overall_status"] = "approved"
            if approved_by:
                stakeholder_data["approved_by"] = approved_by
                stakeholder_data["approved_at"] = datetime.utcnow().isoformat()
        else:
            stakeholder_data["overall_status"] = "pending"

        if comments:
            stakeholder_data["comments"] = comments

        # Update summary
        checklist["summary"] = self._calculate_summary(checklist)
        checklist["next_steps"] = self._generate_next_steps(checklist)
        checklist["last_updated"] = datetime.utcnow().isoformat()

        logger.info(f"Updated {stakeholder} approval for {approval_item} to {status}")
        return checklist

    def validate_checklist(self, checklist: dict) -> dict:
        """Validate checklist completeness and generate validation report."""
        validation = {
            "is_valid": True,
            "issues": [],
            "recommendations": [],
            "readiness_score": 0,
        }

        # Check if all stakeholders have provided approvals
        approved_stakeholders = 0
        total_stakeholders = len(checklist["stakeholders"])

        for stakeholder_key, stakeholder_data in checklist["stakeholders"].items():
            if stakeholder_data["overall_status"] == "approved":
                approved_stakeholders += 1
            elif stakeholder_data["overall_status"] == "rejected":
                validation["issues"].append(f"{stakeholder_data['name']} has rejected approvals")
                validation["is_valid"] = False

        # Calculate readiness score
        validation["readiness_score"] = (approved_stakeholders / total_stakeholders) * 100

        # Check for critical security approvals
        security_approved = checklist["stakeholders"]["security"]["overall_status"] == "approved"
        if not security_approved:
            validation["issues"].append("Security team approval is required for go-live")
            validation["is_valid"] = False
            validation["recommendations"].append("Complete security validation and obtain security team approval")

        # Check for engineering completeness
        engineering_approved = checklist["stakeholders"]["engineering"]["overall_status"] == "approved"
        if not engineering_approved:
            validation["issues"].append("Engineering team approval is required for go-live")
            validation["is_valid"] = False
            validation["recommendations"].append("Complete all engineering validations and testing")

        # Readiness thresholds
        if validation["readiness_score"] < 75:
            validation["recommendations"].append("Overall readiness is below 75%. Address outstanding approvals.")
        elif validation["readiness_score"] >= 100:
            validation["recommendations"].append("All approvals received. System is ready for go-live.")

        return validation

    def _calculate_summary(self, checklist: dict) -> dict:
        """Calculate approval summary."""
        summary = {
            "total_stakeholders": len(checklist["stakeholders"]),
            "approved_stakeholders": 0,
            "pending_stakeholders": 0,
            "rejected_stakeholders": 0,
            "total_approvals_required": 0,
            "total_approvals_given": 0,
            "overall_completion_percentage": 0,
        }

        for stakeholder_data in checklist["stakeholders"].values():
            if stakeholder_data["overall_status"] == "approved":
                summary["approved_stakeholders"] += 1
            elif stakeholder_data["overall_status"] == "rejected":
                summary["rejected_stakeholders"] += 1
            else:
                summary["pending_stakeholders"] += 1

            summary["total_approvals_required"] += len(stakeholder_data["approvals_required"])
            summary["total_approvals_given"] += sum(
                1 for s in stakeholder_data["approval_status"].values() if s == "approved"
            )

        if summary["total_approvals_required"] > 0:
            summary["overall_completion_percentage"] = (
                summary["total_approvals_given"] / summary["total_approvals_required"]
            ) * 100

        return summary

    def _generate_next_steps(self, checklist: dict) -> list[str]:
        """Generate next steps based on current approval status."""
        next_steps = []

        # Check for blocked stakeholders
        for stakeholder_key, stakeholder_data in checklist["stakeholders"].items():
            if stakeholder_data["overall_status"] == "rejected":
                next_steps.append(f"Address {stakeholder_data['name']} concerns and re-submit for approval")
            elif stakeholder_data["overall_status"] == "pending":
                pending_items = [
                    item for item, status in stakeholder_data["approval_status"].items() if status == "pending"
                ]
                if pending_items:
                    next_steps.append(
                        f"Complete {stakeholder_data['name']} approvals: {', '.join(pending_items[:3])}{'...' if len(pending_items) > 3 else ''}"
                    )

        # Overall readiness
        summary = checklist.get("summary", {})
        completion_pct = summary.get("overall_completion_percentage", 0)

        if completion_pct >= 100:
            next_steps.append("All approvals received. Proceed with go-live preparation.")
        elif completion_pct >= 75:
            next_steps.append("Most approvals received. Focus on remaining critical items.")
        else:
            next_steps.append("Significant approvals pending. Prioritize security and engineering sign-offs.")

        # Phase-specific next steps
        phase = checklist.get("phase", "golive")
        if phase == "golive":
            if summary.get("approved_stakeholders", 0) == summary.get("total_stakeholders", 0):
                next_steps.append("Schedule go-live date and prepare final deployment checklist.")
            else:
                next_steps.append("Continue stakeholder reviews and address any concerns.")

        return next_steps


def main():  # noqa: PLR0912,PLR0915
    """Main function."""
    parser = argparse.ArgumentParser(description="Stakeholder Approval Management")
    parser.add_argument("--generate", action="store_true", help="Generate new approval checklist")
    parser.add_argument(
        "--update",
        nargs=4,
        metavar=("STAKEHOLDER", "ITEM", "STATUS", "APPROVED_BY"),
        help="Update approval status: stakeholder item status approved_by",
    )
    parser.add_argument("--validate", action="store_true", help="Validate current checklist")
    parser.add_argument("--phase", default="golive", help="Phase for checklist generation")
    parser.add_argument(
        "--input",
        default="docs/pmo/stakeholder_approvals.json",
        help="Input checklist file",
    )
    parser.add_argument(
        "--output",
        default="docs/pmo/stakeholder_approvals.json",
        help="Output checklist file",
    )
    parser.add_argument("--verbose", action="store_true", help="Verbose output")

    args = parser.parse_args()

    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)

    manager = StakeholderApprovalManager()

    # Create output directory
    import os

    os.makedirs(os.path.dirname(args.output), exist_ok=True)

    if args.generate:
        # Generate new checklist
        checklist = manager.generate_checklist(args.phase)

        with open(args.output, "w") as f:
            json.dump(checklist, f, indent=2)

        print(f"✅ Generated stakeholder approval checklist for phase '{args.phase}'")
        print(f"📄 Saved to: {args.output}")

    elif args.update:
        # Load existing checklist
        if not os.path.exists(args.input):
            print(f"❌ Input file not found: {args.input}")
            sys.exit(1)

        with open(args.input) as f:
            checklist = json.load(f)

        # Update approval
        stakeholder, item, status, approved_by = args.update
        checklist = manager.update_approval(checklist, stakeholder, item, status, approved_by)

        # Save updated checklist
        with open(args.output, "w") as f:
            json.dump(checklist, f, indent=2)

        print(f"✅ Updated {stakeholder} approval for '{item}' to '{status}'")

    elif args.validate:
        # Load and validate checklist
        if not os.path.exists(args.input):
            print(f"❌ Input file not found: {args.input}")
            sys.exit(1)

        with open(args.input) as f:
            checklist = json.load(f)

        validation = manager.validate_checklist(checklist)

        print(f"\n{'=' * 60}")
        print("STAKEHOLDER APPROVAL VALIDATION REPORT")
        print(f"{'=' * 60}")
        print(f"Phase: {checklist.get('phase', 'unknown')}")
        print(f"Readiness Score: {validation['readiness_score']:.1f}%")
        print(f"Valid for Go-Live: {'✅ YES' if validation['is_valid'] else '❌ NO'}")
        print()

        if validation["issues"]:
            print("ISSUES FOUND:")
            for issue in validation["issues"]:
                print(f"  ❌ {issue}")
            print()

        if validation["recommendations"]:
            print("RECOMMENDATIONS:")
            for rec in validation["recommendations"]:
                print(f"  💡 {rec}")
            print()

        summary = checklist.get("summary", {})
        print("APPROVAL SUMMARY:")
        print(
            f"  Stakeholders: {summary.get('approved_stakeholders', 0)}/{summary.get('total_stakeholders', 0)} approved"
        )
        print(
            f"  Individual Approvals: {summary.get('total_approvals_given', 0)}/{summary.get('total_approvals_required', 0)} completed"
        )
        print(f"  Overall Completion: {summary.get('overall_completion_percentage', 0):.1f}%")
        print(f"{'=' * 60}")

        if not validation["is_valid"]:
            sys.exit(1)

    # Display current status
    elif os.path.exists(args.input):
        with open(args.input) as f:
            checklist = json.load(f)

        summary = checklist.get("summary", {})
        print(f"\n{'=' * 50}")
        print("CURRENT STAKEHOLDER APPROVAL STATUS")
        print(f"{'=' * 50}")
        print(f"Phase: {checklist.get('phase', 'unknown')}")
        print(f"Generated: {checklist.get('generated_at', 'unknown')}")
        print(f"Last Updated: {checklist.get('last_updated', 'never')}")
        print()
        print("STAKEHOLDER STATUS:")
        for stakeholder_key, stakeholder_data in checklist["stakeholders"].items():
            status_icon = {"approved": "✅", "rejected": "❌", "pending": "⏳"}[stakeholder_data["overall_status"]]
            print(f"  {status_icon} {stakeholder_data['name']}: {stakeholder_data['overall_status']}")
            if stakeholder_data["overall_status"] == "approved":
                print(f"      Approved by: {stakeholder_data.get('approved_by', 'unknown')}")
                print(f"      At: {stakeholder_data.get('approved_at', 'unknown')}")
        print()
        print("OVERALL SUMMARY:")
        print(f"  Completion: {summary.get('overall_completion_percentage', 0):.1f}%")
        print(
            f"  Approved Stakeholders: {summary.get('approved_stakeholders', 0)}/{summary.get('total_stakeholders', 0)}"
        )
        print(f"{'=' * 50}")

        next_steps = checklist.get("next_steps", [])
        if next_steps:
            print("NEXT STEPS:")
            for step in next_steps:
                print(f"  • {step}")
            print(f"{'=' * 50}")
    else:
        print(f"❌ No checklist found at: {args.input}")
        print("💡 Use --generate to create a new checklist")


if __name__ == "__main__":
    main()
