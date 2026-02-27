#!/usr/bin/env bash
# PMO Health Checker
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh" || source "${SCRIPT_DIR}/common.sh"

pmo_health_check
