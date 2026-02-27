#!/usr/bin/env python3
"""Milestone Lifecycle Manager — ElevatedIQ Elite PMO System.

Auto-closes milestones when open_issues reaches 0.
Auto-reopens milestones when an issue is assigned after they were closed.
Provides intelligent milestone health sweep with full audit trail.

NIST: PM-5 (Program Management), PM-6 (Measures of Performance)

Commands:
  sweep          Sweep all milestones: close empty ones, reopen non-empty closed ones
  on-close <N>   React to issue #N being closed (check if parent milestone hits 0)
  on-open  <N>   React to issue #N being opened/reassigned (reopen milestone if needed)
  status         Print milestone health dashboard
  smart-assign <N>  Classify issue #N and assign optimal milestone

Usage:
  python3 milestone_lifecycle_manager.py sweep
  python3 milestone_lifecycle_manager.py on-close 4234
  python3 milestone_lifecycle_manager.py on-open 4240
  python3 milestone_lifecycle_manager.py smart-assign 4250
  python3 milestone_lifecycle_manager.py status

Env:
  REPO        GitHub repository (default: kushin77/ElevatedIQ-Mono-Repo)
  DRY_RUN     "true" to skip writes (default: false)
  VERBOSE     "true" for debug output
"""

from __future__ import annotations

import json
import logging
import os
import re
import subprocess
import sys
from dataclasses import dataclass, field
from datetime import UTC, datetime

# ─────────────────────────────── Config ──────────────────────────────────────

REPO = os.environ.get("REPO", "kushin77/ElevatedIQ-Mono-Repo")
DRY_RUN = os.environ.get("DRY_RUN", "false").lower() == "true"
VERBOSE = os.environ.get("VERBOSE", "false").lower() == "true"

logging.basicConfig(
    level=logging.DEBUG if VERBOSE else logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%SZ",
)
log = logging.getLogger("milestone-lifecycle")

# Milestones never auto-closed (catch-all buckets)
PROTECTED_MILESTONES: set[str] = {
    "Project Eta: Backlog",
    "Backlog",
}

# ──────────────────────────── Data classes ───────────────────────────────────


@dataclass
class Milestone:
    """Milestone class."""

    id: int
    number: int
    title: str
    state: str  # "open" | "closed"
    open_issues: int
    closed_issues: int
    description: str = ""
    due_on: str | None = None

    @property
    def total_issues(self) -> int:
        """total_issues method."""
        return self.open_issues + self.closed_issues

    @property
    def completion_pct(self) -> float:
        """completion_pct method."""
        if self.total_issues == 0:
            return 0.0
        return round(self.closed_issues / self.total_issues * 100, 1)

    @property
    def is_protected(self) -> bool:
        """is_protected method."""
        return self.title in PROTECTED_MILESTONES


@dataclass
class Issue:
    """Issue class."""

    number: int
    title: str
    state: str
    labels: list[str] = field(default_factory=list)
    milestone_number: int | None = None
    body: str = ""


@dataclass
class LifecycleAction:
    """LifecycleAction class."""

    action: str  # "closed_milestone" | "reopened_milestone" | "no_change"
    milestone_title: str
    milestone_number: int
    reason: str
    timestamp: str = field(default_factory=lambda: datetime.now(UTC).isoformat() + "Z")


# ────────────────────────────── GitHub API ───────────────────────────────────


def _gh(*args: str, check: bool = True) -> str:
    """Run a gh CLI command and return stdout."""
    cmd = ["gh", *args]
    log.debug("Running: %s", " ".join(cmd))
    result = subprocess.run(cmd, capture_output=True, text=True)
    if check and result.returncode != 0:
        log.error("gh error: %s", result.stderr.strip())
        raise RuntimeError(f"gh command failed: {' '.join(cmd)}\n{result.stderr}")
    return result.stdout.strip()


