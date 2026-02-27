#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
COMPOSE_FILE="$REPO_ROOT/build/openstack-handover/docker-compose.yml"
CONFIG_DIR="$REPO_ROOT/build/openstack-handover/config"
OUT_BASE="$REPO_ROOT/reports/openstack"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
OUT_DIR="$OUT_BASE/immutable-manifest-$TS"
MANIFEST_MD="$OUT_DIR/manifest.md"
CHECKSUM_FILE="$OUT_DIR/config_checksums.sha256"
FILE_INVENTORY="$OUT_DIR/file_inventory.txt"
IMAGE_MANIFEST="$OUT_DIR/image_manifest.txt"
HEALTH_REPORT="$OUT_DIR/health_report.txt"

mkdir -p "$OUT_DIR"

ts() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }
log() { echo "[$(ts)] [OPENSTACK-IMMUTABLE] $*"; }

has_cmd() { command -v "$1" >/dev/null 2>&1; }

record_inventory() {
  {
    echo "# Immutable Baseline File Inventory"
    echo "generated_at=$(ts)"
    echo "repo_root=$REPO_ROOT"
    echo
    for required in \
      "$REPO_ROOT/.env" \
      "$REPO_ROOT/infrastructure/hosts.env" \
      "$REPO_ROOT/config/network/trusted-devices.yaml" \
      "$COMPOSE_FILE"; do
      if [[ -f "$required" ]]; then
        echo "FOUND $required"
      else
        echo "MISSING $required"
      fi
    done
  } > "$FILE_INVENTORY"
}

record_checksums() {
  : > "$CHECKSUM_FILE"

  if [[ -f "$COMPOSE_FILE" ]]; then
    sha256sum "$COMPOSE_FILE" >> "$CHECKSUM_FILE"
  fi

  for path in \
    "$REPO_ROOT/.env" \
    "$REPO_ROOT/infrastructure/hosts.env" \
    "$REPO_ROOT/config/network/trusted-devices.yaml"; do
    if [[ -f "$path" ]]; then
      sha256sum "$path" >> "$CHECKSUM_FILE"
    fi
  done

  if [[ -d "$CONFIG_DIR" ]]; then
    find "$CONFIG_DIR" -type f -print0 | sort -z | xargs -0 sha256sum >> "$CHECKSUM_FILE"
  fi
}

record_image_manifest() {
  : > "$IMAGE_MANIFEST"

  if [[ ! -f "$COMPOSE_FILE" ]]; then
    echo "compose_file_missing=$COMPOSE_FILE" > "$IMAGE_MANIFEST"
    return
  fi

  if has_cmd docker; then
    local host_ips
    host_ips="$(hostname -I 2>/dev/null || true)"
    if [[ "$host_ips" != *"192.168.168.42"* ]]; then
      {
        echo "skipped=true"
        echo "reason=not_on_192.168.168.42"
        echo "detected_host_ips=$host_ips"
      } > "$IMAGE_MANIFEST"
      return
    fi

    if docker compose -f "$COMPOSE_FILE" config --images > "$IMAGE_MANIFEST" 2>/dev/null; then
      :
    else
      {
        echo "skipped=true"
        echo "reason=docker_compose_config_images_failed"
      } > "$IMAGE_MANIFEST"
    fi
  else
    {
      echo "skipped=true"
      echo "reason=docker_not_available"
    } > "$IMAGE_MANIFEST"
  fi
}

record_health_report() {
  {
    echo "# OpenStack Health Report"
    echo "generated_at=$(ts)"
    for endpoint in \
      "http://192.168.168.42:5000" \
      "http://192.168.168.42:8774" \
      "http://192.168.168.42:9696" \
      "http://192.168.168.42:9292" \
      "http://192.168.168.42:8776" \
      "http://192.168.168.42:8778"; do
      if has_cmd curl; then
        code="$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 3 "$endpoint" || true)"
        echo "$endpoint status_code=$code"
      else
        echo "$endpoint status_code=SKIPPED_NO_CURL"
      fi
    done
  } > "$HEALTH_REPORT"
}

write_manifest_md() {
  local checksum_count
  checksum_count="$(wc -l < "$CHECKSUM_FILE" | tr -d ' ')"

  {
    echo "# OpenStack Immutable Baseline Manifest"
    echo
    echo "- generated_at: $(ts)"
    echo "- output_dir: $OUT_DIR"
    echo "- compose_file: $COMPOSE_FILE"
    echo "- checksum_entries: $checksum_count"
    echo
    echo "## Artifacts"
    echo "- file inventory: $FILE_INVENTORY"
    echo "- checksums: $CHECKSUM_FILE"
    echo "- image manifest: $IMAGE_MANIFEST"
    echo "- health report: $HEALTH_REPORT"
  } > "$MANIFEST_MD"
}

main() {
  log "Generating immutable baseline manifest"
  record_inventory
  record_checksums
  record_image_manifest
  record_health_report
  write_manifest_md

  log "Complete"
  log "Manifest: $MANIFEST_MD"
}

main "$@"
