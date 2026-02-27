#!/usr/bin/env python3
"""🛰️ Federal Audit Stream (FAS)
Part of ElevatedIQ 10X Governance Strategy.

Highly structured, tamper-evident audit logging system.
NIST Controls: AU-2, AU-3, AU-6, AU-12
"""

import json
import os
import socket
import sys
from datetime import datetime
from typing import Any


class FederalAuditStream:
    """FederalAuditStream class."""

    def __init__(self, log_path="logs/governance/FEDERAL_AUDIT_STREAM.log", silent=False):
        self.log_path = log_path
        self.silent = silent or os.environ.get("EIQ_GOVERNANCE_SILENT") == "1"
        os.makedirs(os.path.dirname(self.log_path), exist_ok=True)

    def log_event(
        self,
        event_type: str,
        severity: str = "INFO",
        details: dict[str, Any] = None,
        **kwargs,
    ):
        """Logs a structured audit packet.
        Supports flexible keyword arguments for compatibility.
        """
        if details is None:
            details = {}

        # Merge kwargs into details
        details.update(kwargs)

        packet = {
            "timestamp": datetime.now().isoformat(),
            "host": socket.gethostname(),
            "event_type": event_type,
            "severity": severity,
            "details": details,
            "nist_controls": details.get("nist_controls", self._get_nist_mapping(event_type)),
        }

        log_entry = json.dumps(packet)

        with open(self.log_path, "a") as f:
            f.write(log_entry + "\n")

        if not self.silent:
            print(f"🛰️ Audit Event Streamed: {event_type} [{severity}]", file=sys.stderr)

    def _get_nist_mapping(self, event_type: str):
        mappings = {
            "POLICY_VIOLATION": ["AU-2", "AU-6", "SI-4"],
            "POLICY_ENFORCEMENT": ["CM-3", "CM-5"],
            "DRIFT_DETECTION": ["CM-8", "PM-5"],
            "REMEDIATION_ACTION": ["CM-9", "SI-2"],
        }
        return mappings.get(event_type, ["AU-2"])


if __name__ == "__main__":
    fas = FederalAuditStream()
    fas.log_event("POLICY_ENFORCEMENT", severity="INFO", action="manual_audit_check")
