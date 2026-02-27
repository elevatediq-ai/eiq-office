#!/usr/bin/env python3
##############################################################################
# 🔥 Ruthless 10X Metrics Generator - Topic Coherence Reporting
# Purpose: Analyze 1000+ issues for topic coherence, identify misalignments
# Generates: Comprehensive metrics report, actionable insights, quality KPIs
# Session: 20260218-10X-MILESTONE-ENFORCER
# Issue: #3460
# FedRAMP: [NIST-PM-5] Project Management with automated governance
# Usage: python3 ruthless_10x_metrics_generator.py [--scan-closed] [--output report.md]
##############################################################################

import argparse
import json
import os
import subprocess
import sys
from collections import defaultdict
from dataclasses import asdict, dataclass
from datetime import datetime
from typing import Any

# Add parent directory to path
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, SCRIPT_DIR)

from milestone_rules_engine import MilestoneRulesEngine
from topic_coherence_validator import TopicCoherenceValidator


@dataclass
class CoherenceResult:
    """Result of coherence analysis for a single issue."""

    issue_number: int
    title: str
    current_milestone: str
    current_milestone_id: int
    coherence_score: float
    is_coherent: bool
    recommendation: str
    alternative_milestone: str = None

    def to_dict(self):
        """to_dict method."""
        return asdict(self)


@dataclass
class MilestoneMetrics:
    """Aggregated metrics for a single milestone."""

    milestone_id: int
    milestone_title: str
    total_issues: int
    coherent_issues: int
    incoherent_issues: int
    avg_coherence_score: float
    coherence_percentage: float
    recommended_reassignments: int

    def to_dict(self):
        """to_dict method."""
        return asdict(self)


