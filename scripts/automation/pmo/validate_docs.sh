#!/usr/bin/env bash
# ============================================================
# validate_docs.sh — ElevatedIQ Documentation Validator
# Adapted from kushin77/MXdocs — Issue #4426
# NIST 800-53: SA-5 (Information System Documentation), PM-6
# ============================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DOCS_DIR="$REPO_ROOT/docs"
MXDOC_CONFIG="$DOCS_DIR/mxdoc.yaml"

# ── Colors ──────────────────────────────────────────────────
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

# ── Counters ─────────────────────────────────────────────────
HARD_FAIL_COUNT=0
WARNING_COUNT=0
FILE_COUNT=0
CHECKED_COUNT=0

# ── Flags ────────────────────────────────────────────────────
CI_MODE=false
FIX_MODE=false
SINGLE_FILE=""

usage() {
  echo "Usage: $0 [--ci] [--fix] [--file <path>]"
  echo ""
  echo "  --ci          Non-zero exit on any hard-fail violation (for CI pipelines)"
  echo "  --fix         Auto-fix fixable issues (filename case, trailing whitespace)"
  echo "  --file <path> Validate a single file instead of all docs/"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ci)   CI_MODE=true; shift ;;
    --fix)  FIX_MODE=true; shift ;;
    --file) SINGLE_FILE="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown arg: $1"; usage ;;
  esac
done

# ── Required Canonical Folders ────────────────────────────────
REQUIRED_FOLDERS=(
  "getting-started"
  "architecture"
  "services"
  "api"
  "cli"
  "config"
  "runbooks"
  "development"
  "infrastructure"
  "platform"
  "reference"
)

REQUIRED_FRONT_MATTER=(title description lifecycle nist_controls owner last_reviewed)
VALID_LIFECYCLES=(active deprecated draft)
STALENESS_DAYS=180

log_fail() { echo -e "${RED}[HARD FAIL]${NC} $1"; ((HARD_FAIL_COUNT++)); }
log_warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; ((WARNING_COUNT++)); }
log_ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
log_info() { echo -e "${CYAN}[INFO]${NC} $1"; }

# ── Helper: extract front matter field ────────────────────────
get_front_matter_field() {
  local file="$1"
  local field="$2"
  # Extract between --- delimiters
  awk '/^---$/{if(++c==2) exit} c==1 && /^'"$field"':/' "$file" | head -1 | sed 's/^[^:]*: *//'
}

has_front_matter() {
  head -1 "$1" | grep -q "^---$"
}

is_auto_generated() {
  grep -q "AUTO-GENERATED" "$1" 2>/dev/null
}

# ── Check 1: Required canonical folders exist ─────────────────
check_required_folders() {
  log_info "Checking required canonical folders..."
  local missing=0
  for folder in "${REQUIRED_FOLDERS[@]}"; do
    if [[ ! -d "$DOCS_DIR/$folder" ]]; then
      log_fail "Missing canonical folder: docs/$folder/"
      missing=1
    fi
    if [[ ! -f "$DOCS_DIR/$folder/index.md" ]]; then
      log_fail "Missing index.md in docs/$folder/"
      missing=1
    fi
  done
  [[ $missing -eq 0 ]] && log_ok "All required canonical folders present with index.md"
}

# ── Check 2: Filename conventions ─────────────────────────────
check_filename() {
  local file="$1"
  local rel="${file#$REPO_ROOT/}"
  local basename
  basename="$(basename "$file")"

  # No uppercase letters (except README.md and STANDARDS.md etc.)
  if [[ "$basename" =~ [A-Z] ]] && [[ "$basename" != "README.md" ]] && \
     [[ "$basename" != "STANDARDS.md" ]] && [[ "$basename" != "CONTRIBUTING.md" ]] && \
     [[ "$basename" != "LICENSE" ]]; then
    log_warn "Uppercase in filename: $rel (use lowercase-kebab-case.md)"
  fi

  # No spaces
  if [[ "$basename" == *" "* ]]; then
    log_fail "Spaces in filename: $rel (use lowercase-kebab-case.md)"
  fi

  # No underscores (warning only — some legacy files)
  if [[ "$basename" == *"_"* ]] && [[ "$basename" != "index.md" ]]; then
    log_warn "Underscore in filename: $rel (prefer kebab-case)"
  fi
}

