#!/bin/bash

# Purpose: Standardized script functionality managed by Elite PMO/usr/bin/env bash
set -euo pipefail
REPO="kushin77/ElevatedIQ-Mono-Repo"

echo "[close_phase6] Commenting and closing Phase 6 epics (#2605, #2615)"
gh issue comment 2605 --repo "$REPO" --body "Closing: Phase 6 implementation considered delivered. Artifacts: docs/PHASE_6_DEPLOYMENT_PACKAGE.md, docs/PHASE_6_EXECUTION_PLAN_FINAL.md, libs/security/ (SecurityOrchestrator & managers). Validated by local smoke tests and ./scripts/eiq validate. Refs #2569" || true
gh issue edit 2605 --repo "$REPO" --state closed || true

gh issue comment 2615 --repo "$REPO" --body "Closing: Cross-Cloud Mesh and Identity federation delivered per execution plan. Artifacts: docs/PHASE_6_DEPLOYMENT_PACKAGE.md, infra/ (SPIRE/Istio manifests), libs/security/identity_mesh_v2.py. Validated by local smoke tests and ./scripts/eiq validate. Refs #2569" || true
gh issue edit 2615 --repo "$REPO" --state closed || true

echo "[close_phase6] Marking Sprint 1 Epic #2624 in-progress and adding comment"
gh issue edit 2624 --repo "$REPO" --add-label "status: in-progress" || true
gh issue comment 2624 --repo "$REPO" --body "Sprint 1 execution: LSTM + Dashboard + Canary are now in-progress. Pre-deployment validation passed locally; schedule canary rollout for Feb 16. Assigned subtasks remain tracked under #2630-2634. Refs #2624" || true

echo "[close_phase6] Completed (some commands may have been non-fatal if already applied)."