class RuthlessMetricsGenerator:
    """RuthlessMetricsGenerator class."""

    def __init__(self, repo: str = "kushin77/ElevatedIQ-Mono-Repo"):
        self.repo = repo
        self.coherence_validator = TopicCoherenceValidator()
        self.rules_engine = MilestoneRulesEngine()
        self.results: list[CoherenceResult] = []
        self.milestone_metrics: dict[int, MilestoneMetrics] = {}

    def scan_all_issues(self, include_closed: bool = False) -> tuple[int, list[dict[str, Any]]]:
        """Fetch all issues from GitHub."""
        print(f"🔍 Scanning all {'open & closed' if include_closed else 'open'} issues from {self.repo}...")

        all_issues = []

        # Query both states or just open
        states = ["open"]
        if include_closed:
            states.append("closed")

        for state in states:
            try:
                # Use simpler gh issue list command
                cmd = [
                    "gh",
                    "issue",
                    "list",
                    "--repo",
                    self.repo,
                    "--state",
                    state,
                    "--limit",
                    "500",
                    "--json",
                    "number,title,body,labels,milestone",
                ]

                output = subprocess.check_output(cmd, stderr=subprocess.PIPE, text=True)
                if not output.strip():
                    print(f"  No {state} issues found")
                    continue

                issues_data = json.loads(output)

                for issue in issues_data:
                    # Transform to expected format
                    transformed = {
                        "number": issue["number"],
                        "title": issue.get("title", ""),
                        "body": issue.get("body", ""),
                        "labels": [l["name"] for l in issue.get("labels", [])],
                        "current_milestone": (issue["milestone"]["number"] if issue.get("milestone") else None),
                        "current_milestone_title": (issue["milestone"]["title"] if issue.get("milestone") else None),
                        "state": state,
                    }
                    all_issues.append(transformed)

                print(f"  Found {len(issues_data)} {state} issues")

            except subprocess.CalledProcessError as e:
                print(f"  Error fetching {state} issues: {e}")
                continue
            except json.JSONDecodeError as e:
                print(f"  Error parsing JSON: {e}")
                continue

        print(f"✅ Found {len(all_issues)} total issues\n")
        return len(all_issues), all_issues

    def analyze_coherence(self, issues: list[dict[str, Any]]) -> None:
        """Analyze topic coherence for all issues."""
        print(f"📊 Analyzing topic coherence for {len(issues)} issues...")

        for i, issue in enumerate(issues, 1):
            if (i - 1) % 50 == 0:
                print(f"   Progress: {i}/{len(issues)} ({(i / len(issues) * 100):.1f}%)")

            if not issue.get("current_milestone"):
                # Skip issues without milestone for this analysis
                continue

            try:
                # Validate coherence
                validator_input = {
                    "number": issue["number"],
                    "title": issue["title"],
                    "body": issue.get("body", ""),
                    "labels": issue.get("labels", []),
                    "current_milestone_id": issue["current_milestone"],
                    "current_milestone_title": issue.get("current_milestone_title", "Unknown"),
                }

                coherence_result = self.coherence_validator.validate_coherence(validator_input)

                result = CoherenceResult(
                    issue_number=issue["number"],
                    title=issue["title"][:80],  # Truncate for display
                    current_milestone=issue.get("current_milestone_title", "Unknown"),
                    current_milestone_id=issue["current_milestone"],
                    coherence_score=coherence_result["coherence_score"],
                    is_coherent=coherence_result["is_coherent"],
                    recommendation=coherence_result["recommendation"]["action"],
                    alternative_milestone=coherence_result["recommendation"]["alternative_milestone"],
                )

                self.results.append(result)

            except Exception as e:
                print(f"⚠️  Error analyzing issue #{issue['number']}: {e}")
                continue

        print(f"✅ Analysis complete: {len(self.results)} issues analyzed\n")

    def generate_metrics(self) -> dict[str, Any]:
        """Aggregate metrics across all results."""
        print("📈 Generating aggregate metrics...")

        if not self.results:
            return {"error": "No results to aggregate"}

        # Aggregate by milestone
        by_milestone = defaultdict(list)
        for result in self.results:
            by_milestone[result.current_milestone_id].append(result)

        # Calculate milestone-level metrics
        total_coherent = 0
        total_incoherent = 0
        total_reassign = 0
        coherence_scores = []

        for milestone_id, milestone_results in by_milestone.items():
            milestone_title = milestone_results[0].current_milestone

            coherent_count = sum(1 for r in milestone_results if r.is_coherent)
            incoherent_count = len(milestone_results) - coherent_count
            reassign_count = sum(1 for r in milestone_results if r.recommendation in ["review", "reassign"])

            avg_score = sum(r.coherence_score for r in milestone_results) / len(milestone_results)
            coherence_pct = (coherent_count / len(milestone_results)) * 100

            metrics = MilestoneMetrics(
                milestone_id=milestone_id,
                milestone_title=milestone_title,
                total_issues=len(milestone_results),
                coherent_issues=coherent_count,
                incoherent_issues=incoherent_count,
                avg_coherence_score=avg_score,
                coherence_percentage=coherence_pct,
                recommended_reassignments=reassign_count,
            )

            self.milestone_metrics[milestone_id] = metrics

            total_coherent += coherent_count
            total_incoherent += incoherent_count
            total_reassign += reassign_count
            coherence_scores.append(avg_score)

        # Overall metrics
        overall_coherence = (total_coherent / len(self.results)) * 100 if self.results else 0
        overall_avg_score = sum(coherence_scores) / len(coherence_scores) if coherence_scores else 0

        return {
            "timestamp": datetime.now().isoformat(),
            "total_issues_analyzed": len(self.results),
            "total_coherent_issues": total_coherent,
            "total_incoherent_issues": total_incoherent,
            "overall_coherence_percentage": overall_coherence,
            "overall_average_score": overall_avg_score,
            "recommended_reassignments": total_reassign,
            "milestone_metrics": [m.to_dict() for m in self.milestone_metrics.values()],
            "incoherent_issues": [r.to_dict() for r in self.results if not r.is_coherent],
        }

    def generate_report(self, metrics: dict[str, Any], output_file: str = None) -> str:
        """Generate markdown report."""
        print("📝 Generating markdown report...")

        # Handle empty metrics
        if not metrics or "error" in metrics:
            report_text = "# 🔥 Ruthless 10X Milestone Enforcement - Quality Report\n\n**No data to report**\n"
            if output_file:
                with open(output_file, "w") as f:
                    f.write(report_text)
            return report_text

        total_issues = metrics.get("total_issues_analyzed", 0)
        if total_issues == 0:
            report_text = "# 🔥 Ruthless 10X Milestone Enforcement - Quality Report\n\n**No issues to analyze**\n"
            if output_file:
                with open(output_file, "w") as f:
                    f.write(report_text)
            return report_text

        lines = [
            "# 🔥 Ruthless 10X Milestone Enforcement - Quality Report",
            f"**Generated:** {datetime.now().strftime('%Y-%m-%d %H:%M:%S UTC')}",
            "",
            "## Executive Summary",
            "",
            "| Metric | Value |",
            "|--------|-------|",
            f"| **Total Issues Analyzed** | {total_issues} |",
            f"| **Overall Coherence** | {metrics.get('overall_coherence_percentage', 0):.1f}% |",
            f"| **Average Coherence Score** | {metrics.get('overall_average_score', 0):.2f}/1.00 |",
            f"| **Issues in Wrong Milestone** | {metrics.get('total_incoherent_issues', 0)} |",
            f"| **Recommended Reassignments** | {metrics.get('recommended_reassignments', 0)} |",
            "",
            "## Milestone Coherence Breakdown",
            "",
            "| Milestone | Issues | Coherent | Incoherent | % Coherent | Avg Score |",
            "|-----------|--------|----------|------------|-----------|-----------|",
        ]

        # Sort by coherence percentage (ascending) to show worst performers first
        sorted_milestones = sorted(
            metrics.get("milestone_metrics", []),
            key=lambda m: m["coherence_percentage"],
        )

        for m in sorted_milestones:
            lines.append(
                f"| {m['milestone_title']:<40} | {m['total_issues']:<6} | "
                f"{m['coherent_issues']:<8} | {m['incoherent_issues']:<10} | "
                f"{m['coherence_percentage']:.1f}% | {m['avg_coherence_score']:.2f} |"
            )

        lines.extend(
            [
                "",
                "## 🚨 Issues Recommended for Reassignment",
                "",
                "### Strategy",
                "- **Review Issues** (0.50-0.70 coherence): May belong elsewhere, needs validation",
                "- **Reassign Issues** (<0.50 coherence): Clear misalignment, should be moved",
                "",
            ]
        )

        # Group incoherent issues by recommendation type
        incoherent_issues = metrics.get("incoherent_issues", [])
        review_issues = [i for i in incoherent_issues if i.get("recommendation") == "review"]
        reassign_issues = [i for i in incoherent_issues if i.get("recommendation") == "reassign"]

        if review_issues:
            lines.append(f"### Review Issues ({len(review_issues)} issues)")
            lines.append("")
            for issue in review_issues[:10]:  # Show first 10
                lines.append(
                    f"- **#{issue['issue_number']}:** {issue['title'][:60]}<br/>"
                    f"  Current: {issue['current_milestone']} | "
                    f"Score: {issue['coherence_score']:.2f} | "
                    f"Consider: {issue.get('alternative_milestone') or 'Review manually'}"
                )
            if len(review_issues) > 10:
                lines.append(f"- ... and {len(review_issues) - 10} more")
            lines.append("")

        if reassign_issues:
            lines.append(f"### Reassign Issues ({len(reassign_issues)} issues)")
            lines.append("")
            for issue in reassign_issues[:10]:  # Show first 10
                lines.append(
                    f"- **#{issue['issue_number']}:** {issue['title'][:60]}<br/>"
                    f"  Current: {issue['current_milestone']} | "
                    f"Score: {issue['coherence_score']:.2f} | "
                    f"Recommend: {issue.get('alternative_milestone') or 'Review manually'}"
                )
            if len(reassign_issues) > 10:
                lines.append(f"- ... and {len(reassign_issues) - 10} more")
            lines.append("")

        lines.extend(
            [
                "## Recommendations",
                "",
                "### Immediate Ruthelesness (Next 24 Hours)",
                "1. Auto-reassign issues with coherence < 0.50 to suggested milestones",
                "2. Flag issues 0.50-0.70 for manual review",
                "3. Verify no data loss (all issues keep current milestone until reviewed)",
                "",
                "### 10X Quality Targets",
                "- **Target Coherence:** >95% of milestones >80% coherent",
                "- **Maximum Drift:** No issue with <0.60 coherence score",
                "- **Review Cadence:** Validate quarterly to detect organizational drift",
                "",
                "---",
                "*Report generated by Ruthless 10X Metrics Generator | NIST-PM-5 Compliant*",
            ]
        )

        report_text = "\n".join(lines)

        if output_file:
            with open(output_file, "w") as f:
                f.write(report_text)
            print(f"✅ Report saved to {output_file}")

        return report_text


def main():
    """Main function."""
    parser = argparse.ArgumentParser(description="Generate 10X ruthless metrics for milestone coherence")
    parser.add_argument("--scan-closed", action="store_true", help="Include closed issues in scan")
    parser.add_argument("--output", default="ruthless_10x_coherence_report.md", help="Output file")
    parser.add_argument("--repo", default="kushin77/ElevatedIQ-Mono-Repo", help="GitHub repository")
    args = parser.parse_args()

    generator = RuthlessMetricsGenerator(repo=args.repo)

    # Scan issues
    total, issues = generator.scan_all_issues(include_closed=args.scan_closed)

    # Analyze coherence
    generator.analyze_coherence(issues)

    # Generate metrics
    metrics = generator.generate_metrics()

    # Generate report
    report = generator.generate_report(metrics, output_file=args.output)

    # Print to stdout
    print("\n" + report)

    # Print JSON metrics
    print("\n## JSON Metrics (for automation)")
    print(json.dumps(metrics, indent=2))


if __name__ == "__main__":
    main()