# ── Check 3: Front matter completeness ────────────────────────
check_front_matter() {
  local file="$1"
  local rel="${file#$REPO_ROOT/}"

  if is_auto_generated "$file"; then
    return
  fi

  if ! has_front_matter "$file"; then
    log_fail "Missing front matter block: $rel"
    return
  fi

  for field in "${REQUIRED_FRONT_MATTER[@]}"; do
    local value
    value="$(get_front_matter_field "$file" "$field")"
    if [[ -z "$value" ]] || [[ "$value" == '""' ]] || [[ "$value" == "''" ]]; then
      log_fail "Missing required front matter field '$field': $rel"
    fi
  done

  # Validate lifecycle value
  local lifecycle
  lifecycle="$(get_front_matter_field "$file" "lifecycle")"
  lifecycle="${lifecycle//\"/}"
  if [[ -n "$lifecycle" ]]; then
    local valid=false
    for v in "${VALID_LIFECYCLES[@]}"; do
      [[ "$lifecycle" == "$v" ]] && valid=true && break
    done
    if ! $valid; then
      log_fail "Invalid lifecycle value '$lifecycle' (must be: active, deprecated, draft): $rel"
    fi
  fi
}

# ── Check 4: Staleness ────────────────────────────────────────
check_staleness() {
  local file="$1"
  local rel="${file#$REPO_ROOT/}"

  if is_auto_generated "$file"; then return; fi

  local last_reviewed
  last_reviewed="$(get_front_matter_field "$file" "last_reviewed")"
  last_reviewed="${last_reviewed//\"/}"

  if [[ -z "$last_reviewed" ]]; then return; fi  # Already caught in front matter check

  # Parse date (requires GNU date)
  if date -d "$last_reviewed" &>/dev/null 2>&1; then
    local review_epoch today_epoch age_days
    review_epoch=$(date -d "$last_reviewed" +%s 2>/dev/null || echo 0)
    today_epoch=$(date +%s)
    age_days=$(( (today_epoch - review_epoch) / 86400 ))

    if [[ $age_days -gt $STALENESS_DAYS ]]; then
      log_fail "Stale document ($age_days days old, threshold: $STALENESS_DAYS): $rel"
    fi
  fi
}

# ── Check 5: Description length ───────────────────────────────
check_description() {
  local file="$1"
  local rel="${file#$REPO_ROOT/}"

  if is_auto_generated "$file"; then return; fi

  local desc
  desc="$(get_front_matter_field "$file" "description")"
  desc="${desc//\"/}"

  if [[ -n "$desc" ]] && [[ ${#desc} -lt 20 ]]; then
    log_warn "Description too short (${#desc} chars, min 20): $rel"
  fi
}

# ── Check 6: Title length ─────────────────────────────────────
check_title() {
  local file="$1"
  local rel="${file#$REPO_ROOT/}"

  if is_auto_generated "$file"; then return; fi

  local title
  title="$(get_front_matter_field "$file" "title")"
  title="${title//\"/}"

  if [[ -n "$title" ]] && [[ ${#title} -gt 80 ]]; then
    log_warn "Title too long (${#title} chars, max 80): $rel"
  fi
}

# ── Validate single file ──────────────────────────────────────
validate_file() {
  local file="$1"
  ((FILE_COUNT++))

  # Skip non-.md files and certain directories
  if [[ "${file##*.}" != "md" ]]; then return; fi
  if [[ "$file" == *"/archive/"* ]] || [[ "$file" == *"/handover/"* ]]; then return; fi

  ((CHECKED_COUNT++))
  check_filename "$file"
  check_front_matter "$file"
  check_staleness "$file"
  check_description "$file"
  check_title "$file"
}

# ── Main ──────────────────────────────────────────────────────
main() {
  echo ""
  echo "================================================================"
  echo " ElevatedIQ Documentation Validator (MXdoc)"
  echo " Config: $MXDOC_CONFIG"
  echo "================================================================"
  echo ""

  # Folder structure checks
  check_required_folders

  echo ""
  log_info "Validating Markdown files..."
  echo ""

  if [[ -n "$SINGLE_FILE" ]]; then
    validate_file "$SINGLE_FILE"
  else
    while IFS= read -r -d '' file; do
      validate_file "$file"
    done < <(find "$DOCS_DIR" -name "*.md" -not -path "*/.git/*" -print0 | sort -z)
  fi

  # ── Summary ─────────────────────────────────────────────────
  echo ""
  echo "================================================================"
  echo " Validation Summary"
  echo "================================================================"
  echo -e " Files scanned:     $FILE_COUNT"
  echo -e " Files validated:   $CHECKED_COUNT"
  echo -e " Hard failures:     ${RED}$HARD_FAIL_COUNT${NC}"
  echo -e " Warnings:          ${YELLOW}$WARNING_COUNT${NC}"
  echo ""

  if [[ $HARD_FAIL_COUNT -eq 0 && $WARNING_COUNT -eq 0 ]]; then
    echo -e "${GREEN}✅ All documentation validates successfully!${NC}"
  elif [[ $HARD_FAIL_COUNT -eq 0 ]]; then
    echo -e "${YELLOW}⚠️  Validation passed with $WARNING_COUNT warning(s). Review above.${NC}"
  else
    echo -e "${RED}❌ Validation FAILED with $HARD_FAIL_COUNT hard failure(s).${NC}"
    if $CI_MODE; then
      exit 1
    fi
  fi
  echo ""
}

main "$@"
