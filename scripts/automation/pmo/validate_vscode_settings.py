#!/usr/bin/env python3
import json
import os
import sys

# ElevatedIQ Mono-Repo Config Validation
# Issue #2024: [10X-2] Config Schema Validation


def validate_settings():
    """validate_settings function."""
    settings_path = ".vscode/settings.json"
    if not os.path.exists(settings_path):
        return True

    print(f"🔍 Validating {settings_path} against performance policy...")

    with open(settings_path) as f:
        # Handle jsonc (comments)
        lines = f.readlines()
        content = "".join([line for line in lines if not line.strip().startswith("//")])
        try:
            settings = json.loads(content)
        except json.JSONDecodeError as e:
            # Try simple replacement for common jsonc patterns if it still fails
            print(f"❌ Failed to parse {settings_path}: {e}")
            return False

    errors = []

    # Policy 1: No indexing in large repos
    if settings.get("python.analysis.indexing") is True:
        errors.append("POLICY VIOLATION: 'python.analysis.indexing' must be set to 'false' for repos > 1GB.")

    # Policy 2: No 'heavy' type checking
    if settings.get("python.analysis.typeCheckingMode") == "heavy":
        errors.append("POLICY VIOLATION: 'python.analysis.typeCheckingMode' must be 'off' or 'basic' for performance.")

    if errors:
        print("\n🚨 VS CODE CONFIGURATION FAILURES:")
        for error in errors:
            print(f"  - {error}")
        return False

    print("✅ VS Code settings comply with mono-repo performance standards.")
    return True


if __name__ == "__main__":
    if not validate_settings():
        sys.exit(1)
    sys.exit(0)
