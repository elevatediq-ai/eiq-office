#!/usr/bin/env python3
"""Validate `--hash=` tokens in generated requirements*.txt files.

- Flags malformed/truncated `--hash=` tokens (e.g. `--hash=sha25`)
- Ensures `--hash` follows format: <algo>:<hex>

Exit code: 0 = ok, 1 = problems found
"""

import re
import sys
from pathlib import Path

REQ_GLOB = ["**/requirements*.txt"]
HASH_RE = re.compile(r"--hash=([a-z0-9]+):([0-9a-fA-F]+)$")

errors = []

for pattern in REQ_GLOB:
    for p in Path.cwd().glob(pattern):
        try:
            text = p.read_text()
        except Exception as e:
            errors.append(f"ERROR: failed to read {p}: {e}")
            continue

        for lineno, line in enumerate(text.splitlines(), start=1):
            if "--hash=" in line:
                token = line.strip()
                # quick reject for obviously truncated tokens
                if "--hash=sha25" in token or token.endswith("--hash=") or (":" not in token):
                    errors.append(f"Malformed --hash token in {p}:{lineno}: {token}")
                    continue

                m = HASH_RE.search(token)
                if not m:
                    errors.append(f"Invalid --hash format in {p}:{lineno}: {token}")

if errors:
    print("❌ requirements-hash-validation: detected malformed/invalid --hash tokens")
    for e in errors:
        print(e)
    print("\nFix: regenerate the requirements with 'pip-compile --generate-hashes' or correct the broken token.")
    sys.exit(1)

print("✅ requirements-hash-validation: all requirements files look good")
sys.exit(0)
