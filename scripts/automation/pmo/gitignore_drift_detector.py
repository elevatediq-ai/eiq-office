#!/usr/bin/env python3
import os
import subprocess
import sys

# ElevatedIQ Mono-Repo Hygiene Detection
# Aligned with NIST 800-53 CM-9
# Issue #2026: [10X-4] Automated .gitignore & Root Hygiene

MAX_DIR_SIZE_MB = 100
MAX_UNTRACKED_FILE_MB = 50


def get_directory_size(path):
    """get_directory_size function."""
    total_size = 0
    for dirpath, dirnames, filenames in os.walk(path):
        for f in filenames:
            fp = os.path.join(dirpath, f)
            if not os.path.islink(fp):
                total_size += os.path.getsize(fp)
    return total_size / (1024 * 1024)


def check_unignored_drift():
    """check_unignored_drift function."""
    print("🔍 Scanning for .gitignore drift and root hygiene violations...")

    # 1. Check for untracked files/dirs
    try:
        untracked = (
            subprocess.check_output(
                ["git", "ls-files", "--others", "--exclude-standard"],
                stderr=subprocess.STDOUT,
            )
            .decode("utf-8")
            .splitlines()
        )
    except subprocess.CalledProcessError as e:
        print(f"❌ Failed to list untracked files: {e.output.decode()}")
        return False

    violations = []

    # Group results by top-level directory for drill-down

    for item in untracked:
        top_level = item.split("/")[0]
        # Skip libs directory as it's a legitimate large mono-repo component
        if top_level == "libs":
            continue
        if os.path.isdir(item):
            # Only flag if the entire directory is untracked (not just some files)
            try:
                tracked_in_dir = (
                    subprocess.check_output(["git", "ls-files", item], stderr=subprocess.STDOUT).decode("utf-8").strip()
                )
                # If no tracked files in this directory, check size
                if not tracked_in_dir:
                    size = get_directory_size(item)
                    if size > MAX_DIR_SIZE_MB:
                        violations.append(
                            f"Directory '{item}' is completely untracked and exceeds {MAX_DIR_SIZE_MB}MB ({size:.2f}MB)"
                        )
            except subprocess.CalledProcessError:
                # Directory might not exist or other error, skip
                pass
        else:
            size = os.path.getsize(item) / (1024 * 1024)
            if size > MAX_UNTRACKED_FILE_MB:
                violations.append(f"File '{item}' is untracked and exceeds {MAX_UNTRACKED_FILE_MB}MB ({size:.2f}MB)")

    # 2. Check for root hygiene (forbidden patterns in .folder-hygiene.yaml)
    # Simple check for common forbidden items at root
    forbidden_at_root = [".vsc_dummy"]  # __pycache__ and _unorganized allowed if managed
    for forbidden in forbidden_at_root:
        if os.path.exists(forbidden):
            violations.append(f"Root Hygiene Violation: '{forbidden}' should not exist in root.")

    if violations:
        print("\n🚨 HYGIENE FAILURES DETECTED:")
        for v in violations:
            print(f"  - {v}")
        print("\nSuggestion: Update .gitignore or move/delete these files to maintain mono-repo stability.")
        return False

    print("✅ No significant .gitignore drift or hygiene violations detected.")
    return True


if __name__ == "__main__":
    success = check_unignored_drift()
    if not success:
        sys.exit(1)
    sys.exit(0)
