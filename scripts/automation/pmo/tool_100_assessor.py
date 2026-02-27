#!/usr/bin/env python3
"""ElevatedIQ Tool-100 Assessor
Systematically analyzes tools and generates gap analysis to reach 100% completeness.

NIST Alignment:
- CM-8: Component Inventory
- SA-15: Development Process Standards
- CA-7: Continuous Monitoring

Refs: #5264 (parent), #5265-#5309 (tool-specific EPICs)
"""

import json
import re
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path


@dataclass
class ToolAssessment:
    """Assessment results for a single tool."""

    tool_id: str
    name: str
    current_score: int
    target_score: int = 100

    # Completeness checks
    has_readme: bool = False
    has_tests: bool = False
    has_dockerfile: bool = False
    has_makefile: bool = False
    has_requirements: bool = False
    has_health_endpoint: bool = False
    has_metrics: bool = False
    has_runbook: bool = False

    # Code analysis
    python_files: list[str] = field(default_factory=list)
    test_files: list[str] = field(default_factory=list)
    test_coverage: float | None = None

    # Security & compliance
    nist_controls: list[str] = field(default_factory=list)
    has_security_scan: bool = False
    has_audit_logs: bool = False

    # Gaps identified
    gaps: list[str] = field(default_factory=list)
    recommendations: list[str] = field(default_factory=list)

    @property
    def gap_count(self) -> int:
        """Total number of gaps identified."""
        return len(self.gaps)

    @property
    def readiness_percentage(self) -> float:
        """Calculate readiness based on checks completed."""
        total_checks = 11  # Number of boolean checks
        passed = sum([
            self.has_readme,
            self.has_tests,
            self.has_dockerfile,
            self.has_makefile,
            self.has_requirements,
            self.has_health_endpoint,
            self.has_metrics,
            self.has_runbook,
            self.has_security_scan,
            self.has_audit_logs,
            len(self.test_files) > 0
        ])
        return (passed / total_checks) * 100


