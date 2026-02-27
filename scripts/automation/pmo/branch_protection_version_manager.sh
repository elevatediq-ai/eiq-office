#!/usr/bin/env bash

################################################################################
# Branch Protection Baseline Version Manager
#
# Manages semantic versioning for branch protection policy baseline.
# Tracks version history, generates release notes, and creates git tags.
#
# Usage:
#   ./branch_protection_version_manager.sh [command] [options]
#
# Commands:
#   list              - List all baseline versions
#   show VERSION      - Show details for specific version
#   next              - Calculate next version number
#   tag-version       - Create git tag for current version
#   release-notes     - Generate release notes
#
# NIST Controls: CM-2 (Baseline), CM-3 (Change Control), AU-2 (Audit Generation)
################################################################################

set -euo pipefail

REPO_ROOT="${1:-$(pwd)}"
COMMAND="${2:-list}"
VERSION_ARG="${3:-}"
MANIFEST_FILE=".pmo/baseline-versions.json"
CHANGELOG_FILE="docs/governance/BRANCH_PROTECTION_POLICY_BASELINE_CHANGELOG.md"

cd "$REPO_ROOT"

# ==============================================================================
# FUNCTION: Validate manifest file exists
# ==============================================================================
validate_manifest() {
  if [[ ! -f "$MANIFEST_FILE" ]]; then
    echo "❌ Missing version manifest: $MANIFEST_FILE"
    return 1
  fi
  return 0
}

# ==============================================================================
# FUNCTION: Get current version from manifest
# ==============================================================================
get_current_version() {
  if ! validate_manifest; then
    return 1
  fi
  jq -r '.current_version' "$MANIFEST_FILE" 2>/dev/null || echo "0.baseline.1.0.0"
}

# ==============================================================================
# FUNCTION: Parse semantic version components
# ==============================================================================
parse_version() {
  local version="$1"
  # Expected format: v0.baseline.MAJOR.MINOR.PATCH or 0.baseline.MAJOR.MINOR.PATCH
  version="${version#v}"

  if [[ ! "$version" =~ ^0\.baseline\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "❌ Invalid version format: $version (expected: v0.baseline.X.Y.Z)"
    return 1
  fi

  echo "$version"
}

# ==============================================================================
# FUNCTION: Calculate next patch version
# ==============================================================================
next_patch() {
  local current="$1"
  local major=$(echo "$current" | cut -d. -f3)
  local minor=$(echo "$current" | cut -d. -f4)
  local patch=$(echo "$current" | cut -d. -f5)
  patch=$((patch + 1))
  echo "0.baseline.$major.$minor.$patch"
}

# ==============================================================================
# FUNCTION: Calculate next minor version
# ==============================================================================
next_minor() {
  local current="$1"
  local major=$(echo "$current" | cut -d. -f3)
  local minor=$(echo "$current" | cut -d. -f4)
  minor=$((minor + 1))
  echo "0.baseline.$major.$minor.0"
}

# ==============================================================================
# FUNCTION: Calculate next major version
# ==============================================================================
next_major() {
  local current="$1"
  local major=$(echo "$current" | cut -d. -f3)
  major=$((major + 1))
  echo "0.baseline.$major.0.0"
}

# ==============================================================================
# FUNCTION: List all versions
# ==============================================================================
list_versions() {
  if ! validate_manifest; then
    return 1
  fi

  echo "📋 Baseline Version History"
  echo ""

  jq -r '.versions[] | "\(.version)\t\(.released_at)\t\(.approved_by)"' "$MANIFEST_FILE" | \
  while read -r version released approver; do
    echo "  $version - Released: $released by $approver"
  done

  echo ""
  echo "Current: $(get_current_version)"
}

# ==============================================================================
# FUNCTION: Show version details
# ==============================================================================
show_version() {
  local version="$1"

  if ! validate_manifest; then
    return 1
  fi

  jq ".versions[] | select(.version == \"$version\")" "$MANIFEST_FILE"
}

# ==============================================================================
# FUNCTION: Get next version suggestion
# ==============================================================================
calculate_next() {
  local current=$(get_current_version)

  echo "📊 Version Calculator"
  echo ""
  echo "Current: $current"
  echo ""
  echo "Next Suggestions:"
  echo "  Patch (bug fix):     $(next_patch "$current")"
  echo "  Minor (new feature): $(next_minor "$current")"
  echo "  Major (breaking):    $(next_major "$current")"
}

# ==============================================================================
# FUNCTION: Create git tag for baseline version
# ==============================================================================
tag_version() {
  local version=$(get_current_version)
  local tag="v$version"

  echo "🏷️  Tagging baseline version: $tag"

  # Check if tag already exists
  if git rev-parse "$tag" >/dev/null 2>&1; then
    echo "⚠️  Tag already exists: $tag"
    return 0
  fi

  # Create annotated tag
  git tag -a "$tag" -m "Baseline version $version - $(date -u +%Y-%m-%d)" \
    -m "See: $MANIFEST_FILE" \
    -m "Changelog: $CHANGELOG_FILE"

  echo "✅ Tag created: $tag"
  echo "📝 To push tag: git push origin $tag"
}

# ==============================================================================
# FUNCTION: Generate release notes from changelog
# ==============================================================================
generate_release_notes() {
  local version=$(get_current_version)

  echo "📝 Release Notes - Version $version"
  echo ""
  echo "=== Branch Protection Policy Baseline Release ==="
  echo ""
  echo "**Version**: $version"
  echo "**Released**: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo ""

  if [[ -f "$CHANGELOG_FILE" ]]; then
    echo "**Changes**:"
    echo ""
    # Extract changelog entries for this version (simplified extraction)
    grep -E '^- |^## ' "$CHANGELOG_FILE" | head -10 | sed 's/^/  /'
  fi

  echo ""
  echo "**Reference**: GitHub Issue #5403"
  echo "**NIST Controls**: CM-2, CM-3, AU-2"
}

# ==============================================================================
# MAIN LOGIC
# ==============================================================================

case "$COMMAND" in
  list)
    list_versions
    ;;

  show)
    if [[ -z "$VERSION_ARG" ]]; then
      echo "❌ Version required: $0 $COMMAND VERSION"
      exit 1
    fi
    show_version "$VERSION_ARG"
    ;;

  next)
    calculate_next
    ;;

  tag-version)
    tag_version
    ;;

  release-notes)
    generate_release_notes
    ;;

  current)
    get_current_version
    ;;

  *)
    echo "Usage: $0 <repo_root> <command> [version]"
    echo ""
    echo "Commands:"
    echo "  list              - List all baseline versions"
    echo "  show VERSION      - Show details for specific version"
    echo "  next              - Calculate next version number"
    echo "  tag-version       - Create git tag for current version"
    echo "  release-notes     - Generate release notes"
    echo "  current           - Show current version"
    exit 1
    ;;
esac
