#!/bin/bash
# 🚀 100X PMO Status Verifier
# Automatically cross-references Issue/PR statuses in markdown files with GitHub API.
# Prevents inaccurate reporting (Refs #3089)

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

FIX_MODE=false
FILE_TARGET=""

usage() {
    echo "Usage: $0 [file] [--fix]"
    echo "  --fix: Automatically update statuses in the file"
    exit 1
}

if [[ "$#" -eq 0 ]]; then
    usage
fi

for arg in "$@"; do
    if [[ "$arg" == "--fix" ]]; then
        FIX_MODE=true
    else
        FILE_TARGET="$arg"
    fi
done

if [[ ! -f "$FILE_TARGET" ]]; then
    echo -e "${RED}Error: File $FILE_TARGET not found.${NC}"
    exit 1
fi

echo -e "🔍 Auditing $FILE_TARGET..."

# Performance guard: only scan refs in the staged diff of the file (pre-commit),
# or cap at 25 refs if running standalone — prevents O(n*API) unbounded loops.
MAX_REFS=25
STAGED_REFS=$(git diff --cached "$FILE_TARGET" 2>/dev/null | grep '^+' | grep -oE '#[0-9]{4,}' | sort -u)
if [[ -n "$STAGED_REFS" ]]; then
    # Pre-commit mode: only verify newly added/changed refs
    REFS=$(echo "$STAGED_REFS" | head -${MAX_REFS})
    echo "  📌 Checking ${MAX_REFS} staged refs only (performance guard)"
else
    # Standalone mode: sample the most recent refs
    REFS=$(grep -oE '#[0-9]{4,}' "$FILE_TARGET" | tac | sort -u | head -${MAX_REFS})
    echo "  📌 Sampling ${MAX_REFS} refs (cap for performance)"
fi

for REF in $REFS; do
    NUM=${REF#*#}

    # Check if it's a PR or Issue
    INFO=$(gh pr view "$NUM" --json state,mergedAt 2>/dev/null)
    if [[ $? -eq 0 ]]; then
        STATE=$(echo "$INFO" | jq -r .state)
        MERGED=$(echo "$INFO" | jq -r .mergedAt)

        # Determine actual status
        if [[ "$STATE" == "MERGED" ]] || [[ "$MERGED" != "null" ]]; then
            ACTUAL="✅ MERGED"
        elif [[ "$STATE" == "OPEN" ]]; then
            ACTUAL="⏳ OPEN"
        else
            ACTUAL="❌ CLOSED"
        fi
    else
        # Try as Issue
        INFO=$(gh issue view "$NUM" --json state 2>/dev/null)
        if [[ $? -eq 0 ]]; then
            STATE=$(echo "$INFO" | jq -r .state)
            if [[ "$STATE" == "OPEN" ]]; then
                ACTUAL="⏳ OPEN"
            else
                ACTUAL="✅ CLOSED"
            fi
        else
            continue # Not found or other error
        fi
    fi

    # Search for the line containing this number
    LINE=$(grep "$REF" "$FILE_TARGET")

    # Check if documented status matches reality
    # Patterns: ✅ MERGED, ✅ CLOSED, ⏳ OPEN, ❌ CLOSED
    if [[ "$LINE" == *"$ACTUAL"* ]]; then
        echo -e "${GREEN}PASS${NC}: $REF is correctly marked as $ACTUAL"
    else
        echo -e "${RED}FAIL${NC}: $REF is documented incorrectly."
        echo "   Documented: $LINE"
        echo "   Reality:    $ACTUAL"

        if [[ "$FIX_MODE" == "true" ]]; then
            echo -e "${GREEN}FIXING${NC}: Updating $REF status..."
            # Replace common status patterns with reality
            # This is a bit aggressive, but we target the specific line
            sed -i "/$REF/s/✅ MERGED/$ACTUAL/g" "$FILE_TARGET"
            sed -i "/$REF/s/❌ CLOSED/$ACTUAL/g" "$FILE_TARGET"
            sed -i "/$REF/s/✅ CLOSED/$ACTUAL/g" "$FILE_TARGET"
            sed -i "/$REF/s/⏳ OPEN/$ACTUAL/g" "$FILE_TARGET"
            # If no status icon found, add it
            if ! grep -q "✅\|⏳\|❌" <<< "$LINE"; then
                sed -i "/$REF/s/$REF/$ACTUAL $REF/g" "$FILE_TARGET"
            fi
        else
            exit 1 # Block if not fixing
        fi
    fi
done

echo -e "${GREEN}Audit Complete.${NC}"
