#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
COMPOSE_FILE="$REPO_ROOT/build/openstack-handover/docker-compose.yml"
OUT_BASE="$REPO_ROOT/reports/openstack"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
SUMMARY_FILE="$OUT_BASE/lifecycle-orchestrator-$TS.md"

IMMUTABLE_SCRIPT="$SCRIPT_DIR/openstack_immutable_manifest.sh"
SHUTDOWN_VALIDATOR="$SCRIPT_DIR/openstack_shutdown_dependency_validator.sh"
PARITY_VALIDATOR="$SCRIPT_DIR/openstack_post_restore_parity_validator.sh"
PORTABILITY_REPORTER="$SCRIPT_DIR/openstack_portability_dryrun_report.sh"

MODE="full-dryrun"
RUN_TERRAFORM_VALIDATE="false"

mkdir -p "$OUT_BASE"

ts() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }
log() { echo "[$(ts)] [OPENSTACK-LIFECYCLE] $*"; }

usage() {
  cat <<EOF
Usage: $0 [--mode MODE] [--terraform-validate]

Modes:
  preflight-only       Run preflight + baseline evidence only
  restore-validate     Run parity validation + portability report
  full-dryrun          Run full non-destructive pipeline (default)

Options:
  --terraform-validate Attempt terraform init -backend=false + validate for env dirs
EOF
}

has_cmd() { command -v "$1" >/dev/null 2>&1; }

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --mode)
        MODE="$2"; shift 2;;
      --terraform-validate)
        RUN_TERRAFORM_VALIDATE="true"; shift;;
      -h|--help)
        usage; exit 0;;
      *)
        echo "Unknown arg: $1" >&2
        usage
        exit 2;;
    esac
  done
}

run_step() {
  local name="$1"
  local cmd="$2"
  log "STEP: $name"
  if eval "$cmd"; then
    echo "- $name: PASS" >> "$SUMMARY_FILE"
  else
    echo "- $name: FAIL" >> "$SUMMARY_FILE"
    return 1
  fi
}

terraform_validate_envs() {
  local env_root="$REPO_ROOT/infrastructure/terraform/environments"
  [[ -d "$env_root" ]] || return 0

  if ! has_cmd terraform; then
    log "Terraform not installed; skipping terraform validation"
    echo "- terraform_validate: SKIPPED(terraform not installed)" >> "$SUMMARY_FILE"
    return 0
  fi

  while IFS= read -r -d '' env_dir; do
    [[ -f "$env_dir/main.tf" ]] || continue
    log "terraform validate dry-run: $env_dir"
    if terraform -chdir="$env_dir" init -backend=false -input=false -no-color >/dev/null 2>&1 \
      && terraform -chdir="$env_dir" validate -no-color >/dev/null 2>&1; then
      echo "- terraform_env $(basename "$env_dir"): PASS" >> "$SUMMARY_FILE"
    else
      echo "- terraform_env $(basename "$env_dir"): WARN" >> "$SUMMARY_FILE"
    fi
  done < <(find "$env_root" -mindepth 1 -maxdepth 1 -type d -print0)
}

preflight() {
  {
    echo "# OpenStack Terraform Lifecycle Orchestrator"
    echo
    echo "- generated_at: $(ts)"
    echo "- mode: $MODE"
    echo "- compose_file: $COMPOSE_FILE"
    echo "- host_ips: $(hostname -I 2>/dev/null || echo unknown)"
    echo
    echo "## Step Results"
  } > "$SUMMARY_FILE"

  [[ -f "$COMPOSE_FILE" ]] || { log "Missing compose file: $COMPOSE_FILE"; return 1; }
  [[ -x "$IMMUTABLE_SCRIPT" ]] || { log "Missing executable: $IMMUTABLE_SCRIPT"; return 1; }
  [[ -x "$SHUTDOWN_VALIDATOR" ]] || { log "Missing executable: $SHUTDOWN_VALIDATOR"; return 1; }
  [[ -x "$PARITY_VALIDATOR" ]] || { log "Missing executable: $PARITY_VALIDATOR"; return 1; }
  [[ -x "$PORTABILITY_REPORTER" ]] || { log "Missing executable: $PORTABILITY_REPORTER"; return 1; }

  echo "- preflight: PASS" >> "$SUMMARY_FILE"
}

main() {
  parse_args "$@"
  log "Running lifecycle orchestrator (mode=$MODE)"

  preflight

  if [[ "$MODE" == "preflight-only" || "$MODE" == "full-dryrun" ]]; then
    run_step "immutable_baseline_capture" "\"$IMMUTABLE_SCRIPT\""
    run_step "shutdown_dependency_validation" "\"$SHUTDOWN_VALIDATOR\""
  fi

  if [[ "$MODE" == "restore-validate" || "$MODE" == "full-dryrun" ]]; then
    run_step "post_restore_parity_validation" "\"$PARITY_VALIDATOR\""
    run_step "multicloud_portability_dryrun" "\"$PORTABILITY_REPORTER\""
  fi

  if [[ "$RUN_TERRAFORM_VALIDATE" == "true" ]]; then
    terraform_validate_envs
  else
    echo "- terraform_validate: SKIPPED(not requested)" >> "$SUMMARY_FILE"
  fi

  log "Summary: $SUMMARY_FILE"
}

main "$@"
