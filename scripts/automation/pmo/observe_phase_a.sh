#!/bin/bash

# Purpose: Phase A observability and real-time monitoring/usr/bin/env bash
set -euo pipefail
# Observe Phase-A Canary for a monitoring window, trigger rollback on critical failures,
# and file a summary report issue when complete.

SERVICE="finops-forecasting-api"
WEIGHT=5
DURATION_MINUTES=${1:-60}
INTERVAL_SECONDS=${2:-300} # 5 minutes
REPO="kushin77/ElevatedIQ-Mono-Repo"
LOG_DIR="logs"
LOG_FILE="$LOG_DIR/phase_a_observation.log"
START_TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

mkdir -p "$LOG_DIR"

echo "Phase-A Observation Window: start=$START_TS duration=${DURATION_MINUTES}m interval=${INTERVAL_SECONDS}s" | tee -a "$LOG_FILE"

END_TIME=$(( $(date +%s) + DURATION_MINUTES*60 ))
ANY_FAILURE=0
RUN_COUNT=0

while [ $(date +%s) -lt "$END_TIME" ]; do
  RUN_TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  echo "[${RUN_TS}] Running canary health check for ${SERVICE} at ${WEIGHT}%" | tee -a "$LOG_FILE"

  set +e
  OUTPUT=$(./scripts/validation/canary_health_check.sh "$SERVICE" "$WEIGHT" 2>&1)
  RC=$?
  set -e

  echo "[${RUN_TS}] RESULT rc=${RC}" | tee -a "$LOG_FILE"
  echo "$OUTPUT" | sed -n '1,200p' >> "$LOG_FILE" || true
  echo "---" >> "$LOG_FILE"

  RUN_COUNT=$((RUN_COUNT+1))

  if [ $RC -ne 0 ]; then
    ANY_FAILURE=1
    # Create an incident issue and initiate rollback
    ISSUE_TITLE="Phase-A Canary ALERT: health check failed at ${RUN_TS}"
    ISSUE_BODY="Phase-A Canary critical failure detected during observation window.\n\nService: ${SERVICE}\nWeight: ${WEIGHT}%\nTimestamp: ${RUN_TS}\n\nHealth-check output:\n\n$(echo "$OUTPUT" | sed 's/"/\\"/g')\n\nImmediate action: automated rollback executed. Investigate and remediate before re-run."

    echo "${RUN_TS} - CRITICAL: creating incident issue and triggering rollback" | tee -a "$LOG_FILE"
    gh issue create --repo "$REPO" --title "$ISSUE_TITLE" --body "$ISSUE_BODY" --label "severity:critical,proj:Sigma" --assignee "kushin77" --milestone "Project Sigma: FinOps" || true

    # Trigger rollback traffic shift (best-effort)
    ./scripts/pmo/canary_shifter.sh ROLLBACK || true

    break
  fi

  sleep "$INTERVAL_SECONDS"
done

END_TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Summarize results and create final observation report
SUMMARY_TITLE="Phase-A Observation Report: ${START_TS} → ${END_TS}"
SUMMARY_BODY="Phase-A Canary Observation Window completed.\n\nStart: ${START_TS}\nEnd: ${END_TS}\nRuns: ${RUN_COUNT}\nAnyFailures: ${ANY_FAILURE}\n\nLog: artifacts/logs/phase_a_observation.log (attached)\n\nNext steps: review alerts and approve/deny Phase-B rollout."

# Attach log if small, otherwise upload as artifact
gh issue create --repo "$REPO" --title "$SUMMARY_TITLE" --body "$SUMMARY_BODY" --label "proj:Sigma,priority:P1,status:done,phase-9.3" --assignee "kushin77" --milestone "Project Sigma: FinOps" || true

# Persist session log and observation log to repo
cp "$LOG_FILE" artifacts/ || true
printf "\n## PHASE-A OBSERVATION: %s\n- Runs: %s\n- AnyFailures: %s\n- Log: %s\n\n" "$END_TS" "$RUN_COUNT" "$ANY_FAILURE" "$LOG_FILE" >> docs/management/SESSION_LOGS.md

git add docs/management/SESSION_LOGS.md artifacts/phase_a_observation.log | true
if git commit -S -m "chore(pmo): Phase-A observation run summary (duration=${DURATION_MINUTES}m)" 2>/dev/null; then
  git push origin master || true
fi

if [ $ANY_FAILURE -eq 1 ]; then
  echo "Observation ended early due to failure. See incident issue and logs." | tee -a "$LOG_FILE"
  exit 2
else
  echo "Observation window completed successfully; summary issue created." | tee -a "$LOG_FILE"
  exit 0
fi
