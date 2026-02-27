#!/usr/bin/env python3
"""Batch-add # type: ignore[import-*] to lines flagged by mypy for import errors.
Runs mypy, parses output, patches files in-place.
"""

import re
import subprocess
from collections import defaultdict
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
TARGETS = [
    "libs/orchestration",
    "libs/ai_orchestrator",
    "libs/ai_governance",
    "libs/resilience",
    "libs/ml",
    "libs/messaging",
    "libs/queue",
    "libs/omni_governance",
    "libs/predictive_ops",
    "libs/governance",
]

IMPORT_ERRORS = {"import-not-found", "import-untyped"}


def run_mypy() -> str:
    """run_mypy function."""
    result = subprocess.run(
        [str(REPO / ".venv/bin/mypy")] + TARGETS,
        cwd=str(REPO),
        capture_output=True,
        text=True,
    )
    return result.stdout + result.stderr


def parse_import_errors(output: str) -> dict[str, list[int]]:
    """Return {filepath: [line_numbers]} for import errors only."""
    pattern = re.compile(r"^(libs/[^:]+):(\d+): error: .+\[(import-(?:not-found|untyped))\]")
    file_lines: dict[str, list[int]] = defaultdict(list)
    for line in output.splitlines():
        m = pattern.match(line)
        if m:
            filepath, lineno, _code = m.group(1), int(m.group(2)), m.group(3)
            file_lines[filepath].append(lineno)
    return dict(file_lines)


def patch_file(filepath: str, line_numbers: list[int]) -> int:
    """Add # type: ignore[import-untyped,import-not-found] to specified lines. Returns count patched."""
    full_path = REPO / filepath
    if not full_path.exists():
        print(f"  SKIP (not found): {filepath}")
        return 0

    lines = full_path.read_text(encoding="utf-8").splitlines(keepends=True)
    patched = 0
    for lineno in sorted(set(line_numbers)):
        idx = lineno - 1
        if idx >= len(lines):
            continue
        line = lines[idx]
        stripped = line.rstrip("\n").rstrip("\r")

        # Skip if already has type: ignore
        if "# type: ignore" in stripped:
            continue

        # Add ignore comment
        lines[idx] = stripped + "  # type: ignore[import-untyped,import-not-found]\n"
        patched += 1

    if patched:
        full_path.write_text("".join(lines), encoding="utf-8")
        print(f"  Patched {patched} lines in {filepath}")

    return patched


def main() -> None:
    """Main function."""
    print("Running mypy to detect import errors...")
    output = run_mypy()

    file_lines = parse_import_errors(output)
    if not file_lines:
        print("No import errors found!")
        return

    total = sum(len(v) for v in file_lines.values())
    print(f"Found {len(file_lines)} files with {total} import error lines to patch.")

    total_patched = 0
    for filepath, lines in sorted(file_lines.items()):
        total_patched += patch_file(filepath, lines)

    print(f"\nDone. Patched {total_patched} lines across {len(file_lines)} files.")


if __name__ == "__main__":
    main()
