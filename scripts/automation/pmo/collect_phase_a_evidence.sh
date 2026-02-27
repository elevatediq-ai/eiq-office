#!/usr/bin/env bash
# Collect Phase-A evidence artifacts for post-deploy verification
# Usage: ./scripts/pmo/collect_phase_a_evidence.sh /tmp/output-dir
set -euo pipefail
OUT_DIR=${1:-/tmp/phase-a-evidence-$(date +%Y%m%dT%H%M%SZ)}
mkdir -p "$OUT_DIR"
echo "[evidence] output -> $OUT_DIR"

# 1) Run smoke tests (finops)
if command -v pytest >/dev/null 2>&1; then
  echo "[evidence] running smoke tests: tests/finops"
  pytest tests/finops -q || true
  mkdir -p "$OUT_DIR/tests/finops"
  # Copy junit if produced
  if [ -f "test_artifacts/phase-a/smoke_unified_query.xml" ]; then
    cp test_artifacts/phase-a/smoke_unified_query.xml "$OUT_DIR/tests/finops/"
  fi
fi

# 2) Collect Terraform plans/logs if present
mkdir -p "$OUT_DIR/terraform_logs"
if compgen -G "logs/terraform/*" >/dev/null; then
  cp -r logs/terraform/* "$OUT_DIR/terraform_logs/" || true
fi

# 3) Collect PMO logs
mkdir -p "$OUT_DIR/pmo_logs"
if compgen -G "logs/pmo/*" >/dev/null; then
  cp -r logs/pmo/* "$OUT_DIR/pmo_logs/" || true
fi

# 4) Collect service logs / orchestrator status
mkdir -p "$OUT_DIR/service_status"
if [ -f "apps/pmo-orchestrator/VALIDATION_REPORT.md" ]; then
  cp apps/pmo-orchestrator/VALIDATION_REPORT.md "$OUT_DIR/service_status/"
fi

# 5) Gather README/checklists for evidence
mkdir -p "$OUT_DIR/docs"
cp -f docs/phase-a/EXECUTION_READINESS.md "$OUT_DIR/docs/" || true
cp -f docs/phase-a/KICKOFF_RUNBOOK_FEB_19.md "$OUT_DIR/docs/" || true

# 6) Compress into artifact
TAR_FILE="phase-a-evidence-$(date +%Y%m%dT%H%M%SZ).tar.gz"
tar -czf "/tmp/$TAR_FILE" -C "$(dirname "$OUT_DIR")" "$(basename "$OUT_DIR")"
echo "[evidence] packaged: /tmp/$TAR_FILE"
# Print artifact path for CI
echo "/tmp/$TAR_FILE"
exit 0
