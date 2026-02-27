#!/usr/bin/env python3
"""Batch Spoke Provisioning Script
Usage: ./scripts/pmo/batch_provision.py --count 50 --env production --archetype compute
Compliance: NIST-CM-3 (Configuration Change Management).
"""

import argparse
import os
import sys

# Add apps/agent-cicd/pipelines to path to import orchestrator
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "../../apps/agent-cicd/pipelines")))

from spoke_orchestrator import SpokeOrchestrator


def main():
    """Main function."""
    parser = argparse.ArgumentParser(description="Batch provision Managed Spokes for ElevatedIQ.")
    parser.add_argument("--count", type=int, default=10, help="Number of spokes to provision")
    parser.add_argument("--env", type=str, default="dev", help="Target environment")
    parser.add_argument(
        "--archetype",
        type=str,
        default="compute",
        choices=["compute", "data", "ml", "gateway"],
    )
    parser.add_argument("--prefix", type=str, default="spoke", help="Prefix for spoke IDs")
    parser.add_argument(
        "--security-tier",
        type=str,
        default="standard",
        choices=["standard", "high", "critical"],
        help="Security profile tier",
    )

    args = parser.parse_args()

    repo_root = os.getcwd()
    orchestrator = SpokeOrchestrator(repo_root)

    print(f"🚀 Starting batch provisioning of {args.count} {args.archetype} spokes in {args.env}...")

    for i in range(1, args.count + 1):
        spoke_id = f"{args.prefix}-{args.archetype}-{i:03d}"
        print(f"  [+] Processing {spoke_id}...")

        # In a real batch, we allocate unique CIDRs sequentially
        orchestrator.generate_tfvars(
            spoke_id=spoke_id,
            archetype=args.archetype,
            env=args.env,
            spoke_index=i,
            security_tier=args.security_tier,
        )

        orchestrator.trigger_deployment(spoke_id, args.env)

    print(f"\n✅ Batch configuration complete. Diffs generated in configs/{args.env}/spokes/")
    print("Next step: Run 'gh pr create' to review and deploy the new infrastructure.")


if __name__ == "__main__":
    main()
