#!/usr/bin/env bash
# ==============================================================================
# 100X PMO: Infrastructure Drift Monitoring Agent (NIST SI-4)
# ==============================================================================
# Purpose: Continuously monitor 11 critical Phase A/7.0 modules for drift.
# Failsafe: Automatically creates P0 GitHub issues on drift detection.
# NIST SI-4: Continuous Monitoring
# NIST CP-2: Contingency Planning (Auto-Remediation)
# ==============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOG_FILE="${REPO_ROOT}/logs/drift_monitor.log"
PMO_CLI="${REPO_ROOT}/infra/.ci-audit-venv/bin/python -m pmo.cli"
mkdir -p "$(dirname "$LOG_FILE")"

# ── Log rotation (NIST AU-6: keep last 1000 lines, ~100KB) ──────────────────
MAX_LOG_LINES="${MAX_LOG_LINES:-1000}"
if [[ -f "$LOG_FILE" ]] && (( $(wc -l < "$LOG_FILE") > MAX_LOG_LINES )); then
  tail -n "$MAX_LOG_LINES" "$LOG_FILE" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE"
fi

# ── Monitor guards (circuit breaker, sentinel) ─────────────────────────────
MONITOR_SCRIPT_ID="drift-monitor"
MONITOR_CB_LIMIT="${MONITOR_CB_LIMIT:-5}"
MONITOR_CB_WINDOW="${MONITOR_CB_WINDOW:-300}"
MONITOR_LOG_PREFIX="[DRIFT]"
# shellcheck source=scripts/lib/monitor_guards.sh
if [[ -f "${REPO_ROOT}/scripts/lib/monitor_guards.sh" ]]; then
  source "${REPO_ROOT}/scripts/lib/monitor_guards.sh"
else
  circuit_breaker_check() { return 0; }
  circuit_breaker_record() { :; }
fi

# Enable auto-remediation by default if not set
REMEDIATE="${REMEDIATE:-true}"

# ── Dynamic module discovery (NIST CM-8: Component Inventory) ───────────────
# Build the MODULES list at runtime from any infra sub-directory that contains
# a main.tf — avoids ghost-module warnings when phase dirs haven't been
# provisioned yet. Falls back to the static override list when DRIFT_MODULES
# env var is set (useful for targeted CI runs).
build_modules() {
  local -a discovered=()
  if [[ -n "${DRIFT_MODULES:-}" ]]; then
    # Caller-supplied override: one absolute path per line
    while IFS= read -r line; do
      [[ -d "$line" ]] && discovered+=("$line")
    done <<< "${DRIFT_MODULES}"
  else
    # Auto-discover: any directory under infra/ with a main.tf
    while IFS= read -r tf_file; do
      discovered+=("$(dirname "$tf_file")")
    done < <(find "${REPO_ROOT}/infra" -maxdepth 4 -name "main.tf" -not -path "*/.terraform/*" 2>/dev/null | sort)
  fi
  printf '%s\n' "${discovered[@]}"
}

mapfile -t MODULES < <(build_modules)

