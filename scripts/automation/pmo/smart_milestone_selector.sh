#!/usr/bin/env bash
##############################################################################
# Smart Milestone Selector (AI-Enhanced)
# FedRAMP: [NIST-PM-5] Project Management
##############################################################################

TITLE="${1:-}"
BODY="${2:-}"
LABELS="${3:-}"

# 10X Upgrade: Use Python Intelligence Engine (with Ollama capability)
python3 "$(dirname "${BASH_SOURCE[0]}")/ai_classifier.py" "$TITLE" "$BODY" "$LABELS"
exit 0

# Default to Backlog
echo "Project Eta: Backlog"