def _gh_api(path: str, method: str = "GET", fields: dict | None = None) -> dict | list:
    """Call GitHub REST API via gh api."""
    args = ["api", f"/repos/{REPO}/{path}"]
    if method != "GET":
        args += ["-X", method]
    if fields:
        for k, v in fields.items():
            args += ["-f", f"{k}={v}"]
    raw = _gh(*args)
    return json.loads(raw) if raw else {}


def _gh_api_paginated(path: str) -> list[dict]:
    """Fetch all pages of a GitHub REST endpoint."""
    results: list[dict] = []
    page = 1
    while True:
        sep = "&" if "?" in path else "?"
        raw = _gh("api", f"/repos/{REPO}/{path}{sep}per_page=100&page={page}")
        batch: list[dict] = json.loads(raw) if raw else []
        if not batch:
            break
        results.extend(batch)
        if len(batch) < 100:
            break
        page += 1
    return results


def list_milestones(state: str = "all") -> list[Milestone]:
    """List all milestones (open + closed)."""
    raw = _gh_api_paginated(f"milestones?state={state}&direction=asc")
    out: list[Milestone] = []
    for m in raw:
        out.append(
            Milestone(
                id=m["id"],
                number=m["number"],
                title=m["title"],
                state=m["state"],
                open_issues=m["open_issues"],
                closed_issues=m["closed_issues"],
                description=m.get("description") or "",
                due_on=m.get("due_on"),
            )
        )
    return out


def get_issue(number: int) -> Issue:
    """Fetch a single issue by number."""
    data = _gh_api(f"issues/{number}")
    return Issue(
        number=data["number"],
        title=data["title"],
        state=data["state"],
        labels=[lbl["name"] for lbl in data.get("labels", [])],
        milestone_number=(data.get("milestone") or {}).get("number"),
        body=data.get("body") or "",
    )


def close_milestone(m: Milestone, reason: str) -> LifecycleAction:
    """Close a milestone via API."""
    log.info("🔒 Closing milestone #%d '%s' — %s", m.number, m.title, reason)
    if not DRY_RUN:
        _gh_api(f"milestones/{m.number}", method="PATCH", fields={"state": "closed"})
        # Leave audit comment on the milestone's most-recently-closed issue (best-effort)
        _post_milestone_closed_comment(m, reason)
    return LifecycleAction(
        action="closed_milestone",
        milestone_title=m.title,
        milestone_number=m.number,
        reason=reason,
    )


def reopen_milestone(m: Milestone, reason: str) -> LifecycleAction:
    """Reopen a milestone via API."""
    log.info("🔓 Reopening milestone #%d '%s' — %s", m.number, m.title, reason)
    if not DRY_RUN:
        _gh_api(f"milestones/{m.number}", method="PATCH", fields={"state": "open"})
        _post_milestone_reopened_comment(m, reason)
    return LifecycleAction(
        action="reopened_milestone",
        milestone_title=m.title,
        milestone_number=m.number,
        reason=reason,
    )


def _post_milestone_closed_comment(m: Milestone, reason: str) -> None:
    """Post a comment on a recently-closed issue explaining milestone auto-close."""
    try:
        # Find the most-recently-closed issue in this milestone to comment on
        raw = _gh(
            "api",
            f"/repos/{REPO}/issues?milestone={m.number}&state=closed&per_page=1&sort=updated&direction=desc",
            check=False,
        )
        issues = json.loads(raw) if raw else []
        if issues:
            issue_number = issues[0]["number"]
            body = (
                f"🔒 **Milestone Auto-Closed**: `{m.title}` has reached **0 open issues** "
                f"and has been automatically closed.\n\n"
                f"**Reason**: {reason}\n"
                f"**Completion**: {m.completion_pct}% ({m.closed_issues}/{m.total_issues} issues)\n"
                f"**Auto-reopen**: Will reopen automatically if a new issue is assigned.\n\n"
                f"_NIST PM-6 | ElevatedIQ Milestone Lifecycle Manager_"
            )
            _gh(
                "issue",
                "comment",
                str(issue_number),
                "--repo",
                REPO,
                "--body",
                body,
                check=False,
            )
    except Exception as exc:  # noqa: BLE001
        log.debug("Could not post close comment: %s", exc)


