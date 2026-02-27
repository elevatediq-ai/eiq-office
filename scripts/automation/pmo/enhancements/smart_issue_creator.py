#!/usr/bin/env python3
"""🚀 ElevatedIQ: Smart Issue Auto-Creation (Enhancement 1)
Purpose: Scans project docs (MD, ADRs, Strategy) and creates GitHub issues for detected action items.
NIST: [NIST-PM-5] Standardized Project Management Enforcement.
"""

import json
import os
import re
import subprocess
import sys
from datetime import datetime

# ============================================================================
# CONFIGURATION
# ============================================================================
REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../../../"))
UIE_SCRIPT = os.path.join(REPO_ROOT, "scripts/pmo/uie.sh")
NIST_MAP_FILE = os.path.join(REPO_ROOT, "docs/management/NIST_800_53_MAP.json")

# Action Item Patterns
CHKLST_PATTERN = re.compile(r"^\s*-\s*\[\s*\]\s+(.*)$", re.MULTILINE)
TABLE_ROW_PATTERN = re.compile(
    r"^\s*\|\s*([^|]+)\s*\|\s*([^|]+)\s*\|\s*([^|]*)\s*\|\s*([^|]*)\s*\|\s*([^|]*)\s*\|",
    re.MULTILINE,
)

# Keywords for Metadata Detection
PRIORITY_MAP = {
    "P0": "p0",
    "P1": "p1",
    "P2": "p2",
    "CRITICAL": "p0",
    "URGENT": "p0",
    "IMPORTANT": "p1",
    "NORMAL": "p2",
    "LOW": "p2",
}

TYPE_MAP = {
    "feat": "feat",
    "feature": "feat",
    "enhancement": "feat",
    "bug": "bug",
    "fix": "bug",
    "error": "bug",
    "task": "task",
    "chore": "task",
    "refactor": "task",
    "security": "security",
    "infra": "infra",
    "docs": "docs",
}

# ============================================================================
# UTILITIES
# ============================================================================


def log(level: str, message: str):
    """Log function."""
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{timestamp}] [{level}] {message}")


def run_command(cmd: list[str]) -> tuple[int, str]:
    """run_command function."""
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=False)
        return result.returncode, result.stdout.strip()
    except Exception as e:
        return 1, str(e)


# ============================================================================
# PARSERS
# ============================================================================


class DocumentScanner:
    """DocumentScanner class."""

    def __init__(self, file_path: str):
        self.file_path = file_path
        self.content = self._read_file()
        self.file_name = os.path.basename(file_path)

    def _read_file(self) -> str:
        try:
            with open(self.file_path, encoding="utf-8") as f:
                return f.read()
        except Exception as e:
            log("ERROR", f"Failed to read {self.file_path}: {e}")
            return ""

    def scan_checklists(self) -> list[dict]:
        """Finds unchecked items: - [ ] Task name."""
        items = []
        for match in CHKLST_PATTERN.finditer(self.content):
            items.append(
                {
                    "title": match.group(1).strip(),
                    "source": self.file_name,
                    "context": "checklist",
                    "original_text": match.group(0),
                }
            )
        return items

    def scan_table_enhancements(self) -> list[dict]:
        """Finds rows in enhancement matrices like: | 1 | Title | #ID | 1 | Status |."""
        items = []
        for match in TABLE_ROW_PATTERN.finditer(self.content):
            id_val, title, issue_ref, phase, status = match.groups()
            title = title.strip()
            issue_ref = issue_ref.strip()

            # Skip header rows
            if title.lower() == "enhancement" or "--" in title:
                continue

            # If issue_ref is empty, or just '#', it's a candidate for creation
            if not issue_ref or issue_ref == "#":
                items.append(
                    {
                        "title": title,
                        "id": id_val.strip(),
                        "phase": phase.strip(),
                        "issue_ref": issue_ref,
                        "source": self.file_name,
                        "context": "table_matrix",
                    }
                )
        return items


# ============================================================================
# ENRICHMENT
# ============================================================================


