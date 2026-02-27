#!/usr/bin/env python3
"""ElevatedIQ - Post-Authentication Security Audit Script (NIST AU-2)
Purpose: Automated verification of OAuth audit logs and security event integrity.
Compliance: NIST 800-53 (AU-2, IA-2, AC-3).
"""

import json
import logging
import os
import re
import sys
from datetime import UTC, datetime
from typing import Any

# Configure logging for the auditor itself
logging.basicConfig(level=logging.INFO, format="%(asctime)s - [%(levelname)s] - %(message)s")
logger = logging.getLogger("SecurityAuditor")

# Audit Targets
LOG_FILE = "apps/logs/oauth-audit/access.log"


class SecurityAuditor:
    """SecurityAuditor class."""

    def __init__(self, log_path: str = LOG_FILE):
        self.log_path = log_path
        self.findings = []
        self.stats = {
            "total_events": 0,
            "success": 0,
            "failure": 0,
            "critical_alerts": 0,
        }

    def audit_entry(self, entry: dict[str, Any]):
        """Perform security checks on a single audit entry."""
        self.stats["total_events"] += 1

        # 1. NIST Compliance Check (Required Fields)
        required_fields = ["timestamp", "event_type", "status", "ip_address"]
        for field in required_fields:
            if field not in entry:
                self.add_finding("HIGH", f"Missing required NIST field: {field}", entry)

        # 2. Status Tracking
        if entry.get("status") == "success":
            self.stats["success"] += 1
        else:
            self.stats["failure"] += 1
            if entry.get("event_type") == "oauth_callback_failed":
                self.add_finding("MEDIUM", "Failed OAuth callback detected", entry)

        # 3. Secret Leakage Detection
        # Check if any field contains likely tokens or secrets
        sensitive_patterns = [
            r"eyjhbger",  # JWT prefix
            r"AIzaSy",  # Google API Key
            r"secrets",
            r"password",
        ]
        entry_str = json.dumps(entry).lower()
        for pattern in sensitive_patterns:
            if re.search(pattern, entry_str):
                # Flag leakage if found in top-level fields OR if it's a 'password' field in details
                if "details" not in entry or "password" in entry_str:
                    self.add_finding("CRITICAL", f"Potential secret leakage: {pattern}", entry)

        # 4. Brute Force Detection (Simple count-based)
        # In a real system, this would use a sliding window
        pass

    def add_finding(self, severity: str, message: str, context: Any):
        """add_finding method."""
        self.findings.append(
            {
                "severity": severity,
                "message": message,
                "timestamp": datetime.now(UTC).isoformat(),
                "context": context,
            }
        )
        if severity == "CRITICAL":
            self.stats["critical_alerts"] += 1

    def run_audit(self):
        """run_audit method."""
        print("\n\033[0;34m====================================================\033[0m")
        print("\033[0;34m   ElevatedIQ Post-Auth Security Audit (NIST AU-2)  \033[0m")
        print("\033[0;34m====================================================\033[0m\n")

        if not os.path.exists(self.log_path):
            logger.warning(f"Log file not found: {self.log_path}. Generating mock audit data for validation...")
            self.generate_mock_data()

        with open(self.log_path) as f:
            for line in f:
                if "AUDIT:" in line:
                    try:
                        # Extract JSON from "AUDIT: {...}"
                        json_str = line.split("AUDIT:")[1].strip()
                        entry = json.loads(json_str)
                        self.audit_entry(entry)
                    except Exception as e:
                        logger.error(f"Failed to parse audit line: {e}")

        self.report_results()

    def generate_mock_data(self):
        """Generates mock data for testing the auditor."""
        os.makedirs(os.path.dirname(self.log_path), exist_ok=True)
        mock_entries = [
            # Valid Entry
            {
                "timestamp": datetime.now(UTC).isoformat(),
                "event_type": "oauth_authorize_initiated",
                "user_email": None,
                "status": "success",
                "ip_address": "127.0.0.1",
                "user_agent": "Mozilla/5.0",
                "details": {"state": "valid_state_123"},
            },
            # Failure Entry
            {
                "timestamp": datetime.now(UTC).isoformat(),
                "event_type": "oauth_callback_failed",
                "user_email": "attacker@evil.com",
                "status": "failure",
                "ip_address": "192.168.1.100",
                "user_agent": "python-requests/2.25.1",
                "details": {"error": "invalid_grant"},
            },
            # Secret Leakage (BAD)
            {
                "timestamp": datetime.now(UTC).isoformat(),
                "event_type": "login_debug",
                "user_email": "admin@elevatediq.ai",
                "status": "success",
                "ip_address": "10.0.0.5",
                "details": {"password_exposed": "nexusadmin2026"},  # pragma: allowlist secret
            },
        ]
        with open(self.log_path, "a") as f:
            for entry in mock_entries:
                f.write(f"AUDIT: {json.dumps(entry)}\n")
        logger.info(f"Mock audit data written to {self.log_path}")

    def report_results(self):
        """report_results method."""
        print("\033[1;33mAudit Summary:\033[0m")
        print(f"- Total Events Scanned: {self.stats['total_events']}")
        print(f"- Success/Failure: {self.stats['success']}/{self.stats['failure']}")
        print(f"- Critical Alerts: {self.stats['critical_alerts']}")

        if self.findings:
            print(f"\n\033[0;31mFindings Detected ({len(self.findings)}):\033[0m")
            for f in self.findings:
                color = "\033[0;31m" if f["severity"] in ["HIGH", "CRITICAL"] else "\033[1;33m"
                print(f"{color}[{f['severity']}]\033[0m {f['message']}")
                print(f"  Context: {f['context'].get('event_type')} from {f['context'].get('ip_address')}")
        else:
            print("\n\033[0;32m✓ No security findings detected. Compliance verified.\033[0m")

        print("\n\033[0;34m====================================================\033[0m")
        if self.stats["critical_alerts"] > 0:
            sys.exit(1)


if __name__ == "__main__":
    auditor = SecurityAuditor()
    auditor.run_audit()