def _post_milestone_reopened_comment(m: Milestone, reason: str) -> None:
    """Post a comment on the triggering issue explaining milestone auto-reopen."""
    try:
        raw = _gh(
            "api",
            f"/repos/{REPO}/issues?milestone={m.number}&state=open&per_page=1&sort=updated&direction=desc",
            check=False,
        )
        issues = json.loads(raw) if raw else []
        if issues:
            issue_number = issues[0]["number"]
            body = (
                f"🔓 **Milestone Auto-Reopened**: `{m.title}` was re-opened because "
                f"it now has **{m.open_issues} open issue(s)**.\n\n"
                f"**Reason**: {reason}\n\n"
                f"_NIST PM-6 | ElevatedIQ Milestone Lifecycle Manager_"
            )
            _gh(
                "issue",
                "comment",
                str(issue_number),
                "--repo",
                REPO,
                "--body",
                body,
                check=False,
            )
    except Exception as exc:  # noqa: BLE001
        log.debug("Could not post reopen comment: %s", exc)


# ─────────────────────────── Core lifecycle logic ────────────────────────────


def sweep() -> list[LifecycleAction]:
    """Full sweep: close empty open milestones, reopen non-empty closed milestones."""
    log.info("═══ MILESTONE LIFECYCLE SWEEP — %s ═══", REPO)
    milestones = list_milestones(state="all")
    log.info("Found %d milestones total", len(milestones))

    actions: list[LifecycleAction] = []

    for m in milestones:
        if m.is_protected:
            log.debug("Skipping protected milestone '%s'", m.title)
            continue

        if m.state == "open" and m.open_issues == 0 and m.total_issues > 0:
            # All work done → auto-close
            actions.append(
                close_milestone(
                    m,
                    f"All {m.closed_issues} issues completed ({m.completion_pct}% completion rate)",
                )
            )

        elif m.state == "closed" and m.open_issues > 0:
            # Work re-opened / new issue assigned → auto-reopen
            actions.append(
                reopen_milestone(
                    m,
                    f"{m.open_issues} open issue(s) found in closed milestone",
                )
            )

    if not actions:
        log.info("✅ All milestones are in correct lifecycle state — no changes needed")
    else:
        log.info("Applied %d lifecycle action(s)", len(actions))
        for a in actions:
            log.info("  [%s] #%d '%s' — %s", a.action, a.milestone_number, a.milestone_title, a.reason)

    return actions


def on_issue_close(issue_number: int) -> list[LifecycleAction]:
    """React to an issue being closed — check if its milestone should auto-close."""
    log.info("Issue #%d closed — checking parent milestone", issue_number)
    issue = get_issue(issue_number)

    if issue.milestone_number is None:
        log.info("Issue #%d has no milestone — nothing to do", issue_number)
        return []

    milestones = list_milestones(state="open")
    m = next((ms for ms in milestones if ms.number == issue.milestone_number), None)
    if m is None:
        log.info("Milestone #%d not found or already closed", issue.milestone_number)
        return []

    if m.is_protected:
        log.debug("Milestone '%s' is protected — skipping", m.title)
        return []

    # Re-fetch milestone to get fresh counts (GitHub webhooks can lag)
    fresh = _gh_api(f"milestones/{m.number}")
    m.open_issues = fresh["open_issues"]
    m.closed_issues = fresh["closed_issues"]

    if m.open_issues == 0 and m.total_issues > 0:
        return [close_milestone(m, f"Issue #{issue_number} was the last open issue")]
    else:
        log.info("Milestone '%s' still has %d open issue(s) — no change", m.title, m.open_issues)
        return []


