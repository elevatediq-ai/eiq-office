#!/usr/bin/env bash

set -euo pipefail

REPO="${1:-kushin77/ElevatedIQ-Mono-Repo}"
OUTPUT_DIR="${2:-artifacts/governance/branch-protection-sla}"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"

mkdir -p "$OUTPUT_DIR"

if ! command -v gh >/dev/null 2>&1; then
  echo "❌ GitHub CLI (gh) is required."
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "❌ jq is required."
  exit 1
fi

INCIDENT_FILE="$OUTPUT_DIR/incidents_${TIMESTAMP}.json"
SUMMARY_FILE="$OUTPUT_DIR/sla_kpi_${TIMESTAMP}.json"

echo "📈 Generating branch protection SLA KPIs"
echo "   repo: ${REPO}"
echo "   output: ${OUTPUT_DIR}"

gh issue list --repo "$REPO" --state all --limit 300 --json number,title,state,createdAt,closedAt,url > "$INCIDENT_FILE"

jq '
  [ .[] | select(
      .title == "🚨 Branch protection drift detected on main" or
      .title == "🚨 Branch protection drift remediation failed on main" or
      .title == "🛠️ Branch protection drift remediated on main"
    ) ]
' "$INCIDENT_FILE" > "$OUTPUT_DIR/incidents_filtered_${TIMESTAMP}.json"

TOTAL=$(jq 'length' "$OUTPUT_DIR/incidents_filtered_${TIMESTAMP}.json")
OPEN=$(jq '[.[] | select(.state=="OPEN")] | length' "$OUTPUT_DIR/incidents_filtered_${TIMESTAMP}.json")
CLOSED=$(jq '[.[] | select(.state=="CLOSED")] | length' "$OUTPUT_DIR/incidents_filtered_${TIMESTAMP}.json")

AVG_REMEDIATE_MINUTES=$(jq -r '
  [ .[]
    | select(.title == "🛠️ Branch protection drift remediated on main")
    | select(.closedAt != null)
    | ((.closedAt | fromdateiso8601) - (.createdAt | fromdateiso8601)) / 60
  ]
  | if length == 0 then 0 else (add / length) end
' "$OUTPUT_DIR/incidents_filtered_${TIMESTAMP}.json")

AVG_FAILURE_RESOLUTION_MINUTES=$(jq -r '
  [ .[]
    | select(.title == "🚨 Branch protection drift remediation failed on main")
    | select(.closedAt != null)
    | ((.closedAt | fromdateiso8601) - (.createdAt | fromdateiso8601)) / 60
  ]
  | if length == 0 then 0 else (add / length) end
' "$OUTPUT_DIR/incidents_filtered_${TIMESTAMP}.json")

cat > "$SUMMARY_FILE" <<EOF
{
  "generated_at_utc": "${TIMESTAMP}",
  "repository": "${REPO}",
  "metrics": {
    "incidents_total": ${TOTAL},
    "incidents_open": ${OPEN},
    "incidents_closed": ${CLOSED},
    "avg_remediation_minutes": ${AVG_REMEDIATE_MINUTES},
    "avg_failed_remediation_resolution_minutes": ${AVG_FAILURE_RESOLUTION_MINUTES}
  },
  "sla_targets": {
    "remediation_minutes_target": 60,
    "failed_remediation_resolution_minutes_target": 240
  },
  "files": {
    "incidents": "${INCIDENT_FILE}",
    "summary": "${SUMMARY_FILE}"
  }
}
EOF

echo "✅ SLA KPI summary generated"
echo "   summary: ${SUMMARY_FILE}"
