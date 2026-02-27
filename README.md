# OfficeIQ

Enterprise-grade Office + Meeting Intelligence platform — Phase 2 PMO

This repository contains the strategic roadmap and automation used to create the epics, tasks and milestones needed to deliver OfficeIQ.

Quick links
- Issues: https://github.com/kushin77/OfficeIQ/issues
- Milestones: https://github.com/kushin77/OfficeIQ/milestones

Summary
- 25 Epics across 5 pillars: Meeting Intelligence, Documents, Messaging, Humanizer, Infrastructure
- 140+ sub-tasks with story points and acceptance criteria
- 10 sequential sprint milestones (S1..S10) covering ~20 weeks

Repository Layout (high level)
- `PMO_BREAKDOWN.md`, `EXECUTIVE_SUMMARY.md` — high-level strategy and board-level summary
- `EPIC_*_DETAILED.md` — example epic deep-dive and acceptance criteria
- `scripts/` — automation (issue generation, helpers)
- `setup_github.sh` — labels, milestones, initial setup
- `generate_all_subissues.sh` — creates sub-issues via `gh` or GitHub API
- `PHASE_2_COMPLETE.md` — verification & status for Phase 2

Getting started
1. Clone the repo
```bash
git clone https://github.com/kushin77/OfficeIQ.git
cd OfficeIQ
```
2. Inspect milestones and issues on GitHub. Begin with `Sprint 1: Meeting Intelligence Foundation`.
3. Read `README_PMO_BREAKDOWN.md` and `EPIC_1_1_DETAILED.md` for design details and acceptance tests.

Branching & PR workflow
- Branch from `main` using descriptive names: `feature/1.1-transcription-gpu` or `fix/ci-config`.
- Link PRs to issues using the issue number in the PR description (e.g. `Fixes #36`).
- Add reviewers, include test/QA instructions in PR body.

Contribution guidelines, coding standards, workspace configs, and Copilot instructions are provided in the repository (`CONTRIBUTING.md`, `COPILOT_INSTRUCTIONS.md`, `.vscode/`) to ensure consistent developer experience.

Maintainers
- Owner: kushin77
- PMO: See `DELIVERY_SUMMARY.md` for contact and escalation

License
- Add a license if you want to publish; none included by default.

---
For detailed onboarding and sprint planning follow `PHASE_2_COMPLETE.md` and the issues/milestones in GitHub.
# OfficeIQ