def on_issue_open(issue_number: int) -> list[LifecycleAction]:
    """React to an issue being opened/milestoned — reopen closed milestone if needed."""
    log.info("Issue #%d opened/assigned — checking parent milestone", issue_number)
    issue = get_issue(issue_number)

    if issue.milestone_number is None:
        log.info("Issue #%d has no milestone — nothing to do", issue_number)
        return []

    milestones = list_milestones(state="closed")
    m = next((ms for ms in milestones if ms.number == issue.milestone_number), None)
    if m is None:
        log.debug("Milestone #%d is open or doesn't exist — no reopen needed", issue.milestone_number)
        return []

    if m.is_protected:
        return []

    # Re-fetch for fresh counts
    fresh = _gh_api(f"milestones/{m.number}")
    m.open_issues = fresh["open_issues"]

    if m.open_issues > 0:
        return [reopen_milestone(m, f"Issue #{issue_number} assigned to closed milestone")]
    return []


# ─────────────────────────── Smart assignment ────────────────────────────────

# Intelligent classification rules: each entry is (pattern, milestone_title, weight)
CLASSIFICATION_RULES: list[tuple[re.Pattern, str, float]] = [
    # Infrastructure / DevOps
    (
        re.compile(
            r"\b(terraform|infra|k8s|kubernetes|deploy|helm|iac|cloud|aws|gcp|azure|eks|gke|aks|vpc|subnet|route53|alb|nlb|rds|redis|elasticache|s3|bucket|ecs|fargate|argo|gitops|packer|ansible)\b",
            re.I,
        ),
        "Project Gamma: Infrastructure",
        1.0,
    ),
    (
        re.compile(
            r"\b(monitor|observ|metric|prom|grafana|opentelemetry|tracing|jaeger|zipkin|sli|slo|sla|uptime|latency|p99|throughput|scaling|hpa|vpa|autoscal|load.?test|chaos)\b",
            re.I,
        ),
        "Project Gamma: Infrastructure",
        0.8,
    ),
    # Security / Compliance
    (
        re.compile(
            r"\b(secur|auth|authz|oauth|jwt|tls|cert|encrypt|fedramp|nist|cmmc|sox|soc2|hipaa|pci|cve|vuln|pentest|sast|dast|owasp|iam|rbac|abac|zero.?trust|secret|vault|hsm|fips|audit|siem|soc)\b",
            re.I,
        ),
        "Project Delta: Security & Compliance",
        1.0,
    ),
    (
        re.compile(
            r"\b(incident|escalat|alert|breach|threat|annomaly|anomaly|intrusion|dlp|waf|firewall|ids|ips|edr)\b", re.I
        ),
        "Project Delta: Security & Compliance",
        0.7,
    ),
    # AI / ML
    (
        re.compile(
            r"\b(ai|ml|llm|gpt|claude|embed|inference|model|train|finetune|rag|vector|semantic|nlp|transformers|langchain|openai|anthropic|bedrock|sagemaker|mlflow|kubeflow|pytorch|tensorflow)\b",
            re.I,
        ),
        "Project Beta: AI Intelligence",
        1.0,
    ),
    (
        re.compile(
            r"\b(predict|forecast|classif|cluster|detect|anomal|recommend|personali|insight|analytic|dashboard|bi|warehouse|dbt|spark|flink|kafka|pubsub|stream|pipeline|etl|elt)\b",
            re.I,
        ),
        "Project Beta: AI Intelligence",
        0.7,
    ),
    # FinOps / Cost
    (
        re.compile(
            r"\b(cost|finops|billing|budget|sav|optim|rightsiz|commit|reserv|spot|saving.?plan|ri\b|cu\b|waste|spend|roi|chargeback|showback|cloud.?cost|athena|cur|cost.?explorer)\b",
            re.I,
        ),
        "Project Sigma: FinOps",
        1.0,
    ),
    # PMO / Management
    (
        re.compile(
            r"\b(pmo|milestone|sprint|epic|story|backlog|roadmap|kpi|okr|retro|standup|velocity|burndown|capacit|session|track|manage|governance)\b",
            re.I,
        ),
        "Project Omega: PMO Excellence",
        1.0,
    ),
    # Testing / QA
    (
        re.compile(
            r"\b(test|coverage|unit|integration|e2e|smoke|regression|pytest|jest|mocha|cypress|selenium|playwright|benchmark|perf.?test|qa|quality)\b",
            re.I,
        ),
        "Project Kappa: Test Coverage",
        0.9,
    ),
    # API / Core platform
    (
        re.compile(
            r"\b(api|rest|grpc|graphql|endpoint|route|controller|service|micro.?service|gateway|proxy|nginx|envoy|istio|mesh)\b",
            re.I,
        ),
        "Project Alpha: Core Platform",
        0.8,
    ),
    # Data / Database
    (
        re.compile(
            r"\b(database|postgres|mysql|mongo|dynamo|cassandra|schema|migrat|sql|nosql|orm|data.?model|backup|restore|replicat|sharding|partition)\b",
            re.I,
        ),
        "Project Alpha: Core Platform",
        0.6,
    ),
]

