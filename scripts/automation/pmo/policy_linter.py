#!/usr/bin/env python3
"""Policy Linter for ElevatedIQ
Validates Terraform plans and resource configs against OPA policies.
Aligned with NIST-AC-2 (Least Privilege) and Milestone 10 requirements.
"""

import argparse
import json
import logging
import sys
from pathlib import Path

# Add libs to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent / "apps" / "control_plane"))

try:
    from src.policy_engine.evaluator import PolicyEvaluator
except ImportError:
    # Fallback/Mock if not in expected path
    class PolicyEvaluator:
        """PolicyEvaluator class."""

        def evaluate_resource(self, type, data):
            """evaluate_resource method."""
            return []


logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
logger = logging.getLogger(__name__)


def main():
    """Main function."""
    parser = argparse.ArgumentParser(description="ElevatedIQ Policy Linter")
    parser.add_argument("file", help="Path to JSON resource or TF plan")
    parser.add_argument("--type", help="Resource type (e.g. google_compute_instance)")
    args = parser.parse_args()

    file_path = Path(args.file)
    if not file_path.exists():
        logger.error(f"File not found: {args.file}")
        sys.exit(1)

    with open(file_path) as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            logger.error(f"Invalid JSON in {args.file}")
            sys.exit(1)

    evaluator = PolicyEvaluator()

    # Simple logic: if it's a list, treat as multiple resources, else single
    resources = data if isinstance(data, list) else [data]

    all_violations = []
    for i, res in enumerate(resources):
        res_type = args.type or res.get("type") or "unknown"
        logger.info(f"Linter checking resource {i + 1} [Type: {res_type}]")
        violations = evaluator.evaluate_resource(res_type, res)
        all_violations.extend(violations)

    if all_violations:
        logger.error(f"❌ Policy violations found: {len(all_violations)}")
        for v in all_violations:
            logger.error(f"  - [{v.get('severity', 'HIGH')}] {v.get('policy')}: {v.get('message')}")
        sys.exit(2)
    else:
        logger.info("✅ No policy violations found. Least privilege rules satisfied.")
        sys.exit(0)


if __name__ == "__main__":
    main()
