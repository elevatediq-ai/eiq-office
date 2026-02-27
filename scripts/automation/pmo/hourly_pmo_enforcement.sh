#!/bin/bash
# -----------------------------------------------------------------------------
# ElevatedIQ: Hourly PMO Enforcement Script
# Purpose: Scans all open issues for compliance and alerts on violations.
# -----------------------------------------------------------------------------

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPLIANCE_SCRIPT="$SCRIPT_DIR/issue_compliance_check.sh"
NIST_VALIDATOR="$SCRIPT_DIR/compliance_validator.sh"
LOG_FILE="/home/akushnir/ElevatedIQ-Mono-Repo/logs/pmo_enforcement.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "--- [$(date)] Starting PMO Enforcement Scan ---" >> "$LOG_FILE"

# Ensure compliance scripts are executable
chmod +x "$COMPLIANCE_SCRIPT"
chmod +x "$NIST_VALIDATOR"

# 1. Run Issue Compliance Scan
echo "Running Issue Compliance Scan..." >> "$LOG_FILE"
SCAN_RESULTS=$("$COMPLIANCE_SCRIPT" scan)
echo "$SCAN_RESULTS" >> "$LOG_FILE"

# 2. Run NIST Compliance Validator
echo "Running NIST Compliance Validator..." >> "$LOG_FILE"
VALIDATOR_RESULTS=$("$NIST_VALIDATOR")
echo "$VALIDATOR_RESULTS" >> "$LOG_FILE"

# Identify failures for summary
NON_COMPLIANT_ISSUES=$(echo "$SCAN_RESULTS" | grep "non-compliance" | wc -l)
NIST_FAILURES=$(echo "$VALIDATOR_RESULTS" | grep "\[FAIL\]" | wc -l)

if [ "$NON_COMPLIANT_ISSUES" -gt 0 ] || [ "$NIST_FAILURES" -gt 0 ]; then
    echo -e "${YELLOW}⚠ Found $NON_COMPLIANT_ISSUES issue violations and $NIST_FAILURES NIST failures.${NC}"
else
    echo -e "${GREEN}✓ All checks passed.${NC}"
fi

echo "--- [$(date)] Scan Completed ---" >> "$LOG_FILE"