# Fallback milestone (always available as catch-all)
FALLBACK_MILESTONE = "Project Eta: Backlog"


@dataclass
class ClassificationResult:
    """ClassificationResult class."""

    milestone_title: str
    confidence: float
    matched_rules: list[str]
    matched_text: list[str]


def classify_issue(issue: Issue) -> ClassificationResult:
    """Classify an issue using the rule engine and return the best milestone."""
    corpus = f"{issue.title} {issue.body} {' '.join(issue.labels)}".lower()

    scores: dict[str, float] = {}
    matched_rules: dict[str, list[str]] = {}
    matched_text: dict[str, list[str]] = {}

    for pattern, milestone, weight in CLASSIFICATION_RULES:
        hits = pattern.findall(corpus)
        if hits:
            scores[milestone] = scores.get(milestone, 0.0) + weight * len(hits)
            matched_rules.setdefault(milestone, []).append(pattern.pattern[:60])
            matched_text.setdefault(milestone, []).extend(set(h.lower() for h in hits[:5]))

    if not scores:
        return ClassificationResult(
            milestone_title=FALLBACK_MILESTONE,
            confidence=0.1,
            matched_rules=[],
            matched_text=[],
        )

    best = max(scores, key=lambda k: scores[k])
    raw_score = scores[best]
    # Normalise to 0–1 range (cap at 1.0 for multi-rule matches)
    confidence = min(1.0, raw_score / 3.0)

    return ClassificationResult(
        milestone_title=best,
        confidence=round(confidence, 3),
        matched_rules=matched_rules.get(best, []),
        matched_text=matched_text.get(best, []),
    )


def _get_milestone_number(title: str, milestones: list[Milestone]) -> int | None:
    """Map milestone title to its GitHub number."""
    for m in milestones:
        if m.title == title:
            return m.number
    return None


def smart_assign(issue_number: int, dry_run_override: bool | None = None) -> dict:
    """Classify issue and assign it to the best milestone."""
    effective_dry_run = DRY_RUN if dry_run_override is None else dry_run_override
    issue = get_issue(issue_number)
    result = classify_issue(issue)
    milestones = list_milestones(state="open")

    log.info(
        "Issue #%d '%s' → '%s' (confidence=%.2f, matches=%s)",
        issue_number,
        issue.title,
        result.milestone_title,
        result.confidence,
        result.matched_text[:5],
    )

    milestone_number = _get_milestone_number(result.milestone_title, milestones)
    if milestone_number is None:
        log.warning("Milestone '%s' not found or closed — falling back to Backlog", result.milestone_title)
        milestone_number = _get_milestone_number(FALLBACK_MILESTONE, milestones)

    if milestone_number and not effective_dry_run:
        _gh(
            "issue",
            "edit",
            str(issue_number),
            "--repo",
            REPO,
            "--milestone",
            str(milestone_number),
        )
        log.info(
            "✅ Assigned issue #%d to milestone '%s' (#%d)", issue_number, result.milestone_title, milestone_number
        )

    return {
        "issue": issue_number,
        "assigned_milestone": result.milestone_title,
        "milestone_number": milestone_number,
        "confidence": result.confidence,
        "matched_terms": result.matched_text,
        "dry_run": effective_dry_run,
    }