class Tool100Assessor:
    """Assesses tools for 100% completeness."""

    def __init__(self, repo_root: Path):
        self.repo_root = repo_root
        self.apps_dir = repo_root / "apps"
        self.docs_dir = repo_root / "docs"
        self.runbooks_dir = self.docs_dir / "runbooks"

    def assess_tool(self, tool_id: str, tool_name: str, current_score: int, repo_path: str) -> ToolAssessment:
        """Perform comprehensive assessment of a single tool."""
        assessment = ToolAssessment(
            tool_id=tool_id,
            name=tool_name,
            current_score=current_score
        )

        tool_path = self.repo_root / repo_path

        if not tool_path.exists():
            assessment.gaps.append(f"Tool path does not exist: {repo_path}")
            assessment.recommendations.append(f"Create directory structure for {tool_id}")
            return assessment

        # File structure checks
        assessment.has_readme = (tool_path / "README.md").exists()
        if not assessment.has_readme:
            assessment.gaps.append("Missing README.md")
            assessment.recommendations.append("Create comprehensive README with usage, API docs, and examples")

        assessment.has_dockerfile = (tool_path / "Dockerfile").exists()
        if not assessment.has_dockerfile:
            assessment.gaps.append("Missing Dockerfile")
            assessment.recommendations.append("Create multi-stage Dockerfile with security best practices")

        assessment.has_makefile = (tool_path / "Makefile").exists()
        if not assessment.has_makefile:
            assessment.gaps.append("Missing Makefile")
            assessment.recommendations.append("Create Makefile with standard targets: test, lint, build, run")

        assessment.has_requirements = (tool_path / "requirements.txt").exists() or (tool_path / "package.json").exists()
        if not assessment.has_requirements:
            assessment.gaps.append("Missing dependency manifest")
            assessment.recommendations.append("Create requirements.txt or package.json with locked versions")

        # Find Python files
        if tool_path.is_dir():
            assessment.python_files = [
                str(p.relative_to(tool_path))
                for p in tool_path.rglob("*.py")
                if "test" not in str(p) and "__pycache__" not in str(p)
            ]

            assessment.test_files = [
                str(p.relative_to(tool_path))
                for p in tool_path.rglob("test*.py")
            ] + [
                str(p.relative_to(tool_path))
                for p in tool_path.rglob("*_test.py")
            ]

        assessment.has_tests = len(assessment.test_files) > 0
        if not assessment.has_tests:
            assessment.gaps.append("No test files found")
            assessment.recommendations.append("Create test suite with pytest covering main functionality")

        # Check for health endpoint in code
        if assessment.python_files:
            assessment.has_health_endpoint = self._check_for_pattern(
                tool_path, assessment.python_files, r'/health|/healthz|HealthCheck'
            )
            if not assessment.has_health_endpoint:
                assessment.gaps.append("No health check endpoint found")
                assessment.recommendations.append("Add /health endpoint returning service status")

        # Check for metrics
        if assessment.python_files:
            assessment.has_metrics = self._check_for_pattern(
                tool_path, assessment.python_files, r'prometheus|metrics|counter|gauge|histogram'
            )
            if not assessment.has_metrics:
                assessment.gaps.append("No metrics instrumentation found")
                assessment.recommendations.append("Add Prometheus metrics export")

        # Check for audit logging
        if assessment.python_files:
            assessment.has_audit_logs = self._check_for_pattern(
                tool_path, assessment.python_files, r'audit|logging\.info|logger\.'
            )
            if not assessment.has_audit_logs:
                assessment.gaps.append("No audit logging found")
                assessment.recommendations.append("Add structured audit logging for all operations")

        # Check for runbook
        runbook_path = self.runbooks_dir / f"{tool_id}.md"
        assessment.has_runbook = runbook_path.exists()
        if not assessment.has_runbook:
            assessment.gaps.append("No runbook found")
            assessment.recommendations.append(f"Create runbook at docs/runbooks/{tool_id}.md")

        # Check for security scanning
        if assessment.has_dockerfile:
            assessment.has_security_scan = self._check_trivy_scan(tool_id)
            if not assessment.has_security_scan:
                assessment.gaps.append("No security scan results")
                assessment.recommendations.append("Run trivy scan and fix vulnerabilities")

        # NIST controls check (read from toolsInventory.ts)
        assessment.nist_controls = self._extract_nist_controls(tool_id)
        if len(assessment.nist_controls) < 3:
            assessment.gaps.append("Insufficient NIST control mapping")
            assessment.recommendations.append("Map to at least 3-5 relevant NIST 800-53 controls")

        return assessment

    def _check_for_pattern(self, tool_path: Path, files: list[str], pattern: str) -> bool:
        """Check if pattern exists in any of the files."""
        regex = re.compile(pattern, re.IGNORECASE)
        for file in files:
            try:
                content = (tool_path / file).read_text()
                if regex.search(content):
                    return True
            except Exception:
                continue
        return False

    def _check_trivy_scan(self, tool_id: str) -> bool:
        """Check if trivy scan results exist."""
        report_path = self.repo_root / "reports" / f"trivy-{tool_id}.json"
        return report_path.exists()

    def _extract_nist_controls(self, tool_id: str) -> list[str]:
        """Extract NIST controls from toolsInventory.ts."""
        inventory_file = self.repo_root / "apps/portal/src/data/toolsInventory.ts"
        if not inventory_file.exists():
            return []

        content = inventory_file.read_text()

        # Find the tool block
        tool_pattern = rf"id:\s*['\"]{ re.escape(tool_id)}['\"].*?nistControls:\s*\[(.*?)\]"
        match = re.search(tool_pattern, content, re.DOTALL)

        if match:
            controls_str = match.group(1)
            controls = re.findall(r"['\"]([A-Z]+-\d+)['\"]", controls_str)
            return controls

        return []

    def generate_issue_comment(self, assessment: ToolAssessment) -> str:
        """Generate GitHub issue comment with assessment results."""
        comment = f"""## 🔍 Tool Assessment Results: {assessment.name}

**Current Score:** {assessment.current_score}/100
**Target Score:** {assessment.target_score}/100
**Assessment Date:** {subprocess.check_output(["date", "-u", "+%Y-%m-%d %H:%M UTC"]).decode().strip()}

### Readiness Analysis
**Structural Readiness:** {assessment.readiness_percentage:.1f}% ({sum([assessment.has_readme, assessment.has_tests, assessment.has_dockerfile, assessment.has_makefile, assessment.has_requirements, assessment.has_health_endpoint, assessment.has_metrics, assessment.has_runbook, assessment.has_security_scan, assessment.has_audit_logs, len(assessment.test_files) > 0])}/11 checks passed)

### Component Checklist
- [{"x" if assessment.has_readme else " "}] README.md
- [{"x" if assessment.has_dockerfile else " "}] Dockerfile
- [{"x" if assessment.has_makefile else " "}] Makefile
- [{"x" if assessment.has_requirements else " "}] Dependency manifest
- [{"x" if assessment.has_tests else " "}] Test suite ({len(assessment.test_files)} test files)
- [{"x" if assessment.has_health_endpoint else " "}] Health endpoint
- [{"x" if assessment.has_metrics else " "}] Metrics instrumentation
- [{"x" if assessment.has_audit_logs else " "}] Audit logging
- [{"x" if assessment.has_runbook else " "}] Runbook
- [{"x" if assessment.has_security_scan else " "}] Security scan
- [{"x" if len(assessment.nist_controls) >= 3 else " "}] NIST controls mapped ({len(assessment.nist_controls)} controls)

### Identified Gaps ({assessment.gap_count})
"""

        for i, gap in enumerate(assessment.gaps, 1):
            comment += f"{i}. {gap}\n"

        comment += f"\n### Recommendations ({len(assessment.recommendations)})\n"
        for i, rec in enumerate(assessment.recommendations, 1):
            comment += f"{i}. {rec}\n"

        comment += f"""
### Next Steps
1. Address gaps listed above in priority order
2. Run validation: `./scripts/pmo/tool_100_assessor.py {assessment.tool_id}`
3. Update score in `apps/portal/src/data/toolsInventory.ts`
4. Mark issue as completed when score reaches 100

---
_Auto-generated by `scripts/pmo/tool_100_assessor.py` — NIST CM-8, SA-15_
"""
        return comment

    def generate_json_report(self, assessment: ToolAssessment) -> str:
        """Generate JSON report for automation."""
        return json.dumps({
            "tool_id": assessment.tool_id,
            "name": assessment.name,
            "current_score": assessment.current_score,
            "target_score": assessment.target_score,
            "readiness_percentage": round(assessment.readiness_percentage, 1),
            "gap_count": assessment.gap_count,
            "gaps": assessment.gaps,
            "recommendations": assessment.recommendations,
            "checks": {
                "has_readme": assessment.has_readme,
                "has_tests": assessment.has_tests,
                "has_dockerfile": assessment.has_dockerfile,
                "has_makefile": assessment.has_makefile,
                "has_requirements": assessment.has_requirements,
                "has_health_endpoint": assessment.has_health_endpoint,
                "has_metrics": assessment.has_metrics,
                "has_runbook": assessment.has_runbook,
                "has_security_scan": assessment.has_security_scan,
                "has_audit_logs": assessment.has_audit_logs,
            },
            "nist_controls": assessment.nist_controls,
            "test_file_count": len(assessment.test_files),
            "python_file_count": len(assessment.python_files),
        }, indent=2)