if [[ ${#MODULES[@]} -eq 0 ]]; then
  echo "[$(date -u)] ℹ️  No Terraform modules found under infra/. Drift check skipped." >> "$LOG_FILE"
  echo "[$(date -u)] 🏁 Drift check completed." >> "$LOG_FILE"
  exit 0
fi

echo "[$(date -u)] 📋 Discovered ${#MODULES[@]} Terraform module(s) for drift check." >> "$LOG_FILE"

echo "[$(date -u)] 🚀 Starting Drift Monitoring Agent..." >> "$LOG_FILE"

for MODULE in "${MODULES[@]}"; do
    echo "[$(date -u)] 🔍 Checking drift for: $(basename "$MODULE")..." >> "$LOG_FILE"

    cd "$MODULE"

    # Run terraform plan with -detailed-exitcode
    # 0 = Succeeded, no changes
    # 1 = Error
    # 2 = Succeeded, there are changes (drift)

    # Note: Using -input=false for non-interactive mode
    # Assuming terraform init was already run by previous validation turn

    set +e
    terraform plan -detailed-exitcode -input=false -no-color > /tmp/tf_drift_plan.txt 2>&1
    EXIT_CODE=$?
    set -e

    if [ $EXIT_CODE -eq 2 ]; then
        echo "[$(date -u)] 🚨 DRIFT DETECTED in $(basename "$MODULE")" >> "$LOG_FILE"

        # Check if an open drift issue already exists to avoid duplication
        EXISTING_ISSUE=$(gh issue list --repo kushin77/ElevatedIQ-Mono-Repo --state open --search "DRIFT: $(basename "$MODULE")" --json number --jq '.[0].number')

        if [ -n "$EXISTING_ISSUE" ]; then
            echo "[$(date -u)] 📋 Existing issue #$EXISTING_ISSUE found. Adding update." >> "$LOG_FILE"
            if circuit_breaker_check; then
              gh issue comment "$EXISTING_ISSUE" --repo kushin77/ElevatedIQ-Mono-Repo --body "🚨 **Drift re-detected at $(date -u)**

Plan summary:
\`\`\`
$(grep 'Plan:' /tmp/tf_drift_plan.txt || echo "Changes detected, plan log truncated.")
\`\`\`" && circuit_breaker_record
            else
              echo "[$(date -u)] [CIRCUIT-BREAKER] gh issue comment suppressed (rate limit)" >> "$LOG_FILE"
            fi
        else
            echo "[$(date -u)] 🎫 Creating new P0 issue for drift." >> "$LOG_FILE"
            if circuit_breaker_check; then
            gh issue create --repo kushin77/ElevatedIQ-Mono-Repo \
                --title "🚨 DRIFT: $(basename "$MODULE") (Phase A/7.0)" \
                --label "type:bug,priority:p0,phase-7,drift" \
                --body "## 🚨 Infrastructure Drift Detected
The drift monitoring agent detected a discrepancy in the **$(basename "$MODULE")** module.

### Module Path
\`$MODULE\`

### Detection Timestamp
$(date -u)

### Plan Output Extract
\`\`\`
$(head -n 50 /tmp/tf_drift_plan.txt)
...
$(tail -n 10 /tmp/tf_drift_plan.txt)
\`\`\`

### Recommended Action
- Inspect the plan results above.
- Investigate out-of-band changes in the cloud console.
- Run \`terraform apply\` to rectify or update IaC to match reality.

---
_Auto-generated by 100X PMO Drift Agent (NIST SI-4)_" && circuit_breaker_record
            else
              echo "[$(date -u)] [CIRCUIT-BREAKER] gh issue create suppressed (rate limit)" >> "$LOG_FILE"
            fi
        fi

        # **Self-Healing Subsystem (NIST CP-2)**
        if [ "$REMEDIATE" = "true" ]; then
            echo "[$(date -u)] 🛠️ Automating remediation for $(basename "$MODULE")..." >> "$LOG_FILE"
            export PYTHONPATH="${REPO_ROOT}/apps/pmo-cli"
            REMEDIATION_LOG=$( $PMO_CLI healing remediate \
                --action terraform_apply \
                --service "$(basename "$MODULE")" \
                --path "$MODULE" 2>&1 )

            if [ $? -eq 0 ]; then
                echo "[$(date -u)] ✅ Remediation successful for $(basename "$MODULE")." >> "$LOG_FILE"
                # Update the issue with remediation status
                EXISTING_ISSUE_NUM=$(gh issue list --repo kushin77/ElevatedIQ-Mono-Repo --state open --search "DRIFT: $(basename "$MODULE")" --json number --jq '.[0].number')
                if [ -n "$EXISTING_ISSUE_NUM" ]; then
                    gh issue comment "$EXISTING_ISSUE_NUM" --repo kushin77/ElevatedIQ-Mono-Repo --body "✅ **Auto-Remediation Successful** at $(date -u).
Remediation output:
\`\`\`
$REMEDIATION_LOG
\`\`\`"
                fi
            else
                echo "[$(date -u)] ❌ Remediation FAILED for $(basename "$MODULE")." >> "$LOG_FILE"
                echo "$REMEDIATION_LOG" >> "$LOG_FILE"
            fi
        fi
    elif [ $EXIT_CODE -eq 1 ]; then
        echo "[$(date -u)] ❌ ERROR during plan for $(basename "$MODULE")" >> "$LOG_FILE"
        cat /tmp/tf_drift_plan.txt >> "$LOG_FILE"
    else
        echo "[$(date -u)] ✅ $(basename "$MODULE") is in sync." >> "$LOG_FILE"
    fi
done

echo "[$(date -u)] 🏁 Drift check completed." >> "$LOG_FILE"
