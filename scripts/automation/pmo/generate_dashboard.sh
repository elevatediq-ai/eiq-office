#!/usr/bin/env bash
# SHIM for legacy path
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "${SCRIPT_DIR}/analytics/generate_dashboard.sh" "$@"
