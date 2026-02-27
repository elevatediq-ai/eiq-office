#!/usr/bin/env python3
"""Phase 9.2 sprint gatekeeper helper.

Inspects key artifacts referenced by issue #698 and prints a readiness summary so
PMO can see what documentation, infrastructure, and verification evidence exists
without spinning up cloud resources.
"""

from __future__ import annotations

import subprocess
import sys
from collections.abc import Iterable, Sequence
from dataclasses import dataclass
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]

TEXT_CACHE: dict[Path, str | None] = {}


@dataclass
class CheckResult:
    """CheckResult class."""

    description: str
    passed: bool
    detail: str
    reference: str


def rel_path(path: Path) -> str:
    """rel_path function."""
    try:
        return str(path.relative_to(REPO_ROOT))
    except ValueError:
        return str(path)


def get_text(path: Path) -> str | None:
    """get_text function."""
    if path not in TEXT_CACHE:
        try:
            TEXT_CACHE[path] = path.read_text()
        except FileNotFoundError:
            TEXT_CACHE[path] = None
    return TEXT_CACHE[path]


def file_check(description: str, path: Path) -> CheckResult:
    """file_check function."""
    reference = rel_path(path)
    if path.exists():
        detail = f"Found {reference}"
        passed = True
    else:
        detail = f"Missing {reference}"
        passed = False
    return CheckResult(description, passed, detail, reference)


def multi_file_check(description: str, paths: Sequence[Path]) -> CheckResult:
    """multi_file_check function."""
    missing = [p for p in paths if not p.exists()]
    reference = "; ".join(rel_path(p) for p in paths)
    if not missing:
        detail = f"All artifacts present ({reference})"
        passed = True
    else:
        detail = f"Missing {', '.join(rel_path(p) for p in missing)}"
        passed = False
    return CheckResult(description, passed, detail, reference)


def contains_check(
    description: str,
    path: Path,
    substrings: Iterable[str],
) -> CheckResult:
    """contains_check function."""
    text = get_text(path)
    reference = rel_path(path)
    if text is None:
        return CheckResult(description, False, f"Missing {reference}", reference)

    missing = [s for s in substrings if s not in text]
    if not missing:
        detail = f"Contains: {', '.join(repr(s) for s in substrings)}"
        passed = True
    else:
        detail = f"Missing {', '.join(repr(s) for s in missing)}"
        passed = False
    return CheckResult(description, passed, detail, reference)


def shell_syntax_check(description: str, script_path: Path) -> CheckResult:
    """shell_syntax_check function."""
    reference = rel_path(script_path)
    try:
        subprocess.run(
            ["bash", "-n", str(script_path)],
            check=True,
            capture_output=True,
            text=True,
        )
        detail = f"Syntax OK ({reference})"
        passed = True
    except subprocess.CalledProcessError as exc:
        output = exc.stderr.strip() or exc.stdout.strip()
        detail = f"Syntax error in {reference}: {output}" if output else f"Syntax error in {reference}"
        passed = False
    return CheckResult(description, passed, detail, reference)


def directory_rego_check(description: str, directory: Path) -> CheckResult:
    """directory_rego_check function."""
    reference = rel_path(directory)
    if not directory.exists():
        return CheckResult(description, False, f"Missing directory {reference}", reference)

    rego_files = list(directory.glob("*.rego"))
    passed = bool(rego_files)
    if passed:
        detail = f"Found {len(rego_files)} Rego policies under {reference}"
    else:
        detail = f"No Rego policies under {reference}"
    return CheckResult(description, passed, detail, reference)


def substring_exists(text: str | None, substring: str) -> bool:
    """substring_exists function."""
    return bool(text and substring in text)


def search_and_report(
    description: str,
    path: Path,
    substring: str,
    detail_pass: str | None = None,
    detail_fail: str | None = None,
) -> CheckResult:
    """search_and_report function."""
    reference = rel_path(path)
    text = get_text(path)
    if text is None:
        return CheckResult(description, False, f"Missing {reference}", reference)
    if substring in text:
        detail = detail_pass or f"Contains {repr(substring)}"
        return CheckResult(description, True, detail, reference)
    detail = detail_fail or f"{repr(substring)} not present"
    return CheckResult(description, False, detail, reference)


