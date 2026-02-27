#!/usr/bin/env bash
# gsm_auth.sh
# Helper: authenticate gcloud using a service-account JSON stored in
# Google Secret Manager (GSM / Secret Manager).
# Usage: ./scripts/pmo/gsm_auth.sh --secret SECRET_NAME --project PROJECT
# Notes:
# - Caller must already have permission to access the secret (or run locally as a user with access).
# - The script writes a temporary keyfile and runs `gcloud auth activate-service-account`.
# - The keyfile is removed on exit. For long-lived auth, set GOOGLE_APPLICATION_CREDENTIALS to the keyfile.

set -euo pipefail
IFS=$'\n\t'

SECRET_NAME=""
PROJECT=""
KEYFILE=""

usage() {
  cat <<EOF
Usage: $0 --secret SECRET_NAME --project PROJECT [--keyfile /path/to/key.json]

Fetches a service-account JSON from Secret Manager and activates it for gcloud.

Examples:
  $0 --secret my-sa-key --project my-project
  $0 --secret my-sa-key --project my-project --keyfile /tmp/sa.json

EOF
}

while [[ ${#} -gt 0 ]]; do
  case "$1" in
    -s|--secret) SECRET_NAME="$2"; shift 2 ;;
    -p|--project) PROJECT="$2"; shift 2 ;;
    -k|--keyfile) KEYFILE="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1"; usage; exit 2 ;;
  esac
done

if [ -z "$SECRET_NAME" ] || [ -z "$PROJECT" ]; then
  usage
  exit 2
fi

# ensure gcloud exists
if ! command -v gcloud >/dev/null 2>&1; then
  echo "gcloud CLI not found" >&2
  exit 3
fi

# default tmp keyfile
if [ -z "$KEYFILE" ]; then
  KEYFILE="/tmp/gsm-sa-${PROJECT}-${SECRET_NAME}-$$.json"
fi

cleanup() {
  if [ -f "$KEYFILE" ]; then
    shred -u "$KEYFILE" 2>/dev/null || rm -f "$KEYFILE" 2>/dev/null || true
  fi
}
trap cleanup EXIT

# Fetch secret value (best-effort). This requires the caller to already have Secret Manager access.
if ! gcloud secrets versions access latest --secret="$SECRET_NAME" --project="$PROJECT" > "$KEYFILE" 2>/dev/null; then
  echo "Failed to access secret '$SECRET_NAME' in project '$PROJECT'. Ensure caller has 'secretmanager.versions.access' permission." >&2
  exit 4
fi

# activate service account
if gcloud auth activate-service-account --key-file="$KEYFILE" >/dev/null 2>&1; then
  echo "Activated service-account from secret '$SECRET_NAME'"
  # export for subprocesses in this shell only
  export GOOGLE_APPLICATION_CREDENTIALS="$KEYFILE"
  # leave KEYFILE in place for the life of this process; cleanup will remove it on exit
  # print path for callers
  echo "GOOGLE_APPLICATION_CREDENTIALS=$KEYFILE"
  exit 0
else
  echo "Failed to activate service-account from keyfile" >&2
  exit 5
fi
