#!/usr/bin/env bash

set -euo pipefail

REPO="${1:-kushin77/ElevatedIQ-Mono-Repo}"
BRANCH="${2:-main}"
OUTPUT_DIR="${3:-artifacts/governance/branch-protection}"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BUNDLE_DIR="${OUTPUT_DIR}/bundle_${TIMESTAMP}"

INCIDENT_TITLES=(
  "🚨 Branch protection drift detected on main"
  "🚨 Branch protection drift remediation failed on main"
  "🛠️ Branch protection drift remediated on main"
)

mkdir -p "$BUNDLE_DIR"

if ! command -v gh >/dev/null 2>&1; then
  echo "❌ GitHub CLI (gh) is required."
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "❌ jq is required."
  exit 1
fi

echo "📦 Exporting branch protection governance evidence"
echo "   repo: ${REPO}"
echo "   branch: ${BRANCH}"
echo "   output: ${BUNDLE_DIR}"

# Snapshot branch protection
GH_HOST_REPO="repos/${REPO}/branches/${BRANCH}/protection"
gh api "$GH_HOST_REPO" > "${BUNDLE_DIR}/branch_protection_snapshot.json"

# Collect incident issues
ISSUES_JSON="${BUNDLE_DIR}/incident_issues.json"
gh issue list --repo "$REPO" --state all --limit 200 --json number,title,state,createdAt,closedAt,url > "$ISSUES_JSON"

# Build title filter regex safely
TITLE_REGEX=$(printf '%s|' "${INCIDENT_TITLES[@]}" | sed 's/|$//')

jq --arg re "${TITLE_REGEX}" '
  map(select(.title | test($re)))
' "$ISSUES_JSON" > "${BUNDLE_DIR}/incident_issues_filtered.json"

OPEN_COUNT=$(jq '[.[] | select(.state == "OPEN")] | length' "${BUNDLE_DIR}/incident_issues_filtered.json")
CLOSED_COUNT=$(jq '[.[] | select(.state == "CLOSED")] | length' "${BUNDLE_DIR}/incident_issues_filtered.json")
TOTAL_COUNT=$(jq 'length' "${BUNDLE_DIR}/incident_issues_filtered.json")

cat > "${BUNDLE_DIR}/summary.json" <<EOF
{
  "generated_at_utc": "${TIMESTAMP}",
  "repository": "${REPO}",
  "branch": "${BRANCH}",
  "controls": {
    "required_contexts": [
      "Workspace Health Check / commit-hygiene",
      "kms-smoke",
      "rotation-smoke"
    ],
    "strict_required_checks_expected": true,
    "code_owner_reviews_expected": true
  },
  "incident_metrics": {
    "open": ${OPEN_COUNT},
    "closed": ${CLOSED_COUNT},
    "total": ${TOTAL_COUNT}
  },
  "files": [
    "branch_protection_snapshot.json",
    "incident_issues_filtered.json",
    "summary.json"
  ]
}
EOF

# Tarball bundle for transport
TARBALL="${OUTPUT_DIR}/branch_protection_evidence_${TIMESTAMP}.tar.gz"
tar -czf "$TARBALL" -C "$OUTPUT_DIR" "bundle_${TIMESTAMP}"

echo "✅ Evidence export complete"
echo "   bundle_dir: ${BUNDLE_DIR}"
echo "   tarball: ${TARBALL}"
