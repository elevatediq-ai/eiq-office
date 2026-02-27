#!/usr/bin/env bash
# =============================================================================
# ElevatedIQ Milestone Health Check
# NIST Controls: PM-5 (Inventory), PM-6 (Measures of Performance), AU-2
# Run: monthly via cron, or manually: ./scripts/pmo/milestone_health_check.sh
# =============================================================================

set -euo pipefail

REPO="${REPO:-kushin77/ElevatedIQ-Mono-Repo}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/logs"
LOG_FILE="${LOG_DIR}/milestone_health_check.log"
FAIL=0

mkdir -p "$LOG_DIR"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

log() { echo "[$TIMESTAMP] $*" | tee -a "$LOG_FILE"; }

log "================================================================"
log " ElevatedIQ Milestone Health Check | Repo: $REPO"
log "================================================================"



# ── 1. GHOST MILESTONES (CLOSED with 0 issues — truly unused) ─────────────────
log ""
log "── CHECK 1: Ghost Milestones (CLOSED, 0 issues) ────────────────"

GHOSTS=$(gh api "repos/${REPO}/milestones?state=closed&per_page=100" \
  --jq '[.[] | select(.open_issues == 0 and .closed_issues == 0) | {n:.number, title:.title}]')
GHOST_COUNT=$(echo "$GHOSTS" | jq 'length')

if [[ "$GHOST_COUNT" -gt 0 ]]; then
  log "  🔴 FAIL: Found $GHOST_COUNT closed ghost milestone(s)"
  while IFS= read -r line; do log "    $line"; done < <(echo "$GHOSTS" | jq -r '.[] | "- #\(.n): \(.title)"')
  FAIL=1
  if [[ "${AUTO_FIX:-false}" == "true" ]]; then
    log "  🔧 AUTO_FIX: Deleting closed ghost milestones..."
    while IFS= read -r n; do
      gh api -X DELETE "repos/${REPO}/milestones/${n}" && log "    ✅ Deleted #${n}" || log "    ⚠️ Failed #${n}"
    done < <(echo "$GHOSTS" | jq '.[].n')
    FAIL=0
  fi
else
  log "  ✅ PASS: No closed ghost milestones"
fi

# ── 2. OPEN MILESTONES WITH 0 OPEN ISSUES (done-but-unclosed, skip canonical) ─
log ""
log "── CHECK 2: Done-but-Open Milestones (excl. canonical [*] buckets) ──"

DONE_OPEN=$(gh api "repos/${REPO}/milestones?state=open&per_page=100" \
  --jq '[.[] | select(
    .open_issues == 0 and
    .closed_issues > 0 and
    (.title | startswith("[INFRA]") | not) and
    (.title | startswith("[SEC]") | not) and
    (.title | startswith("[AI]") | not) and
    (.title | startswith("[FINOPS]") | not) and
    (.title | startswith("[PMO]") | not)
  ) | {n:.number, title:.title, closed:.closed_issues}]')
DONE_COUNT=$(echo "$DONE_OPEN" | jq 'length')

if [[ "$DONE_COUNT" -gt 0 ]]; then
  log "  🟡 WARN: $DONE_COUNT open milestone(s) have 0 open issues but have closed work — should be closed"
  while IFS= read -r line; do log "    $line"; done < <(echo "$DONE_OPEN" | jq -r '.[] | "- #\(.n): \(.title) [\(.closed) closed issues]"')
  if [[ "${AUTO_FIX:-false}" == "true" ]]; then
    log "  🔧 AUTO_FIX: Closing done milestones..."
    while IFS= read -r n; do
      result=$(gh api -X PATCH "repos/${REPO}/milestones/${n}" -f state=closed --jq '"#\(.number): \(.title)"')
      log "    ✅ Closed $result"
    done < <(echo "$DONE_OPEN" | jq '.[].n')
  fi
  FAIL=1
else
  log "  ✅ PASS: No done-but-open milestones"
fi

# ── 3. NAMING SCHEMA VIOLATIONS (Ad-hoc: prefix) ──────────────────────────────
log ""
log "── CHECK 3: Naming Schema Violations ───────────────────────────"

ADHOC=$(gh api "repos/${REPO}/milestones?state=open&per_page=100" \
  --jq '[.[] | select(.title | startswith("Ad-hoc:")) | {n:.number, title:.title}]')
ADHOC_COUNT=$(echo "$ADHOC" | jq 'length')

if [[ "$ADHOC_COUNT" -gt 0 ]]; then
  log "  🔴 FAIL: $ADHOC_COUNT open milestones use forbidden 'Ad-hoc:' prefix"
  echo "$ADHOC" | jq -r '.[] | "    - #\(.n): \(.title)"' | while read -r line; do log "$line"; done
  FAIL=1
else
  log "  ✅ PASS: No Ad-hoc: naming violations in open milestones"
fi

# ── 4. CANONICAL DOMAIN MILESTONES EXIST ──────────────────────────────────────
log ""
log "── CHECK 4: Canonical Domain Milestones Exist ──────────────────"

REQUIRED=("[INFRA] Infrastructure & IaC" "[SEC] Security & Compliance" "[AI] AI/ML & Federated Learning" "[FINOPS] FinOps & Cost Management" "[PMO] PMO & Developer Experience")
ALL_TITLES=$(gh api "repos/${REPO}/milestones?state=all&per_page=100" --jq '[.[].title]')

for title in "${REQUIRED[@]}"; do
  exists=$(echo "$ALL_TITLES" | jq --arg t "$title" '[.[] | select(. == $t)] | length')
  if [[ "$exists" -gt 0 ]]; then
    log "  ✅ Found: $title"
  else
    log "  🔴 MISSING: $title"
    FAIL=1
  fi
done

# ── 5. SUMMARY ─────────────────────────────────────────────────────────────────
log ""
log "── SUMMARY ─────────────────────────────────────────────────────"

TOTAL=$(gh api "repos/${REPO}/milestones?state=all&per_page=100" --jq 'length')
OPEN_COUNT=$(gh api "repos/${REPO}/milestones?state=open&per_page=100" --jq 'length')
CLOSED_COUNT=$(gh api "repos/${REPO}/milestones?state=closed&per_page=100" --jq 'length')

log "  Total milestones:  $TOTAL"
log "  Open milestones:   $OPEN_COUNT"
log "  Closed milestones: $CLOSED_COUNT"
log "  Ghost milestones:  $GHOST_COUNT"
log "  Schema violations: $ADHOC_COUNT"
log ""

if [[ "$FAIL" -eq 0 ]]; then
  log "  ✅ ALL CHECKS PASSED — Milestone health: GREEN"
  exit 0
else
  log "  🔴 HEALTH CHECK FAILED — Run with AUTO_FIX=true to auto-remediate"
  log "  Tip: AUTO_FIX=true ./scripts/pmo/milestone_health_check.sh"
  exit 1
fi
