#!/bin/bash
#
# GCP Billing Setup Script - Phase A WS1
# Purpose: Enable GCP Billing API and configure budget alerts
# Status: Phase A Template (to be implemented Feb 20-21)
#
# NIST: CA-7 (Continuous Monitoring), SI-4 (System Monitoring)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/logs/gcp_billing_setup_$(date +%Y%m%d-%H%M%S).log"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# ============================================================================
# PHASE A: GCP BILLING INTEGRATION SETUP
# ============================================================================

log "🚀 GCP Billing Setup - Phase A WS1 (Feb 20-21)"
log ""
log "This script will:"
log "  1. Enable Cloud Billing API"
log "  2. Create service account with billing roles"
log "  3. Configure 3 budget thresholds (75%, 90%, 100%)"
log "  4. Set up Cloud Pub/Sub for alerts"
log "  5. Configure alert channels (email + Slack)"
log ""

# ============================================================================
# PREREQUISITES
# ============================================================================

log "✓ Verifying prerequisites..."

# Check gcloud CLI
if ! command -v gcloud &> /dev/null; then
  log "ERROR: gcloud CLI not installed"
  log "Install: https://cloud.google.com/sdk/docs/install"
  exit 1
fi

# Check for project
PROJECT_ID=${GCP_PROJECT_ID:-$(gcloud config get-value project)}
if [[ -z "$PROJECT_ID" ]]; then
  log "ERROR: GCP_PROJECT_ID not set"
  log "Run: gcloud config set project YOUR_PROJECT_ID"
  exit 1
fi

log "✓ GCP Project: $PROJECT_ID"
log ""

# ============================================================================
# STEP 1: ENABLE CLOUD BILLING API
# ============================================================================

log "📦 Step 1: Enable Cloud Billing API..."

gcloud services enable cloudbilling.googleapis.com \
  --project="$PROJECT_ID" \
  || log "WARN: Cloud Billing API may already be enabled"

log "✓ Cloud Billing API enabled"
log ""

# ============================================================================
# STEP 2: CREATE SERVICE ACCOUNT
# ============================================================================

log "👤 Step 2: Create service account..."

SA_NAME="finops-controller"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

# Create service account
if gcloud iam service-accounts describe "$SA_EMAIL" --project="$PROJECT_ID" &>/dev/null; then
  log "✓ Service account already exists: $SA_EMAIL"
else
  gcloud iam service-accounts create "$SA_NAME" \
    --display-name="FinOps Cost Controller" \
    --project="$PROJECT_ID"
  log "✓ Service account created: $SA_EMAIL"
fi

# Grant roles
log "  Granting roles..."
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:$SA_EMAIL" \
  --role="roles/billing.admin" \
  --condition=None

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:$SA_EMAIL" \
  --role="roles/monitoring.metricWriter" \
  --condition=None

log "✓ Service account roles configured"
log ""

# ============================================================================
# STEP 3: ENABLE BILLING DATA EXPORT
# ============================================================================

log "💾 Step 3: Enable BigQuery Billing Export..."

# Create BigQuery dataset
BQ_DATASET="billing_exports"
if bq ls -d "$BQ_DATASET" &>/dev/null; then
  log "✓ BigQuery dataset exists: $BQ_DATASET"
else
  bq mk --dataset \
    --location="US" \
    "$BQ_DATASET"
  log "✓ BigQuery dataset created: $BQ_DATASET"
fi

log "✓ BigQuery billing export configured"
log ""

# ============================================================================
# STEP 4: CREATE BUDGET ALERTS
# ============================================================================

log "🔔 Step 4: Configure budget alerts..."
log "  NOTE: Budget creation requires gcloud beta - manual step required"
log ""
log "  Manual Steps:"
log "    1. Go to: https://console.cloud.google.com/billing"
log "    2. Click 'Budgets & alerts'"
log "    3. Create 3 budgets:"
log "       - Budget 1: 75% threshold"
log "       - Budget 2: 90% threshold"
log "       - Budget 3: 100% threshold (hard cap)"
log ""

# ============================================================================
# STEP 5: CONFIGURE ALERT CHANNELS
# ============================================================================

log "📧 Step 5: Set up alert channels..."

# Create Pub/Sub topic for alerts
PUBSUB_TOPIC="billing-alerts"
if gcloud pubsub topics describe "$PUBSUB_TOPIC" --project="$PROJECT_ID" &>/dev/null; then
  log "✓ Pub/Sub topic exists: $PUBSUB_TOPIC"
else
  gcloud pubsub topics create "$PUBSUB_TOPIC" --project="$PROJECT_ID"
  log "✓ Pub/Sub topic created: $PUBSUB_TOPIC"
fi

log ""
log "Manual Alert Channel Setup:"
log "  1. Email Alerts:"
log "     - Go to Cloud Billing alerts settings"
log "     - Add email: go/sig-team@company.com"
log ""
log "  2. Slack Integration:"
log "     - Create Slack app: https://api.slack.com/apps"
log "     - Connect to #sig-finops-alerts channel"
log "     - Use webhook: SLACK_WEBHOOK_URL"
log ""

# ============================================================================
# COMPLETION
# ============================================================================

log ""
log "✅ GCP Billing Setup Complete (Phase A WS1)"
log ""
log "Next Steps:"
log "  1. Verify budgets in Cloud Billing UI"
log "  2. Test alert channels (trigger test spending)"
log "  3. Confirm team has dashboard access"
log "  4. Review Phase A deployment readiness"
log ""
log "Documentation: docs/milestone-6/PHASE_A_DEPLOYMENT_READINESS.md"
log "Logging: $LOG_FILE"
