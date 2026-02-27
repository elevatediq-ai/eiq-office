#!/usr/bin/env bash
# run_gcp_inventory_smoke.sh
# CI-friendly smoke test for PMO GCP inventory + cost report script.

set -euo pipefail

PROJECT=${1:-$(gcloud config get-value project 2>/dev/null || echo "")}
SECRET=${2:-"pm-automation-sa-gcp-pmo"}
OUTDIR="/tmp/gcp-inventory-smoke-$(date +%s)"

if [ -z "$PROJECT" ]; then
  echo "Usage: $0 <GCP_PROJECT> [SECRET_NAME]" >&2
  exit 2
fi

if ! command -v gcloud >/dev/null 2>&1; then
  echo "gcloud CLI not available; skipping smoke test" >&2
  exit 3
fi

mkdir -p "$OUTDIR"

# Try GSM auth (best-effort)
if gcloud secrets versions access latest --secret="$SECRET" --project="$PROJECT" >/dev/null 2>&1; then
  echo "Found secret $SECRET — attempting GSM auth"
  ./scripts/pmo/gsm_auth.sh --secret "$SECRET" --project "$PROJECT"
else
  echo "Secret $SECRET not available in project $PROJECT; skipping GSM auth (will use local gcloud user)"
fi

# Run inventory (quiet)
./scripts/pmo/gcp_inventory_cost_report.sh --project "$PROJECT" --days 1 --outdir "$OUTDIR" --quiet

# Basic validation
if [ -f "$OUTDIR/services.json" ]; then
  echo "Smoke: services.json present"
else
  echo "Smoke FAIL: services.json missing" >&2; exit 4
fi

echo "Smoke test completed — report saved to: $OUTDIR"
exit 0
