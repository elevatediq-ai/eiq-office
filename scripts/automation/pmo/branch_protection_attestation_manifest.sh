#!/usr/bin/env bash

set -euo pipefail

EVIDENCE_DIR="${1:-artifacts/governance/branch-protection}"
OUTPUT_DIR="${2:-artifacts/governance/branch-protection-attestation}"
REPO="${3:-kushin77/ElevatedIQ-Mono-Repo}"
BRANCH="${4:-main}"
GENERATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

mkdir -p "$OUTPUT_DIR"

latest_bundle=$(ls -1t "$EVIDENCE_DIR"/branch_protection_evidence_*.tar.gz 2>/dev/null | head -n 1 || true)
if [[ -z "$latest_bundle" ]]; then
  echo "❌ No evidence bundle found in $EVIDENCE_DIR"
  exit 1
fi

bundle_sha256=$(sha256sum "$latest_bundle" | awk '{print $1}')
manifest_file="$OUTPUT_DIR/attestation_manifest_${GENERATED_AT//[:]/}_UTC.json"
checksum_file="$OUTPUT_DIR/attestation_manifest_${GENERATED_AT//[:]/}_UTC.sha256"

cat > "$manifest_file" <<EOF
{
  "generated_at_utc": "$GENERATED_AT",
  "repository": "$REPO",
  "branch": "$BRANCH",
  "attestation_type": "branch-protection-governance-quarterly",
  "evidence": {
    "bundle_path": "$latest_bundle",
    "bundle_sha256": "$bundle_sha256"
  },
  "control_assertions": {
    "required_contexts": [
      "Workspace Health Check / commit-hygiene",
      "kms-smoke",
      "rotation-smoke"
    ],
    "strict_required_checks_expected": true,
    "code_owner_reviews_expected": true
  }
}
EOF

sha256sum "$manifest_file" > "$checksum_file"

echo "✅ Attestation manifest generated"
echo "   manifest: $manifest_file"
echo "   checksum: $checksum_file"
echo "   evidence_bundle: $latest_bundle"
