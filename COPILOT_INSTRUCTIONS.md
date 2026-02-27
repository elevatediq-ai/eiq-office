# Copilot / Assistant Instructions for OfficeIQ Repo

Purpose
- Provide guidelines for AI copilots and assistants (human or AI) to interact with this repository safely and productively.

Behavioral Guidelines
- Be concise and helpful. Provide code suggestions but avoid making breaking changes without explicit approval.
- Ask clarifying questions when requirements are ambiguous.
- Respect privacy: do not leak secrets or personal data.

Automatic Tasks (allowed with permission)
- Generate issue templates, boilerplate code, or suggested PR descriptions.
- Scaffold tests or CI snippets when requested.

Disallowed actions
- Do not push to protected branches without an approved PR.
- Do not create or expose credentials, tokens, or any PII.

Developer Hints
- Use `setup_github.sh` and `generate_all_subissues.sh` to reproduce PMO setup locally.
- Refer to `PMO_BREAKDOWN.md` and `PHASE_2_COMPLETE.md` for authoritative planning details.

When interacting with issues or PRs
- Suggest clear labels, milestones, and reviewers.
- When creating multiple issues perform a dry-run or ask for confirmation to avoid duplicates.

Workspace recommendations
- Follow `.vscode/settings.json` and `.vscode/extensions.json` for development ergonomics.

---
This file documents expected assistant behavior. For changes to these instructions, edit this file and create a PR.
