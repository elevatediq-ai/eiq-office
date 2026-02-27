#!/usr/bin/env bash
# ==============================================================================
# 🚀 ElevatedIQ 10X PMO: Fast Issue Creator (Sub-2s)
# ==============================================================================
# Purpose: Extremely fast issue creation from natural language strings.
# Usage: ./10x_fast_issue.sh "feat(api): implement redis caching for phase 7"
# Refs: #3446
# ==============================================================================

set -euo pipefail

input="$*"

if [[ -z "$input" ]]; then
    echo "Usage: $0 \"issue description\""
    exit 1
fi

# 1. Very Fast Type/Phase Extraction (Regex)
type="task"
priority="p2"
phase="foundation"

if [[ "$input" =~ ^feat ]]; then type="feature"; fi
if [[ "$input" =~ ^fix ]]; then type="bug"; fi
if [[ "$input" =~ ^security ]]; then type="security"; fi
if [[ "$input" =~ ^docs ]]; then type="docs"; fi

if [[ "$input" =~ "phase 7" ]]; then phase="foundation"; fi
if [[ "$input" =~ "phase 6.3" ]]; then phase="foundation"; fi
if [[ "$input" =~ "urgent" ]]; then priority="p0"; fi

# 2. Extract Title
title="[$(echo $type | tr '[:lower:]' '[:upper:]')] $input"

# 3. Create Issue (Async for speed)
echo "🚀 Creating 10X issue: $title..."

(
    gh issue create --repo "kushin77/ElevatedIQ-Mono-Repo" \
        --title "$title" \
        --body "## Objective\n$input\n\n---\n_Created via 10X Fast Issue Creator_" \
        --label "type:task,priority-$priority,pmo" > /dev/null
) &

echo "✅ Dispatch complete. Work tracked."
