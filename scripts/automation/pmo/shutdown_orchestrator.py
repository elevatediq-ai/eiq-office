#!/usr/bin/env python3
"""ElevatedIQ: Parallel Shutdown Orchestrator
[NIST-SC-7, NIST-IA-2]
[FedRAMP High Resilience Standard].

This script orchestrates the shutdown of cloud resources and local services in parallel,
respecting dependency constraints to resolve the performance bottlenecks identified in #2102.
"""

import json
import logging
import os
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from typing import Any

# Ensure we can import from libs
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "../../")))
from libs.security.credential_manager import CredentialManager

# Configure Logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    handlers=[
        logging.FileHandler("logs/shutdown_orchestrator.log"),
        logging.StreamHandler(),
    ],
)
logger = logging.getLogger("ShutdownOrchestrator")


class ShutdownOrchestrator:
    """ShutdownOrchestrator class."""

    def __init__(self, dry_run: bool = False):
        self.dry_run = dry_run
        self.creds = CredentialManager()
        self.results = []

    def execute_command(self, cmd: list[str], cwd: str, label: str) -> bool:
        """Executes a shell command and returns success status."""
        if self.dry_run:
            logger.info(f"[DRY-RUN] Would execute: {' '.join(cmd)} in {cwd}")
            return True

        logger.info(f"🚀 Starting: {label}")
        try:
            process = subprocess.Popen(cmd, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            stdout, stderr = process.communicate()

            if process.returncode == 0:
                logger.info(f"✅ Completed: {label}")
                return True
            else:
                logger.error(f"❌ Failed: {label}\nError: {stderr}")
                return False
        except Exception as e:
            logger.error(f"💥 Exception in {label}: {str(e)}")
            return False

    def shutdown_docker_compose(self, file_path: str):
        """Shuts down a docker-compose stack."""
        cwd = os.path.dirname(os.path.abspath(file_path))
        filename = os.path.basename(file_path)
        label = f"Docker Stack: {filename}"

        cmd = [
            "docker",
            "compose",
            "-f",
            filename,
            "down",
            "--volumes",
            "--remove-orphans",
        ]
        return self.execute_command(cmd, cwd, label)

    def shutdown_terraform(self, dir_path: str, cloud: str = "gcp"):
        """Shuts down a Terraform workspace with credential injection."""
        label = f"Terraform Infra: {os.path.basename(dir_path)}"

        # Inject credentials
        try:
            self.creds.inject_terraform_env(cloud=cloud)
        except Exception as e:
            logger.error(f"Failed to inject credentials for {label}: {str(e)}")
            return False

        # Destroy
        # We assume 'terraform init' has been run or we run it now
        # For efficiency in shutdown, we assume a pre-initialized state or run quick init
        cmd = ["terraform", "destroy", "-auto-approve"]
        return self.execute_command(cmd, dir_path, label)

    def discover_active_resources(self) -> list[dict[str, Any]]:
        """Dynamically discovers active Docker and Terraform resources [NIST-SC-7]."""
        discovered = []

        # Discover Docker Compose files
        compose_dir = "compose"
        if os.path.exists(compose_dir):
            for file in os.listdir(compose_dir):
                if file.endswith(".yml") or file.endswith(".yaml"):
                    if "docker-compose" in file:
                        discovered.append({"type": "docker", "path": f"{compose_dir}/{file}"})

        # Discover Terraform workspaces
        infra_dir = "infra/terraform"
        if os.path.exists(infra_dir):
            for root, dirs, files in os.walk(infra_dir):
                if ".terraform" in dirs:
                    discovered.append({"type": "terraform", "path": root, "cloud": "gcp"})

        logger.info(f"🔍 Discovered {len(discovered)} potential resources for shutdown.")
        return discovered

    def run_parallel_shutdown(self, tasks: list[dict[str, Any]]):
        """Executes provided tasks in parallel."""
        logger.info(f"🔥 Initiating parallel shutdown of {len(tasks)} components...")
        start_time = time.time()

        with ThreadPoolExecutor(max_workers=os.cpu_count() or 4) as executor:
            future_to_task = {}
            for task in tasks:
                if task["type"] == "docker":
                    future = executor.submit(self.shutdown_docker_compose, task["path"])
                elif task["type"] == "terraform":
                    future = executor.submit(self.shutdown_terraform, task["path"], task.get("cloud", "gcp"))
                else:
                    logger.warning(f"Unknown task type: {task['type']}")
                    continue
                future_to_task[future] = task["path"]

            for future in as_completed(future_to_task):
                path = future_to_task[future]
                try:
                    success = future.result()
                    self.results.append({"path": path, "success": success})
                except Exception as exc:
                    logger.error(f"Task {path} generated an exception: {exc}")
                    self.results.append({"path": path, "success": False, "error": str(exc)})

        duration = time.time() - start_time
        logger.info(f"🏁 Parallel shutdown phase complete in {duration:.2f} seconds.")

    def generate_report(self):
        """Generates a summary report of the shutdown session."""
        report_path = f"docs/management/SHUTDOWN_LOG_{int(time.time())}.json"
        with open(report_path, "w") as f:
            json.dump(self.results, f, indent=4)
        logger.info(f"📊 Shutdown report generated at {report_path}")


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Parallel Shutdown Orchestrator")
    parser.add_argument("--dry-run", action="store_true", help="Perform a dry run")
    parser.add_argument(
        "--config",
        type=str,
        help="Path to a JSON config defining shutdown priority groups",
    )
    parser.add_argument("--discover", action="store_true", help="Dynamically discover resources")
    args = parser.parse_args()

    orchestrator = ShutdownOrchestrator(dry_run=args.dry_run)

    if args.discover:
        tasks = orchestrator.discover_active_resources()
        orchestrator.run_parallel_shutdown(tasks)
    elif args.config and os.path.exists(args.config):
        with open(args.config) as f:
            shutdown_config = json.load(f)
            # Groups are executed sequentially, but tasks within groups are parallel
            for group_name, tasks in shutdown_config.get("groups", {}).items():
                logger.info(f"--- Processing Priority Group: {group_name} ---")
                orchestrator.run_parallel_shutdown(tasks)
    else:
        logger.warning("No configuration provided. Running default demo group.")
        # Example hardcoded discovery for validation
        demo_tasks = [
            {"type": "docker", "path": "compose/docker-compose.control-plane.yml"},
            {"type": "terraform", "path": "infra/terraform/canary", "cloud": "gcp"},
        ]
        orchestrator.run_parallel_shutdown(demo_tasks)

    orchestrator.generate_report()

    # Exit with error if any task failed (NIST-SI-4)
    if any(not r.get("success", False) for r in orchestrator.results):
        logger.error("🛑 One or more shutdown tasks failed. See report for details.")
        sys.exit(1)

    logger.info("🎉 All shutdown tasks completed successfully.")
    sys.exit(0)
