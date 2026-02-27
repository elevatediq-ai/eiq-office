#!/usr/bin/env bash
# gcp_inventory_cost_report.sh
# Purpose: Inventory running GCP resources for a project and (if available)
#          extract cost summaries from BigQuery billing export.
# Output:  JSON inventory + CSV cost summaries saved under reports/gcp/<project>-<ts>/
# Usage:   ./scripts/pmo/gcp_inventory_cost_report.sh [--project PROJECT] [--days N] [--outdir PATH]
# Example: ./scripts/pmo/gcp_inventory_cost_report.sh --project my-project --days 7

set -uuo pipefail
IFS=$'\n\t'

PROJ=""
DAYS=7
OUTDIR=""
QUIET=false

action_help() {
  cat <<EOF
Usage: $0 [--project PROJECT] [--days N] [--outdir PATH] [--quiet]

Inventories GCP resources for a project and attempts to summarize costs
from a BigQuery billing export table (if present/accessible).

Defaults: --days 7, output -> reports/gcp/<project>-<timestamp>/

Examples:
  $0 --project my-project
  $0 --project my-project --days 30 --outdir /tmp/gcp-report

EOF
}

AUTH_SECRET=""

while [[ ${#} -gt 0 ]]; do
  case "$1" in
    -p|--project) PROJ="$2"; shift 2 ;;
    -d|--days) DAYS="$2"; shift 2 ;;
    -o|--outdir) OUTDIR="$2"; shift 2 ;;
    -s|--auth-secret) AUTH_SECRET="$2"; shift 2 ;;
    -q|--quiet) QUIET=true; shift ;;
    -h|--help) action_help; exit 0 ;;
    *) echo "Unknown arg: $1"; action_help; exit 2 ;;
  esac
done

# If auth secret supplied, try to authenticate via GSM helper (best-effort)
if [ -n "$AUTH_SECRET" ]; then
  if command -v bash >/dev/null 2>&1 && [ -x "$(dirname "$0")/gsm_auth.sh" ]; then
    log "Authenticating using Secret Manager secret: $AUTH_SECRET"
    bash "$(dirname "$0")/gsm_auth.sh" --secret "$AUTH_SECRET" --project "$PROJ" || {
      err "GSM auth failed — continuing but subsequent calls may fail"
    }
  else
    err "GSM auth helper missing or not executable: scripts/pmo/gsm_auth.sh"
  fi
fi

# helpers
log() { if [ "$QUIET" = false ]; then printf "%s\n" "$*"; fi }
err() { printf "ERROR: %s\n" "$*" >&2; }

# prerequisites
for cmd in gcloud gsutil; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    err "'$cmd' CLI not found. Install/enable Google Cloud SDK and try again."; exit 3
  fi
done

# determine project
if [ -z "$PROJ" ]; then
  PROJ=$(gcloud config get-value project 2>/dev/null || true)
fi
if [ -z "$PROJ" ] || [ "$PROJ" = "(unset)" ]; then
  err "No gcloud project configured. Set with 'gcloud config set project <PROJECT>' or pass --project.";
  exit 4
fi

# determine outdir
TS=$(date +%Y%m%dT%H%M%S)
if [ -z "$OUTDIR" ]; then
  OUTDIR="reports/gcp/${PROJ}-${TS}"
fi
mkdir -p "$OUTDIR"

log "Project: $PROJ"
log "Output directory: $OUTDIR"
log "Time window: last $DAYS days"

# collect inventory (best-effort, per-service)
log "Collecting inventory..."
{
  echo "project: $PROJ"
  echo "collected_at: $(date -Iseconds)"
} > "$OUTDIR/summary.txt"

# services
gcloud services list --project="$PROJ" --enabled --format=json > "$OUTDIR/services.json" 2>/dev/null || true

# compute (running instances)
gcloud compute instances list --project="$PROJ" --filter="status=RUNNING" --format=json > "$OUTDIR/compute_instances.json" 2>/dev/null || true

# GKE clusters
gcloud container clusters list --project="$PROJ" --format=json > "$OUTDIR/gke_clusters.json" 2>/dev/null || true

# Cloud Run (managed) - may require region; this lists regional services where possible
gcloud run services list --project="$PROJ" --platform=managed --format=json > "$OUTDIR/cloudrun_services.json" 2>/dev/null || true

