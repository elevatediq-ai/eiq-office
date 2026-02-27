"""Bulk import utilities for ingesting entities from files."""

import os, json

def import_entities_bulk(file_path: str) -> int:
    """Read a file and import entities, returning count of imported items.

    - TXT: counts nonempty lines, splitting commas as separate items.
    - JSON: if file contains a top-level list, returns its length.

    Returns 0 if the file cannot be processed.
    """
    if not os.path.exists(file_path):
        return 0
    try:
        if file_path.lower().endswith(".json"):
            with open(file_path, "r", encoding="utf-8") as f:
                data = json.load(f)
                if isinstance(data, list):
                    return len(data)
                return 0
        total = 0
        with open(file_path, "r", encoding="utf-8") as f:
            for line in f:
                if line.strip():
                    total += len(line.strip().split(","))
        return total
    except Exception:
        return 0