def main():
    """Main entry point."""
    if len(sys.argv) < 5:
        print("Usage: ./tool_100_assessor.py <tool_id> <tool_name> <current_score> <repo_path>")
        print("Example: ./tool_100_assessor.py ai-embedding-server 'AI Embedding Server' 92 apps/ai-embedding-server")
        sys.exit(1)

    tool_id = sys.argv[1]
    tool_name = sys.argv[2]
    current_score = int(sys.argv[3])
    repo_path = sys.argv[4]

    repo_root = Path(__file__).parent.parent.parent
    assessor = Tool100Assessor(repo_root)

    print(f"🔍 Assessing {tool_name} ({tool_id})...")
    assessment = assessor.assess_tool(tool_id, tool_name, current_score, repo_path)

    print("\n✅ Assessment complete!")
    print(f"Readiness: {assessment.readiness_percentage:.1f}%")
    print(f"Gaps identified: {assessment.gap_count}")

    # Generate outputs
    comment = assessor.generate_issue_comment(assessment)
    json_report = assessor.generate_json_report(assessment)

    # Write to files
    reports_dir = repo_root / "reports" / "tool-assessments"
    reports_dir.mkdir(parents=True, exist_ok=True)

    comment_file = reports_dir / f"{tool_id}-assessment.md"
    json_file = reports_dir / f"{tool_id}-assessment.json"

    comment_file.write_text(comment)
    json_file.write_text(json_report)

    print("\n📄 Reports generated:")
    print(f"  - Markdown: {comment_file}")
    print(f"  - JSON: {json_file}")

    # Print comment for GitHub CLI usage
    print("\n📋 GitHub Comment Preview:\n")
    print(comment)

    return 0 if assessment.gap_count == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