# Cloud Functions
gcloud functions list --project="$PROJ" --format=json > "$OUTDIR/functions.json" 2>/dev/null || true

# App Engine
gcloud app describe --project="$PROJ" --format=json > "$OUTDIR/app_engine.json" 2>/dev/null || true

# Cloud SQL
gcloud sql instances list --project="$PROJ" --format=json > "$OUTDIR/cloudsql.json" 2>/dev/null || true

# Memorystore (Redis)
gcloud redis instances list --project="$PROJ" --format=json > "$OUTDIR/redis.json" 2>/dev/null || true

# Buckets (names only)
if gsutil ls -p "$PROJ" > "$OUTDIR/buckets_list.txt" 2>/dev/null; then
  :
else
  > "$OUTDIR/buckets_list.txt"
fi

# BigQuery datasets (in project)
if command -v bq >/dev/null 2>&1; then
  bq --project_id="$PROJ" ls --format=json > "$OUTDIR/bigquery_datasets.json" 2>/dev/null || true
fi

# Dataflow jobs
gcloud dataflow jobs list --project="$PROJ" --format=json > "$OUTDIR/dataflow_jobs.json" 2>/dev/null || true

# Logging sinks
gcloud logging sinks list --project="$PROJ" --format=json > "$OUTDIR/logging_sinks.json" 2>/dev/null || true

# Billing accounts visible to caller
gcloud beta billing accounts list --format=json > "$OUTDIR/billing_accounts.json" 2>/dev/null || true

# Attempt to detect a BigQuery billing export table in THIS project (best-effort)
BILLING_TABLE=""
if command -v bq >/dev/null 2>&1; then
  for ds in $(bq --project_id="$PROJ" ls --format=json 2>/dev/null | jq -r '.[].datasetReference.datasetId' 2>/dev/null || true); do
    for tbl in $(bq --project_id="$PROJ" ls --dataset_id="$ds" --format=json 2>/dev/null | jq -r '.[].tableReference.tableId' 2>/dev/null || true); do
      if echo "$tbl" | grep -Ei 'billing|gcp_billing_export' >/dev/null 2>&1; then
        BILLING_TABLE="${PROJ}.${ds}.${tbl}"
        break 2
      fi
    done
  done
fi

echo "billing_table=$BILLING_TABLE" >> "$OUTDIR/summary.txt"

if [ -n "$BILLING_TABLE" ] && command -v bq >/dev/null 2>&1; then
  log "Found billing export table: $BILLING_TABLE — querying costs (last $DAYS days)"
  # costs by GCP service
  bq query --nouse_legacy_sql --format=csv "SELECT service.description AS service, SUM(CAST(cost AS NUMERIC)) AS cost FROM \`${BILLING_TABLE}\` WHERE usage_start_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL ${DAYS} DAY) GROUP BY service.description ORDER BY cost DESC" > "$OUTDIR/costs_${DAYS}d_by_service.csv" 2>/dev/null || true
  # costs by project/resource
  bq query --nouse_legacy_sql --format=csv "SELECT project.id AS project_id, SUM(CAST(cost AS NUMERIC)) AS cost FROM \`${BILLING_TABLE}\` WHERE usage_start_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL ${DAYS} DAY) GROUP BY project.id ORDER BY cost DESC" > "$OUTDIR/costs_${DAYS}d_by_project.csv" 2>/dev/null || true
else
  log "No accessible BigQuery billing export table found in project '$PROJ'."
  log "If you want live cost numbers, enable Billing export to BigQuery and re-run this script: https://cloud.google.com/billing/docs/how-to/export-data-bigquery"
fi

# top-level summary (counts)
jq -n \
  --arg project "$PROJ" \
  --arg collected_at "$(date -Iseconds)" \
  '{project: $project, collected_at: $collected_at, sample_files: ["services.json","compute_instances.json","gke_clusters.json","cloudrun_services.json","functions.json","cloudsql.json","buckets_list.txt"]}' > "$OUTDIR/resources_summary.json"

log "Report generated — files saved to: $OUTDIR"
ls -lah "$OUTDIR" | sed -n '1,200p'

exit 0
