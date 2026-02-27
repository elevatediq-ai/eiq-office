#!/usr/bin/env python3
"""🛡️ Governance Policy Engine (GPE)
Part of ElevatedIQ 10X Governance Strategy
Handles the parsing and enforcement of POLICIES.gpl.
"""

import importlib.util
import json
import os
import re
import sys
from typing import Any

# Dynamic Loader for FAS
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))


def get_fas():
    """get_fas function."""
    try:
        module_name = "audit_stream"
        file_path = os.path.join(SCRIPT_DIR, "08_federal_audit_stream.py")
        spec = importlib.util.spec_from_file_location(module_name, file_path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module.FederalAuditStream()
    except Exception:
        return None


class PolicyEngine:
    """PolicyEngine class."""

    def __init__(self, policy_path: str = None):
        if policy_path is None:
            base_dir = os.path.dirname(os.path.abspath(__file__))
            root_dir = os.path.abspath(os.path.join(base_dir, "../../../"))
            policy_path = os.path.join(root_dir, "docs/governance/POLICIES.gpl")

        self.policy_path = policy_path
        self.policies = []
        self.fas = get_fas()
        self._load_policies()

    def _load_policies(self):
        if not os.path.exists(self.policy_path):
            return

        with open(self.policy_path) as f:
            content = f.read()

        policy_matches = re.finditer(r'policy "([^"]+)" \{', content)
        for p_match in policy_matches:
            name = p_match.group(1)
            start_pos = p_match.end()
            body, end_pos = self._extract_block(content, start_pos)

            policy = {
                "name": name,
                "selector": self._extract_field(body, "selector"),
                "severity": self._extract_field(body, "severity"),
                "nist_controls": self._extract_list(body, "nist_controls"),
                "rules": self._extract_rules_from_body(body),
            }
            self.policies.append(policy)

    def _extract_block(self, text: str, start_pos: int):
        brace_count = 1
        curr_pos = start_pos
        while brace_count > 0 and curr_pos < len(text):
            if text[curr_pos] == "{":
                brace_count += 1
            elif text[curr_pos] == "}":
                brace_count -= 1
            curr_pos += 1
        return text[start_pos : curr_pos - 1], curr_pos

    def _extract_field(self, body: str, key: str) -> str:
        pattern = rf'{key}\s*=\s*"([^"]+)"'
        match = re.search(pattern, body)
        return match.group(1).strip() if match else ""

    def _extract_list(self, body: str, key: str) -> list[str]:
        pattern = rf"{key}\s*=\s*\[([^\]]+)\]"
        match = re.search(pattern, body)
        if match:
            return [x.strip().strip('"') for x in match.group(1).split(",")]
        return []

    def _extract_rules_from_body(self, body: str) -> list[dict[str, str]]:
        rules = []
        rule_matches = re.finditer(r'rule "([^"]+)" \{', body)
        for r_match in rule_matches:
            name = r_match.group(1)
            start_pos = r_match.end()
            r_body, _ = self._extract_block(body, start_pos)

            rule = {
                "name": name,
                "pattern": self._extract_field(r_body, "pattern"),
                "on_failure": self._extract_field(r_body, "on_failure"),
                "message": self._extract_field(r_body, "message"),
            }
            rules.append(rule)
        return rules

    def validate_text(self, context: str, selector: str) -> list[dict[str, Any]]:
        """validate_text method."""
        violations = []
        for policy in self.policies:
            if policy["selector"] != selector:
                continue

            for rule in policy["rules"]:
                if not re.search(rule["pattern"], context):
                    violation = {
                        "policy": policy["name"],
                        "rule": rule["name"],
                        "severity": policy["severity"],
                        "nist_controls": policy["nist_controls"],
                        "action": rule["on_failure"],
                        "message": rule["message"],
                    }
                    violations.append(violation)

                    if self.fas:
                        self.fas.log_event(
                            event_type="POLICY_VIOLATION",
                            nist_controls=policy["nist_controls"],
                            severity=policy["severity"],
                            message=f"Rule '{rule['name']}' failed for context: {context[:50]}...",
                            meta={"selector": selector, "policy": policy["name"]},
                        )

        if not violations and self.fas:
            # Optionally log passes for AU audit
            pass

        return violations


def main():
    """Main function."""
    if len(sys.argv) < 3:
        print("Usage: 05_policy_engine.py <selector> <text>")
        sys.exit(1)

    selector = sys.argv[1]
    input_text = " ".join(sys.argv[2:])

    engine = PolicyEngine()
    violations = engine.validate_text(input_text, selector)

    if violations:
        print(f"❌ Found {len(violations)} violations for selector '{selector}':")
        print(json.dumps(violations, indent=2))
        sys.exit(1)
    else:
        print(f"✅ Context passes all policies for '{selector}'.")
        sys.exit(0)


if __name__ == "__main__":
    main()
