#!/usr/bin/env python3
"""🌐 Federated Governance API (V2)
Part of ElevatedIQ 10X Governance Strategy.

Exposes unified governance metrics across:
Debt, Prediction, Scorecard, and Cross-System Correlation.
"""

import json
import os
import subprocess
import sys
from datetime import datetime


def get_full_governance_state():
    """get_full_governance_state function."""
    results = {
        "timestamp": datetime.now().isoformat(),
        "status": "OPERATIONAL",
        "components": {},
    }

    scripts = {
        "debt_tracker": "scripts/pmo/enhancements/07_compliance_debt_tracker.py",
        "predictive_engine": "scripts/pmo/enhancements/01_predictive_engine.py",
        "scorecard": "scripts/pmo/enhancements/06_compliance_scorecard.py",
        "correlation_engine": "scripts/pmo/enhancements/02_cross_system_correlation.py",
        "developer_profiles": "scripts/pmo/enhancements/08_developer_profiles.py",
    }

    # Force silent mode for audit stream
    os.environ["EIQ_GOVERNANCE_SILENT"] = "1"

    for key, path in scripts.items():
        try:
            full_path = os.path.join(os.getcwd(), path)
            if os.path.exists(full_path):
                # Only capture stdout, ignore stderr to keep JSON clean
                out = subprocess.check_output([sys.executable, full_path], stderr=subprocess.DEVNULL)
                results["components"][key] = json.loads(out)
            else:
                results["components"][key] = {"status": "MISSING", "path": path}
        except Exception as e:
            results["components"][key] = {"status": "ERROR", "message": str(e)}
            results["status"] = "PARTIAL_FAILURE"

    return results


if __name__ == "__main__":
    print(json.dumps(get_full_governance_state(), indent=2))