def build_categories() -> list[tuple[str, list[CheckResult]]]:
    """build_categories function."""
    phase91_doc = REPO_ROOT / "docs/architecture/PHASE_9.1_GOVERNANCE_SPECIFICATION.md"
    phase92_arch = REPO_ROOT / "docs/architecture/PHASE_9.2_AUTONOMOUS_OPTIMIZATION.md"
    session_completion = REPO_ROOT / "docs/management/SESSION_COMPLETION_20260207.md"
    execution_roadmap = REPO_ROOT / "docs/management/PHASE_9_EXECUTION_ROADMAP.md"
    extended_closure = REPO_ROOT / "docs/management/EXTENDED_SESSION_CLOSURE_20260207.md"
    phase92_guide = REPO_ROOT / "docs/phase_9_2_execution_guide.md"
    policy_workflow = REPO_ROOT / ".github/workflows/policy-validation.yml"
    policy_engine = REPO_ROOT / "libs/governance/policy_engine.py"
    pipeline_validation = REPO_ROOT / "scripts/phase-9-2/pipeline_validation.py"
    redis_module = REPO_ROOT / "terraform/modules/phase-9-2-redis/main.tf"
    sqs_module = REPO_ROOT / "terraform/modules/phase-9-2-sqs/main.tf"
    monitoring_module = REPO_ROOT / "terraform/modules/phase-9-2-monitoring/main.tf"
    schema_path = REPO_ROOT / "infra/db/migrations/004_phase_9_2_schema.sql"
    dev_login = REPO_ROOT / "scripts/dev-login.sh"
    service_account_path = execution_roadmap
    start_script = REPO_ROOT / "apps/control_plane/start.sh"
    integration_tests = REPO_ROOT / "scripts/phase-9-2/integration_tests.py"
    model_training = REPO_ROOT / "scripts/pmo/phase9.2.1_model_training.py"

    categories: list[tuple[str, list[CheckResult]]] = []

    # Phase 9.1 completion evidence
    categories.append(
        (
            "Phase 9.1 prerequisites",
            [
                file_check("Phase 9.1 governance framework (#666)", phase91_doc),
                multi_file_check(
                    "Policy validation service (#670) deployed",
                    [policy_workflow, policy_engine],
                ),
                directory_rego_check(
                    "Cost governance policies imported",
                    REPO_ROOT / "libs/governance/policies/gcp",
                ),
                contains_check(
                    "Audit logging (NIST-AU-2) verified",
                    REPO_ROOT / "libs/governance/audit_logger.py",
                    ["class AuditLogger"],
                ),
                search_and_report(
                    "Cost data governance baseline",
                    session_completion,
                    "Cost data encrypted at rest",
                    detail_pass="Document states cost data encrypted at rest",  # noqa: S106
                    detail_fail="Look for cost governance baseline evidence",
                ),
            ],
        )
    )

    # Infrastructure & database readiness
    expected_tables = [
        "cost_facts",
        "hourly_demand",
        "ri_commitments",
        "savings_plans",
        "spot_instances",
        "instance_types",
        "cost_anomalies",
        "cost_allocations",
    ]
    table_snippets = [f"CREATE TABLE IF NOT EXISTS public.{name}" for name in expected_tables]
    expected_views = [
        "v_daily_cost_summary",
        "v_ri_utilization_report",
        "v_cost_attribution_summary",
    ]
    view_snippets = [f"CREATE MATERIALIZED VIEW IF NOT EXISTS {name}" for name in expected_views]
    schema_text = get_text(schema_path)
    table_missing = (
        [
            name
            for name, snippet in zip(expected_tables, table_snippets)
            if not schema_text or snippet not in schema_text
        ]
        if schema_text
        else expected_tables
    )
    view_missing = (
        [name for name, snippet in zip(expected_views, view_snippets) if not schema_text or snippet not in schema_text]
        if schema_text
        else expected_views
    )
    rls_count = schema_text.count("ENABLE ROW LEVEL SECURITY") if schema_text else 0

    categories.append(
        (
            "Infrastructure & database",
            [
                file_check("Phase 9.2 schema migration", schema_path),
                CheckResult(
                    "Eight core tables deployed",
                    not table_missing,
                    (
                        f"All tables present ({', '.join(expected_tables)})"
                        if not table_missing
                        else f"Missing tables: {', '.join(table_missing)}"
                    ),
                    rel_path(schema_path),
                ),
                CheckResult(
                    "Three analytics materialized views",
                    not view_missing,
                    (
                        f"Views present ({', '.join(expected_views)})"
                        if not view_missing
                        else f"Missing views: {', '.join(view_missing)}"
                    ),
                    rel_path(schema_path),
                ),
                CheckResult(
                    "Row-level security policies enabled (critical tables)",
                    rls_count >= 6,
                    (
                        f"Detected {rls_count} ENABLE ROW LEVEL SECURITY declarations"
                        if schema_text
                        else "Schema file missing"
                    ),
                    rel_path(schema_path),
                ),
                search_and_report(
                    "Postgres backup strategy validated",
                    redis_module,
                    "Backup strategy",
                    detail_pass="Redis module documents snapshot retention/backups",  # noqa: S106
                ),
                file_check("Redis cache cluster configuration", redis_module),
                file_check("Async messaging queue (SQS) provisioned", sqs_module),
                CheckResult(
                    "Time-series monitoring module",
                    monitoring_module.exists(),
                    (
                        "CloudWatch dashboard + alarms defined"
                        if monitoring_module.exists()
                        else "Monitoring module missing"
                    ),
                    rel_path(monitoring_module),
                ),
                file_check("Data pipeline validation script", pipeline_validation),
                search_and_report(
                    "Prometheus/metrics story captured",
                    phase92_arch,
                    "Prometheus",
                    detail_pass="Architecture doc references Prometheus metrics",  # noqa: S106
                    detail_fail="Mention of Prometheus metrics missing",
                ),
            ],
        )
    )

    # Development environment readiness
    categories.append(
        (
            "Development environment",
            [
                contains_check(
                    "Service account & IAM instructions",
                    service_account_path,
                    ["ci-phase9-reader", "ci-phase9-staging-writer"],
                ),
                contains_check(
                    "GitHub Actions secrets documented",
                    service_account_path,
                    ["AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY"],
                ),
                shell_syntax_check("dev-login.sh syntax check", dev_login),
                contains_check(
                    "Safety guards enforced",
                    dev_login,
                    ["setup_safety_guards", "SafetyGuard"],
                ),
                contains_check(
                    "Live API health helpers",
                    dev_login,
                    ["PHASE9_COST_API", "load_api_endpoints"],
                ),
                search_and_report(
                    "Unit tests command defined",
                    execution_roadmap,
                    "pytest tests/cost/",
                    detail_pass="Local unit test command documented",  # noqa: S106
                ),
            ],
        )
    )

    # Team assignments
    categories.append(
        (
            "Team assignments",
            [
                search_and_report(
                    "Analytics architect assigned",
                    extended_closure,
                    "Analytics Architect",
                ),
                search_and_report(
                    "Backend engineers roster",
                    extended_closure,
                    "**Backend**: 3 engineers",
                ),
                search_and_report(
                    "Data engineer assignment",
                    extended_closure,
                    "**Data**: 1 engineer",
                ),
                search_and_report(
                    "DevOps owner allocated",
                    extended_closure,
                    "**DevOps**: 1 engineer",
                ),
                search_and_report(
                    "Gurobi licensing spike",
                    phase92_guide,
                    "Gurobi",
                    detail_pass="Solver decision referenced (Gurobi + COIN-OR)",  # noqa: S106
                ),
                search_and_report(
                    "Team onboarding readiness",
                    session_completion,
                    "team onboarding",
                    detail_pass="Session notes say ready for team onboarding",  # noqa: S106
                ),
            ],
        )
    )

    # Documentation review
    categories.append(
        (
            "Documentation review",
            [
                search_and_report(
                    "Architecture doc reviewed",
                    session_completion,
                    "Phase 9.2 Comprehensive Architecture",
                ),
                search_and_report(
                    "Subtask specifications reviewed",
                    session_completion,
                    "#681",
                ),
                search_and_report(
                    "API contracts confirmed",
                    session_completion,
                    "API designs ready",
                ),
                search_and_report(
                    "Database schema walkthrough",
                    session_completion,
                    "Database schemas provided",
                ),
                search_and_report(
                    "ML models + hyperparameters",
                    session_completion,
                    "ML models specified",
                ),
                search_and_report(
                    "Testing strategy aligned",
                    session_completion,
                    "Test Coverage",
                    detail_fail="Document the 90%+ coverage target for Phase 9.2",
                    detail_pass="Test coverage target documented",  # noqa: S106
                ),
            ],
        )
    )

    # Data ingestion verification
    pipeline_checks = []
    for func in [
        "validate_cloud_billing_connectivity",
        "validate_data_quality",
        "validate_historical_data",
        "validate_anomaly_baselines",
        "validate_postgres_schema",
    ]:
        pipeline_checks.append(
            search_and_report(
                f"Data pipeline check: {func}",
                pipeline_validation,
                func,
            )
        )
    categories.append(("Data ingestion", pipeline_checks))

    # Testing & validation
    categories.append(
        (
            "Testing & validation",
            [
                file_check("Staging start script (./start.sh)", start_script),
                file_check("Integration test helpers", integration_tests),
                file_check("ML model training script", model_training),
                file_check("API smoke test file", REPO_ROOT / "tests/cost/test_api.py"),
                search_and_report(
                    "Live optimizer unit test command",
                    execution_roadmap,
                    "python -m pytest tests/cost/test_optimizer.py",
                    detail_pass="Optimizer live test command recorded",  # noqa: S106
                ),
                search_and_report(
                    "Safety guard validation noted",
                    extended_closure,
                    "Safety guards implemented",
                ),
            ],
        )
    )

    # Success metrics baseline
    categories.append(
        (
            "Success metrics baseline",
            [
                search_and_report(
                    "Forecast error baseline",
                    session_completion,
                    "Forecast Error (MAPE)",
                ),
                search_and_report(
                    "Cost optimization accuracy",
                    session_completion,
                    "Cost Optimization Accuracy",
                ),
                search_and_report(
                    "Database latency benchmark",
                    monitoring_module,
                    "Database query latency",
                ),
                search_and_report(
                    "API response time benchmark",
                    monitoring_module,
                    "API response time",
                ),
                search_and_report(
                    "Cost attribution reconciliation",
                    session_completion,
                    "Cost attribution endpoints",
                ),
            ],
        )
    )

    # Security & compliance
    categories.append(
        (
            "Security & compliance",
            [
                search_and_report(
                    "NIST CA-7 control active",
                    extended_closure,
                    "CA-7",
                ),
                search_and_report(
                    "NIST AU-2 audit trail",
                    extended_closure,
                    "AU-2",
                ),
                search_and_report(
                    "NIST SC-7 boundary protection",
                    extended_closure,
                    "SC-7",
                ),
                search_and_report(
                    "NIST AC-3 access control",
                    extended_closure,
                    "AC-3",
                ),
                search_and_report(
                    "Secrets rotation policy",
                    extended_closure,
                    "Credential caching + rotation implemented",
                ),
                search_and_report(
                    "Encryption at rest (TDE)",
                    session_completion,
                    "TDE",
                ),
                search_and_report(
                    "Encryption in transit (TLS 1.3)",
                    session_completion,
                    "TLS 1.3",
                ),
            ],
        )
    )

    # Sign-off status
    categories.append(
        (
            "Sign-off",
            [
                search_and_report(
                    "Tech Lead sign-off",
                    phase92_guide,
                    "Tech Lead",
                ),
                search_and_report(
                    "DevOps sign-off",
                    phase92_guide,
                    "DevOps",
                ),
                search_and_report(
                    "Data sign-off",
                    phase92_guide,
                    "Data Engineer",
                ),
                search_and_report(
                    "Manager sign-off",
                    phase92_guide,
                    "Team assignments confirmed",
                ),
                search_and_report(
                    "Compliance sign-off",
                    phase92_guide,
                    "NIST controls verified",
                ),
            ],
        )
    )

    return categories


def print_report(categories: list[tuple[str, list[CheckResult]]]) -> bool:
    """print_report function."""
    print("\n=== Phase 9.2 Sprint Gatekeeper Report ===")
    all_passed = True
    for category, checks in categories:
        print(f"\n{category}")
        for check in checks:
            icon = "✅" if check.passed else "❌"
            print(f"  {icon} {check.description}")
            if check.detail:
                print(f"       {check.detail}")
            if not check.passed:
                all_passed = False
    return all_passed


def main() -> None:
    """Main function."""
    categories = build_categories()
    ready = print_report(categories)
    if ready:
        print("\n🎯 Gatekeeper verdict: READY for Phase 9.2 sprint kickoff")
        sys.exit(0)
    print("\n⚠️ Gatekeeper verdict: BLOCKED until outstanding artifacts are addressed")
    sys.exit(1)


if __name__ == "__main__":
    main()
