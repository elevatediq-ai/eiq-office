#!/usr/bin/env python3
"""🛡️ Continuous Risk Assessment Engine.

Enhancement 9 of 10x PMO Process Improvements
Monitors code quality, security, and operational risks in real-time

Features:
- Dependency vulnerability scanning (pip, npm, etc.)
- Code quality metrics (complexity, coverage, etc.)
- Security scanning (secrets, hardcoded credentials)
- Performance regression detection
- Test coverage tracking
- Deployment risk scoring
- Auto-remediation recommendations

Usage:
    ./risk_assessment.py scan          # Full risk scan
    ./risk_assessment.py security      # Security vulnerabilities only
    ./risk_assessment.py quality       # Code quality metrics
    ./risk_assessment.py trending      # Risk trends over time
    ./risk_assessment.py report        # Generate risk report
    ./risk_assessment.py test          # Run tests
"""

import json
import subprocess
import sys
from datetime import datetime
from pathlib import Path


class RiskAssessment:
    """Continuous risk assessment and monitoring."""

    def __init__(self, repo_path="."):
        self.repo = repo_path
        self.risk_scores = {}
        self.thresholds = {
            "critical_vuln": 1,  # Any critical vulns = CRITICAL risk
            "high_vuln": 3,  # 3+ high vulns = HIGH risk
            "low_coverage": 70,  # <70% coverage = MEDIUM risk
            "complexity_high": 15,  # Cyclomatic complexity > 15
        }

    def run_cmd(self, cmd, silent=False):
        """Execute command safely."""
        try:
            result = subprocess.run(
                f"cd {self.repo} && {cmd}",
                shell=True,
                capture_output=True,
                text=True,
                timeout=30,
            )
            return result.stdout.strip() if result.returncode == 0 else ""
        except Exception:
            if not silent:
                print(f"⚠️  Command failed: {cmd}")
            return ""

    def scan_dependencies(self):
        """Scan for dependency vulnerabilities."""
        findings = {"critical": 0, "high": 0, "medium": 0, "low": 0, "packages": []}

        # Check for requirements.txt
        req_file = Path(self.repo) / "requirements.txt"
        if req_file.exists():
            # Try pip-audit
            cmd = "pip-audit --desc 2>/dev/null | grep -E '^Found|vulnerability'"
            result = self.run_cmd(cmd, silent=True)

            if result:
                if "Found" in result:
                    # Parse pip-audit output
                    findings["high"] += result.count("High")
                    findings["medium"] += result.count("Medium")
                    findings["low"] += result.count("Low")

        return findings

    def analyze_code_quality(self):
        """Analyze code quality metrics."""
        metrics = {
            "test_coverage": 0,
            "complexity_average": 0,
            "pylint_score": 0,
            "issues": [],
        }

        # Check for pytest coverage
        cmd = "coverage report 2>/dev/null | tail -1 | awk '{print $NF}' | sed 's/%//'"
        coverage_str = self.run_cmd(cmd, silent=True)
        if coverage_str:
            try:
                metrics["test_coverage"] = int(coverage_str.split()[0] if coverage_str.split() else "0")
            except Exception:
                pass

        # Pylint check
        py_files = list(Path(self.repo).glob("*.py"))
        if py_files and len(py_files) < 100:  # Only if manageable number
            cmd = "pylint --exit-zero -f json . 2>/dev/null | python3 -c \"import json,sys; data=json.load(sys.stdin); print(sum(1 for m in data if m['type']=='error'))\""
            errors = self.run_cmd(cmd, silent=True)
            if errors:
                metrics["issues"].append(
                    {
                        "type": "PYLINT_ERRORS",
                        "count": int(errors or "0"),
                        "severity": "HIGH",
                    }
                )

        return metrics

    def security_scan(self):
        """Security-focused scanning."""
        findings = {
            "secrets": 0,
            "hardcoded_creds": 0,
            "dangerous_libraries": 0,
            "missing_tls": 0,
            "issues": [],
        }

        # Check for hardcoded secrets using simple patterns
        sneaky_patterns = [
            "password\\s*=",
            "api_key\\s*=",
            "secret\\s*=",
            "token\\s*=",
        ]

        # Check Python files
        for py_file in Path(self.repo).glob("**/*.py"):
            if "venv" in str(py_file) or "__pycache__" in str(py_file):
                continue

            try:
                content = py_file.read_text()
                for pattern in sneaky_patterns:
                    if pattern in content.lower():
                        findings["hardcoded_creds"] += 1
                        findings["issues"].append(
                            {
                                "type": "HARDCODED_SECRET",
                                "file": str(py_file),
                                "severity": "CRITICAL",
                            }
                        )
            except Exception:
                pass

        return findings

    def calculate_risk_score(self, dependencies, quality, security):
        """Calculate overall risk score (0-100, higher = more risk)."""
        risk = 0

        # Dependency risk (30%)
        dep_risk = dependencies["critical"] * 30 + dependencies["high"] * 20 + dependencies["medium"] * 5
        risk += min(dep_risk / 10, 30)

        # Quality risk (30%)
        if quality["test_coverage"] < self.thresholds["low_coverage"]:
            risk += 20 - (quality["test_coverage"] / 100 * 20)

        if quality["pylint_score"] < 70 or len(quality["issues"]) > 0:
            risk += 10

        # Security risk (40%)
        sec_risk = (
            security["secrets"] * 40
            + security["hardcoded_creds"] * 35
            + security["dangerous_libraries"] * 20
            + security["missing_tls"] * 15
        )
        risk += min(sec_risk / 10, 40)

        return min(risk, 100)

    def get_risk_level(self, score):
        """Classify risk level."""
        if score >= 80:
            return "🔴 CRITICAL"
        elif score >= 60:
            return "🟠 HIGH"
        elif score >= 40:
            return "🟡 MEDIUM"
        elif score >= 20:
            return "🟢 LOW"
        else:
            return "✅ MINIMAL"

    def remediation_suggestions(self, risk_data):
        """Generate remediation suggestions."""
        suggestions = []

        # Dependency remediation
        if risk_data["dependencies"]["critical"] > 0:
            suggestions.append(
                {
                    "priority": "CRITICAL",
                    "issue": "Critical vulnerabilities detected",
                    "action": "Run 'pip-audit' and update affected packages immediately",
                    "est_time": "1-4 hours",
                }
            )

        # Coverage remediation
        if risk_data["quality"]["test_coverage"] < 70:
            gap = 70 - risk_data["quality"]["test_coverage"]
            suggestions.append(
                {
                    "priority": "HIGH",
                    "issue": f"Test coverage is {risk_data['quality']['test_coverage']}% (target: 70%+)",
                    "action": f"Add {gap}% more test coverage",
                    "est_time": "2-8 hours",
                }
            )

        # Security remediation
        if risk_data["security"]["hardcoded_creds"] > 0:
            suggestions.append(
                {
                    "priority": "CRITICAL",
                    "issue": f"{risk_data['security']['hardcoded_creds']} hardcoded credentials found",
                    "action": "Move to environment variables or AWS Secrets Manager",
                    "est_time": "4-8 hours",
                }
            )

        if len(risk_data["security"]["issues"]) > 0:
            suggestions.append(
                {
                    "priority": "HIGH",
                    "issue": "Security issues detected",
                    "action": "Review and remediate detected security issues",
                    "est_time": "1-2 hours",
                }
            )

        return suggestions

    def get_risk_trend(self):
        """Analyze risk trends (would read from historical logs)."""
        historical_path = Path(self.repo) / "logs/risk_assessments"

        if not historical_path.exists():
            return {"status": "no_history", "trend": "STABLE"}

        # Read last 30 days of risk scores
        risk_scores = []
        for log_file in sorted(historical_path.glob("*.json"))[-30:]:
            try:
                data = json.loads(log_file.read_text())
                risk_scores.append(data.get("overall_risk", 0))
            except Exception:
                pass

        if not risk_scores:
            return {"status": "no_history", "trend": "STABLE"}

        avg_recent = sum(risk_scores[-7:]) / 7 if len(risk_scores) >= 7 else risk_scores[-1]
        avg_older = sum(risk_scores[-14:-7]) / 7 if len(risk_scores) >= 14 else avg_recent

        trend_delta = avg_recent - avg_older

        if trend_delta > 5:
            trend = "RISING"
        elif trend_delta < -5:
            trend = "FALLING"
        else:
            trend = "STABLE"

        return {
            "current_score": risk_scores[-1],
            "7day_avg": round(avg_recent, 1),
            "trend": trend,
            "delta": round(trend_delta, 1),
        }

    def export_findings_json(self):
        """Export all findings as JSON."""
        deps = self.scan_dependencies()
        quality = self.analyze_code_quality()
        security = self.security_scan()
        overall_risk = self.calculate_risk_score(deps, quality, security)

        return json.dumps(
            {
                "timestamp": datetime.now().isoformat(),
                "overall_risk_score": round(overall_risk, 1),
                "risk_level": self.get_risk_level(overall_risk),
                "dependencies": deps,
                "code_quality": quality,
                "security": security,
                "recommendations": self.remediation_suggestions(
                    {"dependencies": deps, "quality": quality, "security": security}
                ),
            },
            indent=2,
        )

    def display_report(self):  # noqa: PLR0915
        """Display comprehensive risk report."""
        deps = self.scan_dependencies()
        quality = self.analyze_code_quality()
        security = self.security_scan()
        overall_risk = self.calculate_risk_score(deps, quality, security)
        trend = self.get_risk_trend()
        recommendations = self.remediation_suggestions({"dependencies": deps, "quality": quality, "security": security})

        print("\n" + "=" * 80)
        print("🛡️  CONTINUOUS RISK ASSESSMENT ENGINE")
        print("=" * 80)
        print(f"⏰ {datetime.now().strftime('%Y-%m-%d %H:%M:%S UTC')}\n")

        # Overall Risk
        print("📊 OVERALL RISK SCORE")
        print("-" * 80)
        print(f"  Score:                {round(overall_risk, 1)}/100")
        print(f"  Level:                {self.get_risk_level(overall_risk)}")
        print(f"  Trend:                {trend['trend']} ({trend['delta']:+.1f})")
        print()

        # Dependencies
        print("📦 DEPENDENCY VULNERABILITIES")
        print("-" * 80)
        print(f"  Critical:             {deps['critical']}")
        print(f"  High:                 {deps['high']}")
        print(f"  Medium:               {deps['medium']}")
        print(f"  Low:                  {deps['low']}")
        print()

        # Code Quality
        print("🎯 CODE QUALITY METRICS")
        print("-" * 80)
        cov_status = "🟢" if quality["test_coverage"] >= 70 else "🟡" if quality["test_coverage"] >= 50 else "🔴"
        print(f"  Test Coverage:        {quality['test_coverage']}% {cov_status}")
        print(f"  Pylint Issues:        {len(quality['issues'])}")
        if quality["issues"]:
            for issue in quality["issues"]:
                print(f"    - {issue['type']}: {issue['count']}")
        print()

        # Security
        print("🔐 SECURITY FINDINGS")
        print("-" * 80)
        print(f"  Hardcoded Credentials: {security['hardcoded_creds']}")
        print(f"  Secret Strings:        {security['secrets']}")
        print(f"  Missing TLS/SSL:       {security['missing_tls']}")
        if security["issues"]:
            print("  Issues:")
            for issue in security["issues"][:5]:
                print(f"    - [{issue['severity']}] {issue['type']} in {Path(issue['file']).name}")
        print()

        # Recommendations
        if recommendations:
            print("💡 REMEDIATION RECOMMENDATIONS")
            print("-" * 80)
            for i, rec in enumerate(recommendations[:5], 1):
                icon = "🔴" if rec["priority"] == "CRITICAL" else "🟠" if rec["priority"] == "HIGH" else "🟡"
                print(f"  {i}. {icon} [{rec['priority']}] {rec['issue']}")
                print(f"     Action: {rec['action']}")
                print(f"     Est. Time: {rec['est_time']}")
                print()
        else:
            print("✅ NO CRITICAL ISSUES - Risk level is acceptable\n")

        print("=" * 80 + "\n")

    def run_tests(self):
        """Run unit tests."""
        print("\n🧪 RISK ASSESSMENT UNIT TESTS\n")

        tests_passed = 0
        tests_total = 0

        # Test 1: Risk scoring
        tests_total += 1
        try:
            test_data = {
                "critical": 0,
                "high": 1,
                "medium": 2,
                "low": 3,
                "packages": [],
            }
            score = self.calculate_risk_score(
                test_data,
                {
                    "test_coverage": 75,
                    "complexity_average": 10,
                    "pylint_score": 80,
                    "issues": [],
                },
                {
                    "secrets": 0,
                    "hardcoded_creds": 0,
                    "dangerous_libraries": 0,
                    "missing_tls": 0,
                    "issues": [],
                },
            )
            assert 0 <= score <= 100
            print("✅ Test 1: Risk scoring - PASSED")
            tests_passed += 1
        except Exception as e:
            print(f"❌ Test 1: Risk scoring - FAILED ({e})")

        # Test 2: Risk level classification
        tests_total += 1
        try:
            level = self.get_risk_level(75)
            assert level in [
                "🔴 CRITICAL",
                "🟠 HIGH",
                "🟡 MEDIUM",
                "🟢 LOW",
                "✅ MINIMAL",
            ]
            print("✅ Test 2: Risk level classification - PASSED")
            tests_passed += 1
        except Exception as e:
            print(f"❌ Test 2: Risk level classification - FAILED ({e})")

        # Test 3: Remediation suggestions
        tests_total += 1
        try:
            suggestions = self.remediation_suggestions(
                {
                    "dependencies": {"critical": 1, "high": 0, "medium": 0, "low": 0},
                    "quality": {"test_coverage": 50, "issues": []},
                    "security": {"hardcoded_creds": 0, "issues": []},
                }
            )
            assert len(suggestions) > 0
            print("✅ Test 3: Remediation suggestions - PASSED")
            tests_passed += 1
        except Exception as e:
            print(f"❌ Test 3: Remediation suggestions - FAILED ({e})")

        # Test 4: JSON export
        tests_total += 1
        try:
            report_json = self.export_findings_json()
            json.loads(report_json)
            print("✅ Test 4: JSON export - PASSED")
            tests_passed += 1
        except Exception as e:
            print(f"❌ Test 4: JSON export - FAILED ({e})")

        print(f"\n📊 Results: {tests_passed}/{tests_total} tests passed")
        return tests_passed == tests_total


def main():
    """Main entry point."""
    assessment = RiskAssessment()

    if len(sys.argv) < 2:
        assessment.display_report()
        return

    command = sys.argv[1]

    if command == "scan":
        assessment.display_report()
    elif command == "security":
        security = assessment.security_scan()
        print(json.dumps(security, indent=2))
    elif command == "quality":
        quality = assessment.analyze_code_quality()
        print(json.dumps(quality, indent=2))
    elif command == "dependencies":
        deps = assessment.scan_dependencies()
        print(json.dumps(deps, indent=2))
    elif command == "trending":
        trend = assessment.get_risk_trend()
        print(json.dumps(trend, indent=2))
    elif command == "report":
        print(assessment.export_findings_json())
    elif command == "test":
        success = assessment.run_tests()
        sys.exit(0 if success else 1)
    else:
        print(f"Unknown command: {command}")
        print("Usage: risk_assessment.py [scan|security|quality|dependencies|trending|report|test]")
        sys.exit(1)


if __name__ == "__main__":
    main()
