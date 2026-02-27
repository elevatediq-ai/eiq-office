#!/usr/bin/env bash
# ==============================================================================
# 100X PMO: FedRAMP Gate 1 Evidence Bundler
# ==============================================================================

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PACKAGE_DATE="$(date +%Y%m%d-%H%M%S)"
EVIDENCE_DIR="${REPO_ROOT}/fedramp-evidence-${PACKAGE_DATE}"
SUBMISSION_DIR="${REPO_ROOT}/fedramp-submission-gate1"

echo "📂 Creating submission bundle..."
mkdir -p "$EVIDENCE_DIR"
mkdir -p "$SUBMISSION_DIR"

# Copy all known evidence files
cp "${REPO_ROOT}/docs/management/FINAL_COMPLIANCE_REPORT_FEB18.md" "$EVIDENCE_DIR/"
cp "${REPO_ROOT}/docs/management/FEDRAMP_GATE_1_PROJECT_REPORT.md" "$EVIDENCE_DIR/"
cp "${REPO_ROOT}/docs/management/FEDRAMP_GATE_1_FINAL_CHECKLIST.md" "$EVIDENCE_DIR/"
cp "${REPO_ROOT}/docs/management/PMO_DASHBOARD.md" "$EVIDENCE_DIR/"
cp "${REPO_ROOT}/docs/management/.consolidation/manifest.json" "$EVIDENCE_DIR/"

# Copy baseline tf files for inspection
mkdir -p "$EVIDENCE_DIR/infra"
cp -r "${REPO_ROOT}/infra/phase-a/" "$EVIDENCE_DIR/infra/"
cp -r "${REPO_ROOT}/infra/phase-7/" "$EVIDENCE_DIR/infra/"

# Archive the evidence
cd "$REPO_ROOT"
tar -czf "$SUBMISSION_DIR/elevatediq-gate1-submission-${PACKAGE_DATE}.tar.gz" "fedramp-evidence-${PACKAGE_DATE}"

# Generate checksum
sha256sum "$SUBMISSION_DIR/elevatediq-gate1-submission-${PACKAGE_DATE}.tar.gz" > "$SUBMISSION_DIR/elevatediq-gate1-submission-${PACKAGE_DATE}.sha256"

echo "✅ FedRAMP Gate 1 submission package created: $SUBMISSION_DIR"
echo "✅ Checksum generated: elevatediq-gate1-submission-${PACKAGE_DATE}.sha256"
