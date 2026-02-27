#!/usr/bin/env python3
"""Grafana Dashboard Registry Sync - Phase 9.3
NIST-CA-7: Continuous Monitoring & SI-4: Information System Monitoring
This script synchronizes local JSON dashboard definitions with a central registry
to ensure all Phase 9.3 intelligence dashboards are properly tracked and provisioned.
"""

import argparse
import json
import logging
import os
from datetime import UTC, datetime
from typing import Any

# Configure logging
logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger("GrafanaSync")

DEFAULT_DASHBOARD_DIR = "config/grafana/dashboards"
DEFAULT_REGISTRY_FILE = "config/grafana/dashboards/registry.json"


def get_dashboard_metadata(file_path: str) -> dict[str, Any]:
    """Extract metadata from dashboard JSON file."""
    try:
        with open(file_path) as f:
            data = json.load(f)
            return {
                "uid": data.get("uid", "unknown"),
                "title": data.get("title", "Untitled"),
                "version": data.get("version", 1),
                "tags": data.get("tags", []),
                "last_modified": datetime.fromtimestamp(os.path.getmtime(file_path), tz=UTC).isoformat(),
            }
    except Exception as e:
        logger.error(f"Error reading {file_path}: {e}")
        return {}


def sync_registry(dashboard_dir: str, registry_file: str, dry_run: bool = False):
    """Sync the registry file with dashboards in the directory."""
    logger.info(f"Syncing Grafana dashboards from {dashboard_dir} to {registry_file}")

    if not os.path.exists(dashboard_dir):
        logger.error(f"Dashboard directory {dashboard_dir} does not exist.")
        return

    dashboards = []
    for filename in os.listdir(dashboard_dir):
        if filename.endswith(".json") and filename != "registry.json":
            file_path = os.path.join(dashboard_dir, filename)
            meta = get_dashboard_metadata(file_path)
            if meta:
                meta["file_path"] = f"{dashboard_dir}/{filename}"
                dashboards.append(meta)

    registry_data = {
        "sync_timestamp": datetime.now(UTC).isoformat(),
        "total_dashboards": len(dashboards),
        "dashboards": dashboards,
        "phase": "9.3",
        "nist_alignment": ["CA-7", "SI-4"],
    }

    if dry_run:
        logger.info("Dry run: Registry would be updated with following data:")
        logger.info(json.dumps(registry_data, indent=2))
    else:
        os.makedirs(os.path.dirname(registry_file), exist_ok=True)
        with open(registry_file, "w") as f:
            json.dump(registry_data, f, indent=2)
        logger.info(f"✅ Registry successfully updated with {len(dashboards)} dashboards.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Sync Grafana Dashboard Registry")
    parser.add_argument("--dir", default=DEFAULT_DASHBOARD_DIR, help="Dashboard directory")
    parser.add_argument("--registry", default=DEFAULT_REGISTRY_FILE, help="Registry file path")
    parser.add_argument("--dry-run", action="store_true", help="Dry run without writing")

    args = parser.parse_args()

    # Resolve paths relative to repo root if needed
    # (Assuming script is run from repo root)
    sync_registry(args.dir, args.registry, args.dry_run)
