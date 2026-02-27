#!/usr/bin/env python3
"""Global Error Handler Injection Script
Automatically injects centralized error handling into all services.

Purpose: Deploy error_handler integration across 40+ services
NIST Alignment: AU-2 (Audit), IR-4 (Incident Response)
"""

import os
import sys

# Error handler injection template
ERROR_HANDLER_INJECTION = """
# Global error handling integration [NIST-AU-2, NIST-IR-4]
try:
    from libs.resilience.global_error_handler import get_global_handler, ErrorSeverity
    from libs.resilience.auto_recovery import attempt_auto_recovery
    error_handler = get_global_handler()
except (ImportError, ModuleNotFoundError):
    error_handler = None
"""


def find_insertion_point(content: str, filepath: str) -> tuple[int, str]:
    """Find the best place to insert error handler imports."""
    lines = content.split("\n")

    # Find the last import statement
    last_import_idx = -1
    for i, line in enumerate(lines):
        if line.startswith("import ") or line.startswith("from "):
            last_import_idx = i
        elif line.strip() and not line.startswith("#") and last_import_idx != -1:
            # Found first non-import, non-comment line after imports
            break

    if last_import_idx == -1:
        # No imports found, insert after docstring if present
        in_docstring = False
        for i, line in enumerate(lines):
            if '"""' in line or "'''" in line:
                if in_docstring:
                    return i + 1, "after docstring"
                in_docstring = True
        return 0, "at top"

    return last_import_idx + 1, "after imports"


def inject_error_handler(filepath: str) -> bool:
    """Inject error handler into a file."""
    try:
        with open(filepath) as f:
            content = f.read()

        # Skip if already has error handler
        if "error_handler" in content and "ErrorSeverity" in content:
            print(f"  ⊘ SKIP: {filepath} (already integrated)")
            return False

        insert_idx, location = find_insertion_point(content, filepath)
        lines = content.split("\n")

        # Insert the error handler code
        lines.insert(insert_idx, ERROR_HANDLER_INJECTION)

        new_content = "\n".join(lines)

        with open(filepath, "w") as f:
            f.write(new_content)

        print(f"  ✓ INJECT: {filepath} ({location})")
        return True

    except Exception as e:
        print(f"  ✗ ERROR: {filepath} - {str(e)}")
        return False


def find_service_files() -> list[str]:
    """Find all main.py service files."""
    services = []
    for root, dirs, files in os.walk("apps"):
        # Skip venv and site-packages
        dirs[:] = [d for d in dirs if d not in [".venv", "__pycache__", "dist", "build"]]

        if "main.py" in files:
            full_path = os.path.join(root, "main.py")
            # Avoid site-packages
            if "site-packages" not in full_path:
                services.append(full_path)

    return sorted(services)


def main():
    """Main injection workflow."""
    print("\n" + "=" * 70)
    print("🚀 GLOBAL ERROR HANDLER INJECTION - Phase B Deployment")
    print("=" * 70)

    services = find_service_files()
    print(f"\n📍 Found {len(services)} service entry points:\n")

    injected = 0
    skipped = 0

    for service in services:
        if inject_error_handler(service):
            injected += 1
        else:
            skipped += 1

    print("\n" + "=" * 70)
    print("✓ INJECTION COMPLETE")
    print(f"  • Services Updated: {injected}")
    print(f"  • Services Skipped: {skipped}")
    print(f"  • Total Processed: {len(services)}")
    print("=" * 70 + "\n")

    return injected > 0


if __name__ == "__main__":
    sys.exit(0 if main() else 1)
