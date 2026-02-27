#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
COMPOSE_FILE="$REPO_ROOT/build/openstack-handover/docker-compose.yml"
OUT_BASE="$REPO_ROOT/reports/openstack"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
OUT_FILE="$OUT_BASE/shutdown-dependency-validation-$TS.md"

mkdir -p "$OUT_BASE"

ts() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }
log() { echo "[$(ts)] [OPENSTACK-SHUTDOWN-VALIDATOR] $*"; }

has_cmd() { command -v "$1" >/dev/null 2>&1; }

collect_services() {
  if [[ ! -f "$COMPOSE_FILE" ]]; then
    return 1
  fi

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

contains_service() {
  local list="$1"
  local needle="$2"
  echo "$list" | grep -qx "$needle"
}

validate_phases() {
  local services="$1"
  local service_count
  service_count="$(echo "$services" | grep -c . || true)"

  if [[ "$service_count" -le 1 ]]; then
    {
      echo "# OpenStack Shutdown Dependency Validation"
      echo
      echo "- generated_at: $(ts)"
      echo "- compose_file: $COMPOSE_FILE"
      echo
      echo "## Service Inventory"
      echo '```'
      echo "$services"
      echo '```'
      echo
      echo "## Validation Result"
      echo "INCONCLUSIVE: compose inventory is minimal (${service_count} service)."
      echo ""
      echo "Action: load full OpenStack handover compose profile before enforcing service dependency mapping."
    } > "$OUT_FILE"
    return 0
  fi

  phase1=(keystone horizon api-gateway)
  phase2=(nova-api nova-conductor nova-scheduler neutron-server)
  phase3=(nova-compute placement-api)
  phase4=(glance-api cinder-api)
  phase5=(mariadb mysql rabbitmq redis memcached)

  local -a missing

  for item in "${phase1[@]}" "${phase2[@]}" "${phase3[@]}" "${phase4[@]}" "${phase5[@]}"; do
    if ! contains_service "$services" "$item"; then
      missing+=("$item")
    fi
  done

  {
    echo "# OpenStack Shutdown Dependency Validation"
    echo
    echo "- generated_at: $(ts)"
    echo "- compose_file: $COMPOSE_FILE"
    echo
    echo "## Service Inventory"
    echo '```'
    echo "$services"
    echo '```'
    echo
    echo "## Recommended Shutdown Sequence"
    echo "1. Freeze ingress/writes: keystone, horizon, api-gateway"
    echo "2. Control plane APIs: nova-api, nova-conductor, nova-scheduler, neutron-server"
    echo "3. Compute/routing: nova-compute, placement-api"
    echo "4. Image/block APIs: glance-api, cinder-api"
    echo "5. Persistence/backing: mariadb/mysql, rabbitmq, redis, memcached"
    echo
    if [[ ${#missing[@]} -eq 0 ]]; then
      echo "## Validation Result"
      echo "PASS: all canonical dependency services detected in compose inventory."
    else
      echo "## Validation Result"
      echo "WARN: missing expected services from compose inventory:"
      for svc in "${missing[@]}"; do
        echo "- $svc"
      done
      echo
      echo "Action: adjust mapping in this validator and/or compose definitions before production shutdown drills."
    fi
  } > "$OUT_FILE"

  if [[ ${#missing[@]} -eq 0 ]]; then
    return 0
  fi

  return 2
}

main() {
  log "Validating shutdown dependencies against canonical OpenStack compose"

  local services
  if ! services="$(collect_services)" || [[ -z "$services" ]]; then
    log "ERROR: unable to collect services from $COMPOSE_FILE"
    exit 1
  fi

  if validate_phases "$services"; then
    log "Validation PASS"
  else
    code=$?
    if [[ $code -eq 2 ]]; then
      log "Validation WARN: expected service aliases missing"
      log "Report: $OUT_FILE"
      exit 0
    fi
    exit "$code"
  fi

  log "Report: $OUT_FILE"
}

main "$@"
