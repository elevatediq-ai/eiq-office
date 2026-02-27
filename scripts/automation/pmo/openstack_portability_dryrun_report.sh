#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TF_ROOT="$REPO_ROOT/infrastructure/terraform"
CHECKLIST="$REPO_ROOT/docs/runbooks/openstack-multicloud-portability-checklist.md"
OUT_BASE="$REPO_ROOT/reports/openstack"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
OUT_FILE="$OUT_BASE/portability-dryrun-$TS.md"

mkdir -p "$OUT_BASE"

ts() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }
log() { echo "[$(ts)] [OPENSTACK-PORTABILITY] $*"; }

has_cmd() { command -v "$1" >/dev/null 2>&1; }

check_provider_pin() {
  local provider="$1"
  local referenced_files
  referenced_files="$(grep -R -l --include='*.tf' --exclude-dir='.terraform' "source[[:space:]]*=[[:space:]]*\"hashicorp/${provider}\"" "$TF_ROOT" 2>/dev/null || true)"

  if [[ -z "$referenced_files" ]]; then
    echo "NOT_REFERENCED"
    return 0
  fi

  local file
  while read -r file; do
    [[ -n "$file" ]] || continue
    if awk -v provider="$provider" '
      BEGIN { in_block=0; saw_source=0; saw_version=0; pinned=0 }
      $0 ~ "^[[:space:]]*" provider "[[:space:]]*=[[:space:]]*\\{" {
        in_block=1; saw_source=0; saw_version=0; next
      }
      in_block {
        if ($0 ~ "source[[:space:]]*=[[:space:]]*\"hashicorp/" provider "\"") saw_source=1
        if ($0 ~ "version[[:space:]]*=") saw_version=1
        if ($0 ~ /^[[:space:]]*}/) {
          if (saw_source && saw_version) { pinned=1; exit }
          in_block=0
        }
      }
      END { exit pinned ? 0 : 1 }
    ' "$file"; then
      echo "PINNED"
      return 0
    fi
  done <<< "$referenced_files"

  echo "REFERENCED_NO_PIN"
}

main() {
  log "Generating OpenStack portability dry-run report"

  local aws_state gcp_state azure_state
  aws_state="$(check_provider_pin aws)"
  gcp_state="$(check_provider_pin google)"
  azure_state="$(check_provider_pin azurerm)"

  local checklist_state="MISSING"
  [[ -f "$CHECKLIST" ]] && checklist_state="PRESENT"

  local terraform_state="NOT_INSTALLED"
  local tf_version="unknown"
  if has_cmd terraform; then
    terraform_state="INSTALLED"
    tf_version="$(terraform version | head -1 | sed 's/\r//g')"
  fi

  local risk_score=0
  for state in "$aws_state" "$gcp_state" "$azure_state"; do
    case "$state" in
      PINNED) risk_score=$((risk_score + 0));;
      REFERENCED_NO_PIN) risk_score=$((risk_score + 20));;
      NOT_REFERENCED) risk_score=$((risk_score + 0));;
    esac
  done

  if [[ "$checklist_state" == "MISSING" ]]; then
    risk_score=$((risk_score + 10))
  fi

  local risk_band="LOW"
  if [[ "$risk_score" -ge 70 ]]; then
    risk_band="HIGH"
  elif [[ "$risk_score" -ge 35 ]]; then
    risk_band="MEDIUM"
  fi

  {
    echo "# OpenStack to AWS/GCP/Azure Portability Dry-Run Report"
    echo
    echo "- generated_at: $(ts)"
    echo "- terraform_state: $terraform_state"
    echo "- terraform_version: $tf_version"
    echo "- checklist: $checklist_state"
    echo
    echo "## Provider Readiness"
    echo "- aws: $aws_state"
    echo "- google: $gcp_state"
    echo "- azurerm: $azure_state"
    echo
    echo "## Capability Mapping Snapshot"
    echo "- Keystone -> IAM/STS | IAM | Entra ID/Managed Identity"
    echo "- Nova -> EC2 | Compute Engine | Virtual Machines"
    echo "- Neutron -> VPC/TGW | VPC | VNet"
    echo "- Glance -> AMI/ECR | Images/Artifact Registry | SIG/ACR"
    echo "- Cinder -> EBS | Persistent Disk | Managed Disks"
    echo "- Swift -> S3 | Cloud Storage | Blob Storage"
    echo "- Barbican -> KMS+Secrets Manager | Cloud KMS+Secret Manager | Key Vault"
    echo
    echo "## Dry-Run Risk Assessment"
    echo "- risk_score: $risk_score"
    echo "- risk_band: $risk_band"
    echo
    echo "## Recommended Next Actions"
    echo "1. Ensure required_providers version pinning for aws/google/azurerm"
    echo "2. Add per-provider backend encryption + lock strategy"
    echo "3. Validate AU-2/AU-12 event parity across clouds"
    echo "4. Validate SC-8 transport controls for each provider edge path"
    echo "5. Open implementation tasks for unresolved mapping gaps"
  } > "$OUT_FILE"

  log "Report: $OUT_FILE"
}

main "$@"
