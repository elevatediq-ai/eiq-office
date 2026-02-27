#!/usr/bin/env python3
"""ElevatedIQ - GCP OAuth 2.0 Credential Validator & Setup Assistant
NIST Aligned Implementation (IA-2, AC-2, AU-2).

This script automates the validation of Google OAuth 2.0 credentials
and provides a structured checklist for GCP configuration.
"""

import logging
import os
import re
import sys

# Configure logging
logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s")
logger = logging.getLogger(__name__)

# ANSI Colors
GREEN = "\033[0;32m"
RED = "\033[0;31m"
YELLOW = "\033[1;33m"
BLUE = "\033[0;34m"
NC = "\033[0m"


class GCPValidator:
    """GCPValidator class."""

    def __init__(self, env_path: str = "config/.env"):
        self.env_path = env_path
        self.required_vars = [
            "GOOGLE_OAUTH_CLIENT_ID",
            "GOOGLE_OAUTH_CLIENT_SECRET",
            "GOOGLE_OAUTH_REDIRECT_URI",
            "ALLOWED_ADMIN_EMAILS",
        ]
        self.config = {}

    def load_env(self) -> bool:
        """Load variables from .env file into configuration dictionary."""
        abs_path = os.path.abspath(self.env_path)
        if not os.path.exists(abs_path):
            logger.error(f"Environment file not found at: {abs_path}")
            return False

        with open(abs_path) as f:
            for _line in f:
                line = _line.strip()
                if line and not line.startswith("#"):
                    key, *value = line.split("=", 1)
                    if value:
                        self.config[key] = value[0].strip('"').strip("'")
        return True

    def validate_variable(self, key: str, value: str) -> tuple[bool, str]:
        """Validate specific logic for each variable."""
        if not value or value.startswith("your-") or value == "your_token_here":
            return False, f"{key} is missing or uses a placeholder value."

        if key == "GOOGLE_OAUTH_CLIENT_ID":
            if not value.endswith(".apps.googleusercontent.com"):
                return (
                    False,
                    f"{key} format is invalid. Must end with '.apps.googleusercontent.com'.",
                )

        if key == "GOOGLE_OAUTH_REDIRECT_URI":
            if not value.startswith("http"):
                return False, f"{key} must be a valid URL starting with http/https."
            if "localhost" in value and not value.startswith("http://"):
                return False, f"{key} should use http:// for localhost development."

        if key == "ALLOWED_ADMIN_EMAILS":
            emails = [e.strip() for e in value.split(",")]
            for email in emails:
                if not re.match(r"[^@]+@[^@]+\.[^@]+", email):
                    return (
                        False,
                        f"Invalid email format in ALLOWED_ADMIN_EMAILS: {email}",
                    )

        return True, f"{key} is valid."

    def run(self):
        """Run method."""
        print(f"{BLUE}===================================================={NC}")
        print(f"{BLUE}   ElevatedIQ GCP OAuth 2.0 Validator (Phase 4)     {NC}")
        print(f"{BLUE}===================================================={NC}\n")

        if not self.load_env():
            print(f"{RED}FAILED:{NC} Please ensure {self.env_path} exists.")
            sys.exit(1)

        all_passed = True
        print(f"{YELLOW}Checking credentials in {self.env_path}...{NC}")

        for var in self.required_vars:
            val = self.config.get(var)
            passed, msg = self.validate_variable(var, val)
            if passed:
                print(f"{GREEN}[PASS]{NC} {msg}")
            else:
                print(f"{RED}[FAIL]{NC} {msg}")
                all_passed = False

        print(f"\n{BLUE}===================================================={NC}")
        if all_passed:
            print(f"{GREEN}SUCCESS:{NC} All OAuth configuration variables are valid.")
            print(f"{YELLOW}Next Step:{NC} Run the E2E integration tests in Phase 4.2.")
        else:
            print(f"{RED}ACTION REQUIRED:{NC} Please fix the issues above in your .env file.")
            self.print_gcp_guide()
            sys.exit(1)

    def print_gcp_guide(self):
        """print_gcp_guide method."""
        print(f"\n{YELLOW}GCP Setup Guide Checklist:{NC}")
        print("1. Go to GCP Console: https://console.cloud.google.com")
        print("2. Navigate to 'APIs & Services' > 'Credentials'")
        print("3. Click 'Create Credentials' > 'OAuth client ID'")
        print("4. Select Application type: 'Web application'")
        print("5. Add Authorized Redirect URI:")
        print("   -> http://localhost:8000/api/v1/auth/google/callback")
        print("6. Copy Client ID & Secret to config/.env")


if __name__ == "__main__":
    validator = GCPValidator()
    validator.run()
