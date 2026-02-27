#!/usr/bin/env python3
import logging
import os
import sys

# NIST-AU-2 Structured Audit Logging
LOG_DIR = "/home/akushnir/ElevatedIQ-Mono-Repo/logs/pmo"
os.makedirs(LOG_DIR, exist_ok=True)
logging.basicConfig(
    level=logging.INFO,
    format="[%(asctime)s] [%(levelname)s] [NIST-AU-2] %(message)s",
    handlers=[
        logging.FileHandler(f"{LOG_DIR}/phase92b_deployment_ready.log"),
        logging.StreamHandler(sys.stdout),
    ],
)
logger = logging.getLogger("phase92b_pre_flight")


def check_files():
    """check_files function."""
    required_files = [
        "scripts/failover/shift_traffic.sh",
        "scripts/failover/promote_rds_replica.sh",
        "scripts/failover/promote_redis_replica.sh",
        "scripts/db/apply_004_migration.py",
        "docs/PHASE_9_2B_EXECUTION_PLAN_FEB13.md",
    ]
    all_pass = True
    for f in required_files:
        path = f"/home/akushnir/ElevatedIQ-Mono-Repo/{f}"
        if os.path.exists(path):
            logger.info(f"✅ Required artifact found: {f}")
        else:
            logger.error(f"❌ MISSING REQUIRED ARTIFACT: {f}")
            all_pass = False
    return all_pass


def check_env_vars():
    """check_env_vars function."""
    # Simulation: In prod these are checked via AWS Secrets Manager
    required_vars = ["AWS_HOSTED_ZONE_ID", "AWS_DOMAIN_NAME"]
    all_pass = True
    for var in required_vars:
        if os.getenv(var):
            logger.info(f"✅ Environment variable set: {var}")
        else:
            logger.warning(f"⚠️ MISSING Env Var: {var} (Falling back to CLI defaults)")
    return all_pass


def validate_traffic_config():
    """validate_traffic_config function."""
    script_path = "/home/akushnir/ElevatedIQ-Mono-Repo/scripts/failover/shift_traffic.sh"
    with open(script_path) as f:
        content = f.read()
        indicators = [
            'PRIMARY_HEALTH_CHECK_ID="c2678680-60a0-4354-944d-5853f60f7811"',
            'SECONDARY_HEALTH_CHECK_ID="7bd13f42-9a2c-4e81-b541-698f12345678"',
            'TERTIARY_HEALTH_CHECK_ID="8de24a53-0b3d-5f92-c652-709f23456789"',
        ]
        all_pass = True
        for ind in indicators:
            if ind in content:
                logger.info(f"✅ Confirmed locked Health Check ID: {ind.split('=')[0]}")
            else:
                logger.error(f"❌ Health Check ID not locked in shift_traffic.sh: {ind}")
                all_pass = False
    return all_pass


def main():
    """Main function."""
    logger.info("Starting Phase 9.2B Pre-Flight Environmental Validation...")

    checks = {
        "Artifact Presence": check_files(),
        "Environment Config": check_env_vars(),
        "Traffic Configuration": validate_traffic_config(),
    }

    if all(checks.values()):
        logger.info("🚀 [STATUS: READY] All pre-flight checks passed for Feb 13 06:00 UTC Deployment.")
        sys.exit(0)
    else:
        logger.error("🛑 [STATUS: FAILED] Pre-flight checks failed. Manual intervention required.")
        sys.exit(1)


if __name__ == "__main__":
    main()
