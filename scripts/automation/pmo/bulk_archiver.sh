#!/bin/bash
# High-Velocity Bulk Archiver for ElevatedIQ 100X PMO
# Author: GitHub Copilot (Gemini 3 Flash)

DOCS_DIR="/home/akushnir/ElevatedIQ-Mono-Repo/docs/management"
ARCHIVE_SESSIONS="$DOCS_DIR/_archived/sessions"
ARCHIVE_PHASES="$DOCS_DIR/_archived/phases"

mkdir -p "$ARCHIVE_SESSIONS"
mkdir -p "$ARCHIVE_PHASES"

echo "🚀 Starting 100X Bulk Archival..."

# Move SESSION_*.md files (excluding registry and master logs)
count_sessions=$(find "$DOCS_DIR" -maxdepth 1 -name "SESSION_*.md" | wc -l)
if [ "$count_sessions" -gt 0 ]; then
    echo "Found $count_sessions session files. Archiving..."
    mv "$DOCS_DIR"/SESSION_*.md "$ARCHIVE_SESSIONS/"
else
    echo "No individual session files found to archive."
fi

# Move PHASE_*.md files
count_phases=$(find "$DOCS_DIR" -maxdepth 1 -name "PHASE_*.md" | wc -l)
if [ "$count_phases" -gt 0 ]; then
    echo "Found $count_phases phase files. Archiving..."
    mv "$DOCS_DIR"/PHASE_*.md "$ARCHIVE_PHASES/"
else
    echo "No individual phase files found to archive."
fi

# Move EPIC_*.md files (if any)
count_epics=$(find "$DOCS_DIR" -maxdepth 1 -name "EPIC_*.md" | wc -l)
if [ "$count_epics" -gt 0 ]; then
    echo "Found $count_epics epic files. Archiving..."
    mv "$DOCS_DIR"/EPIC_*.md "$ARCHIVE_PHASES/"
fi

echo "✅ 100X Bulk Archival Complete."
