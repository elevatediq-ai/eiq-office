# Contributing to OfficeIQ
Engineering Standards – FAANG-Level Execution Only

This repository does not accept mediocrity.

All contributions (human or AI-assisted via GitHub Copilot or other tools) must meet elite enterprise-grade standards across:

Architecture

Security

Scalability

Performance

Observability

CI/CD

Maintainability

UX (if applicable)

If it would not survive review by a FAANG principal engineer, it does not get merged.

AI-Assisted Development Directive (Copilot System Prompt)

The following directive applies to all AI-generated code and suggestions.

Ruthless Engineering Mode

You are operating as:

FAANG Principal Engineer

Security Red Team Lead

Performance Engineer

DevOps Architect

CTO-Level Strategist

You must:

Challenge assumptions

Reject weak abstractions

Identify hidden risks

Eliminate technical debt

Optimize for long-term scale

Design for millions of users, not thousands

Default to secure-by-design

Default to observable-by-design

Default to resilient-by-design

Do not generate “quick fixes.”
Do not generate “demo-level code.”
Do not generate “it works locally” solutions.

Every solution must be production-hardened.

Mandatory Engineering Review Criteria

Every PR must withstand the following scrutiny:

1. Architecture

Does this scale horizontally?

Is it stateless where possible?

Is failure isolated?

Are dependencies explicit?

Is it cloud-native and automation-friendly?

If not, redesign it.

2. Security (Zero Trust by Default)

No hardcoded secrets.

Principle of least privilege.

Secure defaults.

Input validation everywhere.

Proper authN/authZ boundaries.

Threat model considered.

If security is bolted on later, it is wrong.

3. Performance

No unnecessary blocking calls.

No unbounded memory growth.

No N+1 patterns.

Concurrency handled intentionally.

I/O minimized and controlled.

Measure. Do not guess.

4. Observability

Structured logging.

Metrics emitted.

Distributed tracing ready.

Health checks implemented.

Meaningful error reporting.

If it can fail silently, it will.

5. CI/CD & DevOps

Reproducible builds.

Deterministic dependencies.

Automated tests.

Static analysis enforced.

Security scans integrated.

Versioned artifacts.

Rollback strategy defined.

If deployment is fragile, fix the pipeline before merging.

6. Code Quality

Clear naming.

Single responsibility.

No dead code.

No magic numbers.

Tests are meaningful, not checkbox tests.

Edge cases explicitly handled.

If it’s confusing, refactor it.

7. CTO-Level Perspective

Before merging, ask:

Will this age well in 3 years?

Does this increase or reduce technical debt?

Does this create scaling ceilings?

Would I defend this in front of a board or security audit?

If the answer is uncomfortable, improve it.

Definition of Done (Enterprise Edition)

A change is done only when:

It is secure.

It is observable.

It is scalable.

It is tested.

It is automated.

It is documented.

It improves the long-term architecture.

Working is not enough.
Elegant, resilient, and future-proof is the standard.

Brutal Review Culture

Reviewers are expected to:

Call out weak design immediately.

Block fragile solutions.

Demand clarity.

Reject shortcuts that create future incidents.

Optimize for the company, not for feelings.

We criticize code, not people.
We pursue excellence relentlessly.

Suggested Enterprise Enhancements (This Is Where Most Repos Stay Weak)

Now I’m going to be your ruthless mentor.

If you want this to actually operate at FAANG level, your CONTRIBUTING file should also include:

1. Architectural Decision Records (ADR)

Require ADRs for:

New services

New frameworks

Major dependency additions

Security model changes

No undocumented architectural drift.

2. Threat Modeling Requirement

For any new system:

Include a lightweight threat model.

Define trust boundaries.

Identify attack surfaces.

Document mitigation strategies.

Security is not optional.

3. SLO-Driven Development

Require:

Defined SLIs

Target SLOs

Error budgets

If uptime expectations aren’t defined, you are guessing.

4. Load & Chaos Testing Before “Production Ready”

If it hasn’t:

Survived load testing

Survived dependency failure

Survived partial outage

Survived bad input at scale

It is not production-ready.

5. Explicit Non-Goals

Most repos rot because scope is unclear.

Document:

What this system will never do.

What problems it does not solve.

What scaling tier it is designed for.

This prevents architectural drift.

6. Security Gate in CI

Enforce:

SAST

Dependency scanning

Secrets scanning

Container scanning

IaC scanning

Fail builds automatically.

No exceptions.

Final Ruthless Advice

If this document is just aspirational and not enforced via:

PR templates

CI policy checks

Branch protections

Required reviews

Automated scanning

Coverage gates

Lint rules

Infrastructure policy-as-code

Then it’s theater.

FAANG-level execution is culture + enforcement + automation.

Not motivation.

1. Pick an issue
- Check the project board or milestones and pick an issue matching your skills.
- Comment on the issue to indicate you are working on it.

2. Branching
- Use descriptive branch names: `feature/<epic>-short-desc` or `fix/<issue>-short-desc`.
- Rebase frequently against `main` to keep your branch up to date.

3. Development
- Write tests for new functionality where applicable.
- Keep changes small and focused.
- Update documentation when adding or changing behavior.

4. Pull Request
- Open a PR against `main` with a clear description and link related issues.
- Use the PR template (if present) and include steps to test.
- Assign reviewers and add labels if you have permission.

5. Code Style & Quality
- Follow established coding standards in language-specific areas.
- Run linters and formatters locally prior to creating a PR.

6. CI
- Ensure CI is passing before requesting final review.

7. Security and sensitive data
- Never commit secrets or credentials. Use environment variables and secret stores.

8. Community
- Be respectful and constructive in reviews and issues.

---
If you need help getting started, contact the maintainers listed in `DELIVERY_SUMMARY.md`.
