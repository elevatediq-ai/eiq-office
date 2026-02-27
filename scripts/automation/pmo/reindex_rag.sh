#!/usr/bin/env bash
# Re-run RAG indexing for sessions that missed indexing due to ChromaDB downtime.
# Usage: SESSION_ID=xyz ./scripts/pmo/reindex_rag.sh OR ./scripts/pmo/reindex_rag.sh [session_id]

set -euo pipefail

export SESSION_ID="${SESSION_ID:-${1:-all}}"

echo "🔁 Reindexing RAG for session: $SESSION_ID"

# Check if chroma CLI or service is available (placeholder check)
if ! command -v chroma >/dev/null 2>&1; then
    echo "⚠️  Chroma CLI not available. Please ensure ChromaDB is accessible and chroma CLI is installed."
    exit 2
fi

# Use environment variable to pass SESSION_ID to the Python sub-process
python3 - << 'PY'
import os
import sys

sid = os.environ.get('SESSION_ID', 'all')
print(f"(placeholder) Indexing session {sid}...")
# Real implementation should load documents for the session, embed, and upsert to Chroma.
PY

echo "✅ Reindexing started (check logs for progress)."