# ──────────────────────────── Status dashboard ───────────────────────────────


def status() -> None:
    """Print a milestone health dashboard."""
    milestones = list_milestones(state="all")
    open_ms = [m for m in milestones if m.state == "open"]
    closed_ms = [m for m in milestones if m.state == "closed"]

    print(f"\n{'═' * 70}")
    print(f"  ElevatedIQ Milestone Health Dashboard — {datetime.now(UTC).strftime('%Y-%m-%d %H:%M UTC')}")
    print(f"  Repo: {REPO}   DRY_RUN={DRY_RUN}")
    print(f"{'═' * 70}")
    print(f"  Open: {len(open_ms)}   Closed: {len(closed_ms)}   Total: {len(milestones)}")
    print()

    # Warn: open milestones with 0 open issues (should be closed)
    should_close = [m for m in open_ms if m.open_issues == 0 and m.total_issues > 0 and not m.is_protected]
    if should_close:
        print(f"  ⚠️  SHOULD BE CLOSED ({len(should_close)} milestones — all issues done):")
        for m in should_close:
            print(f"     #{m.number:4d}  {m.title:<50s}  ✅{m.closed_issues} closed")

    # Warn: closed milestones with open issues (should be reopened)
    should_reopen = [m for m in closed_ms if m.open_issues > 0 and not m.is_protected]
    if should_reopen:
        print(f"\n  ⚠️  SHOULD BE REOPENED ({len(should_reopen)} milestones — have open issues):")
        for m in should_reopen:
            print(f"     #{m.number:4d}  {m.title:<50s}  🔴{m.open_issues} open")

    print(f"\n  {'─' * 66}")
    print(f"  {'#':>5}  {'Title':<50s}  {'State':<8}  {'Open':>5}  {'Done':>5}  {'%':>5}")
    print(f"  {'─' * 66}")
    for m in sorted(milestones, key=lambda x: x.number):
        flag = " ⚠️ " if (m in should_close or m in should_reopen) else "    "
        print(
            f"  {m.number:>5}{flag}{m.title:<50s}  {m.state:<8}  {m.open_issues:>5}  "
            f"{m.closed_issues:>5}  {m.completion_pct:>4.0f}%"
        )
    print(f"{'═' * 70}\n")


# ───────────────────────────────── CLI ───────────────────────────────────────


def main() -> int:  # noqa: PLR0911
    """Main function."""
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        return 0

    cmd = args[0]

    if cmd == "sweep":
        actions = sweep()
        # JSON output for GH Actions summary
        print(json.dumps([vars(a) for a in actions], indent=2))
        return 0

    elif cmd == "on-close" and len(args) >= 2:
        actions = on_issue_close(int(args[1]))
        print(json.dumps([vars(a) for a in actions], indent=2))
        return 0

    elif cmd == "on-open" and len(args) >= 2:
        actions = on_issue_open(int(args[1]))
        print(json.dumps([vars(a) for a in actions], indent=2))
        return 0

    elif cmd == "smart-assign" and len(args) >= 2:
        result = smart_assign(int(args[1]))
        print(json.dumps(result, indent=2))
        return 0

    elif cmd == "status":
        status()
        return 0

    else:
        print(f"Unknown command: {cmd}\n")
        print(__doc__)
        return 1


if __name__ == "__main__":
    sys.exit(main())
