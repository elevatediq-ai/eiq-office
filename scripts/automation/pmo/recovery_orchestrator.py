#!/usr/bin/env python3
"""ElevatedIQ: Recovery Orchestrator (The Rebirth Logic)
[NIST-CP-10, NIST-SI-4]
[FedRAMP High Resilience Standard].

Automates the parallel provisioning and health verification of resources
following a shutdown or failure event, completing the 10X lifecycle.
"""

import json
import logging
import os
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from typing import Any

import requests

# Ensure we can import from libs
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "../../")))
from libs.security.credential_manager import CredentialManager

# Configure Logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    handlers=[
        logging.FileHandler("logs/recovery_orchestrator.log"),
        logging.StreamHandler(),
    ],
)
logger = logging.getLogger("RecoveryOrchestrator")


class RecoveryOrchestrator:
    """RecoveryOrchestrator class."""

    def __init__(self, dry_run: bool = False):
        self.dry_run = dry_run
        self.creds = CredentialManager()
        self.results = []

    def execute_command(self, cmd: list[str], cwd: str, label: str) -> bool:
        """Executes a recovery command and returns success status."""
        if self.dry_run:
            logger.info(f"[DRY-RUN] Would execute: {' '.join(cmd)} in {cwd}")
            return True

        logger.info(f"⚡ Recovering: {label}")
        try:
            process = subprocess.Popen(cmd, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            stdout, stderr = process.communicate()

            if process.returncode == 0:
                logger.info(f"✅ Recovered: {label}")
                return True
            else:
                logger.error(f"❌ Recovery Failed: {label}\nError: {stderr}")
                return False
        except Exception as e:
            logger.error(f"💥 Recovery Exception in {label}: {str(e)}")
            return False

    def recover_docker_compose(self, file_path: str):
        """Starts a docker-compose stack and waits for basic health."""
        cwd = os.path.dirname(os.path.abspath(file_path))
        filename = os.path.basename(file_path)
        label = f"Docker Stack: {filename}"

        cmd = ["docker", "compose", "-f", filename, "up", "-d", "--wait"]
        return self.execute_command(cmd, cwd, label)

    def recover_terraform(self, dir_path: str, cloud: str = "gcp"):
        """Applies Terraform configuration with credential injection."""
        label = f"Terraform Infra: {os.path.basename(dir_path)}"

        try:
            self.creds.inject_terraform_env(cloud=cloud)
        except Exception as e:
            logger.error(f"Failed to inject credentials for {label}: {str(e)}")
            return False

        # Init (required after a potential clean checkout or provider change)
        init_cmd = ["terraform", "init", "-input=false"]
        if not self.execute_command(init_cmd, dir_path, f"{label} (Init)"):
            return False

        # Apply
        apply_cmd = ["terraform", "apply", "-auto-approve", "-input=false"]
        return self.execute_command(apply_cmd, dir_path, label)

    def verify_health(self, task: dict[str, Any]) -> bool:
        """Performs post-recovery health checks [NIST-SI-4]."""
        endpoint = task.get("health_endpoint")
        if not endpoint:
            return True  # Assume healthy if no endpoint provided

        logger.info(f"🔍 Checking health for {task['path']} at {endpoint}")
        if self.dry_run:
            return True

        max_retries = 5
        for i in range(max_retries):
            try:
                response = requests.get(endpoint, timeout=5)
                if response.status_code == 200:
                    logger.info(f"💚 Health OK: {task['path']}")
                    return True
            except Exception:
                pass
            logger.warning(f"⏳ Waiting for health... ({i + 1}/{max_retries})")
            time.sleep(5)

        logger.error(f"💔 Health Failed: {task['path']}")
        return False

    def run_parallel_recovery(self, tasks: list[dict[str, Any]]):
        """Executes provided recovery tasks in parallel."""
        logger.info(f"🌟 Initiating parallel recovery of {len(tasks)} components...")
        start_time = time.time()

        with ThreadPoolExecutor(max_workers=os.cpu_count() or 4) as executor:
            future_to_task = {}
            for task in tasks:
                if task["type"] == "docker":
                    future = executor.submit(self.recover_docker_compose, task["path"])
                elif task["type"] == "terraform":
                    future = executor.submit(self.recover_terraform, task["path"], task.get("cloud", "gcp"))
                else:
                    continue
                future_to_task[future] = task

            for future in as_completed(future_to_task):
                task = future_to_task[future]
                try:
                    success = future.result()
                    if success:
                        health_success = self.verify_health(task)
                        self.results.append({"path": task["path"], "success": health_success})
                    else:
                        self.results.append({"path": task["path"], "success": False})
                except Exception as exc:
                    self.results.append({"path": task["path"], "success": False, "error": str(exc)})

        duration = time.time() - start_time
        logger.info(f"🏁 Parallel recovery phase complete in {duration:.2f} seconds.")

    def generate_report(self):
        """Generates a summary report of the recovery session."""
        report_path = f"docs/management/RECOVERY_LOG_{int(time.time())}.json"
        with open(report_path, "w") as f:
            json.dump(self.results, f, indent=4)
        logger.info(f"📊 Recovery report generated at {report_path}")


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Recovery Orchestrator")
    parser.add_argument("--dry-run", action="store_true", help="Perform a dry run")
    parser.add_argument(
        "--config",
        type=str,
        help="Path to a JSON config defining recovery priority groups",
    )
    args = parser.parse_args()

    orchestrator = RecoveryOrchestrator(dry_run=args.dry_run)

    if args.config and os.path.exists(args.config):
        with open(args.config) as f:
            config = json.load(f)
            # For recovery, we typically work in REVERSE of shutdown order,
            # but we use specific 'recovery_groups' if defined.
            groups = config.get("recovery_groups", config.get("groups", {}))

            # Sort groups by name if they are named group1, group2 etc to support ordering
            for group_name in sorted(groups.keys()):
                logger.info(f"--- Processing Priority Group: {group_name} ---")
                orchestrator.run_parallel_recovery(groups[group_name])
    else:
        logger.warning("No configuration provided. Running default recovery demo.")
        demo_tasks = [{"type": "terraform", "path": "infra/terraform/canary", "cloud": "gcp"}]
        orchestrator.run_parallel_recovery(demo_tasks)

    orchestrator.generate_report()

    if any(not r.get("success", False) for r in orchestrator.results):
        sys.exit(1)
    sys.exit(0)