class MetadataEnricher:
    """MetadataEnricher class."""

    def __init__(self):
        self.nist_map = self._load_nist_map()

    def _load_nist_map(self) -> dict:
        if os.path.exists(NIST_MAP_FILE):
            try:
                with open(NIST_MAP_FILE) as f:
                    return json.load(f)
            except Exception:
                pass
        return {}

    def get_metadata(self, title: str) -> dict:
        """get_metadata method."""
        meta = {"type": "task", "priority": "p2", "nist_controls": []}

        title_lower = title.lower()

        # Priority detection
        for key, val in PRIORITY_MAP.items():
            if key.lower() in title_lower:
                meta["priority"] = val
                break

        # Type detection
        for key, val in TYPE_MAP.items():
            if key.lower() in title_lower:
                meta["type"] = val
                break

        # NIST Mapping (Basic keyword matching)
        if "security" in title_lower or "auth" in title_lower:
            meta["nist_controls"].append("AC-2")
        if "audit" in title_lower or "log" in title_lower:
            meta["nist_controls"].append("AU-2")
        if "monitor" in title_lower:
            meta["nist_controls"].append("SI-4")

        # If a NIST mapping file is present, use it for richer keyword→control mapping
        for kw, controls in self.nist_map.items():
            try:
                if kw.lower() in title_lower:
                    for c in controls:
                        if c not in meta["nist_controls"]:
                            meta["nist_controls"].append(c)
            except Exception:
                # defensive: ignore malformed entries
                continue

        return meta


# ============================================================================
# CORE LOGIC
# ============================================================================


def create_issue(item: dict, dry_run: bool = False):
    """create_issue function."""
    enricher = MetadataEnricher()
    meta = enricher.get_metadata(item["title"])

    title = f"[{meta['type'].upper()}] {item['title']}"
    body = f"""## Objective
{item["title"]}

## Source Context
- **File**: [{item["source"]}]({item["source"]})
- **Detected via**: {item["context"]}
- **Auto-created**: {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}

## FedRAMP Compliance (NIST 800-53)
{", ".join(meta["nist_controls"]) if meta["nist_controls"] else "N/A - Standard Task"}

---
_Auto-generated by ElevatedIQ Smart Issue Creator_
"""

    labels = f"{meta['type']},priority-{meta['priority']},auto-created"

    if dry_run:
        log("DRY-RUN", f"Would create issue: {title}")
        log("DRY-RUN", f"Labels: {labels}")
        return None

    # Call uie.sh
    cmd = [
        "bash",
        UIE_SCRIPT,
        "--title",
        title,
        "--body",
        body,
        "--type",
        meta["type"],
        "--priority",
        meta["priority"],
        "--labels",
        labels,
    ]

    log("INFO", f"Creating issue for: {item['title']}")
    rc, output = run_command(cmd)

    if rc == 0:
        # Try to extract issue URL or number from output
        # uie.sh prints something like "Created Issue #123: https://..."
        match = re.search(r"Issue #(\d+)", output)
        if match:
            issue_num = match.group(1)
            log("SUCCESS", f"Created issue #{issue_num}")
            return issue_num
    else:
        log("ERROR", f"Failed to create issue: {output}")
        return None


# ============================================================================
# MAIN
# ============================================================================


def main():
    """Main function."""
    import argparse

    parser = argparse.ArgumentParser(description="ElevatedIQ Smart Issue Creator")
    parser.add_argument("file", help="Document to scan")
    parser.add_argument("--dry-run", action="store_true", help="Don't actually create issues")
    parser.add_argument("--checklists", action="store_true", help="Scan checklists")
    parser.add_argument("--tables", action="store_true", help="Scan enhancement tables")
    args = parser.parse_args()

    if not os.path.exists(args.file):
        log("ERROR", f"File not found: {args.file}")
        sys.exit(1)

    scanner = DocumentScanner(args.file)
    items = []

    if args.checklists:
        items.extend(scanner.scan_checklists())
    if args.tables:
        items.extend(scanner.scan_table_enhancements())

    if not items:
        log("INFO", "No action items detected.")
        return

    log("INFO", f"Detected {len(items)} items in {args.file}")

    for item in items:
        issue_num = create_issue(item, dry_run=args.dry_run)
        if issue_num and not args.dry_run:
            # Optionally update the document with the new issue number
            # Future enhancement: automated MD updating
            pass


if __name__ == "__main__":
    main()
