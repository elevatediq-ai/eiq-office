#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
COMPOSE_FILE="$REPO_ROOT/build/openstack-handover/docker-compose.yml"
OUT_BASE="$REPO_ROOT/reports/openstack"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
OUT_FILE="$OUT_BASE/post-restore-parity-$TS.md"

mkdir -p "$OUT_BASE"

ts() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }
log() { echo "[$(ts)] [OPENSTACK-PARITY] $*"; }

has_cmd() { command -v "$1" >/dev/null 2>&1; }

expected_services_from_compose() {
  if has_cmd docker && docker compose -f "$COMPOSE_FILE" config --services >/dev/null 2>&1; then
    docker compose -f "$COMPOSE_FILE" config --services
  else
    awk '
      $1 == "services:" {in_services=1; next}
      in_services && /^[^[:space:]]/ {in_services=0}
      in_services && /^[[:space:]]{2}[a-zA-Z0-9._-]+:/ {
        name=$1
        gsub(":","",name)
        gsub(/^[[:space:]]+/,"",name)
        print name
      }
    ' "$COMPOSE_FILE"
  fi
}

running_services() {
  if ! has_cmd docker; then
    return 0
  fi

  if docker compose -f "$COMPOSE_FILE" ps --services --status running >/dev/null 2>&1; then
    docker compose -f "$COMPOSE_FILE" ps --services --status running
    return 0
  fi

  return 0
}

endpoint_health() {
  local endpoint="$1"
  if has_cmd curl; then
    curl -s -o /dev/null -w '%{http_code}' --connect-timeout 3 "$endpoint" || true
  else
    echo "SKIP"
  fi
}

main() {
  log "Running post-restore parity validation"

  if [[ ! -f "$COMPOSE_FILE" ]]; then
    log "ERROR: missing compose file: $COMPOSE_FILE"
    exit 1
  fi

  local expected running
  expected="$(expected_services_from_compose | sed '/^$/d' || true)"
  running="$(running_services | sed '/^$/d' || true)"

  local expected_count running_count
  expected_count="$(echo "$expected" | grep -c . || true)"
  running_count="$(echo "$running" | grep -c . || true)"

  local host_ips
  host_ips="$(hostname -I 2>/dev/null || true)"

  local endpoints
  endpoints=$(cat <<'EOF'
http://192.168.168.42:5000
http://192.168.168.42:8774
http://192.168.168.42:9696
http://192.168.168.42:9292
http://192.168.168.42:8776
http://192.168.168.42:8778
EOF
)

  local missing_services=""
  if [[ "$running_count" -gt 0 ]]; then
    while read -r service; do
      [[ -n "$service" ]] || continue
      if ! echo "$running" | grep -qx "$service"; then
        missing_services+="- $service\n"
      fi
    done <<< "$expected"
  fi

  {
    echo "# OpenStack Post-Restore Parity Validation"
    echo
    echo "- generated_at: $(ts)"
    echo "- compose_file: $COMPOSE_FILE"
    echo "- detected_host_ips: ${host_ips:-unknown}"
    echo "- expected_services: $expected_count"
    echo "- running_services: $running_count"
    echo
    echo "## Expected Services"
    echo '```'
    echo "$expected"
    echo '```'
    echo
    echo "## Running Services"
    echo '```'
    if [[ -n "$running" ]]; then
      echo "$running"
    else
      echo "(none detected or docker unavailable)"
    fi
    echo '```'
    echo
    echo "## Endpoint Health Checks"
    while read -r endpoint; do
      [[ -n "$endpoint" ]] || continue
      code="$(endpoint_health "$endpoint")"
      echo "- $endpoint => $code"
    done <<< "$endpoints"
    echo
    if [[ "$expected_count" -le 1 ]]; then
      echo "## Result"
      echo "INCONCLUSIVE: compose inventory is minimal; parity baseline cannot be fully asserted yet."
    elif [[ "$running_count" -eq 0 ]]; then
      echo "## Result"
      echo "WARN: no running compose services detected from canonical file."
    elif [[ -n "$missing_services" ]]; then
      echo "## Result"
      echo "WARN: parity drift detected. Missing running services:"
      printf "%b" "$missing_services"
    else
      echo "## Result"
      echo "PASS: running services match expected compose service inventory."
    fi
  } > "$OUT_FILE"

  log "Report: $OUT_FILE"
}

main "$@"
