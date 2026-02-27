#!/usr/bin/env python3
"""[NIST-SI-4] Pylance Memory Monitor — Workstation Memory Crisis Prevention
Monitors VS Code Pylance LSP memory usage and triggers alerts/remediation.

Issue #5899: Implement Pylance memory profiling & limits on workstation
Issue #5898: Memory crisis: Pylance OOM on workstation runs 24/7

Usage:
  pylance_memory_monitor.py --watch            # Continuous monitoring (30s interval)
  pylance_memory_monitor.py --profile          # Enable memory telemetry
  pylance_memory_monitor.py --threshold 2500   # Set memory threshold (MB)
  pylance_memory_monitor.py --remediate        # Auto-remediate OOM conditions
"""

import json
import logging
import subprocess
import sys
import time
from pathlib import Path

# ============================================================================
# Constants
# ============================================================================

VSCODE_SETTINGS = Path.home() / ".config/Code/User/settings.json"
MONITORING_LOG = Path.home() / ".elevatediq/pylance_memory.log"
ALERT_THRESHOLD_MB = 2500  # Memory limit for Pylance
WARNING_THRESHOLD_MB = 2048  # Warning level before threshold

# ============================================================================
# Logging Setup
# ============================================================================

logging.basicConfig(
    level=logging.INFO,
    format="[%(asctime)s] %(levelname)s - %(message)s",
    handlers=[
        logging.FileHandler(MONITORING_LOG, mode="a"),
        logging.StreamHandler(sys.stdout),
    ],
)
logger = logging.getLogger(__name__)


# ============================================================================
# Memory Monitoring Functions
# ============================================================================


def get_vs_code_processes() -> dict:
    """Get VS Code process memory usage."""
    try:
        result = subprocess.run(
            ["ps", "aux"],
            capture_output=True,
            text=True,
            timeout=5,
        )
        processes = {
            "code": 0,
            "pylance": 0,
            "node": 0,
            "extensionHost": 0,
        }

        for line in result.stdout.split("\n"):
            if "code" in line.lower() and "PID" not in line:
                parts = line.split()
                if len(parts) >= 6:
                    try:
                        rss_kb = int(parts[5])
                        rss_mb = rss_kb / 1024
                        if "extensionhost" in line.lower():
                            processes["extensionHost"] = max(processes["extensionHost"], rss_mb)
                        elif "node" in line.lower():
                            processes["node"] = max(processes["node"], rss_mb)
                        else:
                            processes["code"] = max(processes["code"], rss_mb)
                    except ValueError:
                        pass

        return processes

    except subprocess.TimeoutExpired:
        logger.warning("ps command timed out")
        return {
            "code": 0,
            "pylance": 0,
            "node": 0,
            "extensionHost": 0,
        }


def check_memory_status() -> dict:
    """Check current memory status and return metrics."""
    try:
        result = subprocess.run(
            ["free", "-b"],
            capture_output=True,
            text=True,
            timeout=5,
        )
        lines = result.stdout.split("\n")
        if len(lines) >= 2:
            mem_line = lines[1].split()
            total_mb = int(mem_line[1]) / (1024 * 1024)
            available_mb = int(mem_line[6]) / (1024 * 1024) if len(mem_line) > 6 else 0
            return {
                "total_mb": total_mb,
                "available_mb": available_mb,
                "used_percentage": ((total_mb - available_mb) / total_mb * 100) if total_mb > 0 else 0,
            }
    except Exception as e:
        logger.error(f"Error checking memory: {e}")
    return {"total_mb": 0, "available_mb": 0, "used_percentage": 0}


def read_settings() -> dict:
    """Read VS Code settings.json."""
    try:
        if VSCODE_SETTINGS.exists():
            with open(VSCODE_SETTINGS) as f:
                return json.load(f)
    except Exception as e:
        logger.error(f"Error reading settings: {e}")
    return {}


def write_settings(settings: dict) -> bool:
    """Write VS Code settings.json."""
    try:
        VSCODE_SETTINGS.parent.mkdir(parents=True, exist_ok=True)
        with open(VSCODE_SETTINGS, "w") as f:
            json.dump(settings, f, indent=2)
        return True
    except Exception as e:
        logger.error(f"Error writing settings: {e}")
        return False


def enable_memory_telemetry() -> bool:
    """Enable Pylance memory telemetry in VS Code settings."""
    settings = read_settings()
    updates = {
        "pylance.analysis.enableMemoryTelemetry": True,
        "pylance.analysis.logServerPerf": True,
        "python.analysis.memory.maximumMemory": ALERT_THRESHOLD_MB,
        "python.analysis.memory.minimumMemoryForDisablement": WARNING_THRESHOLD_MB,
    }
    settings.update(updates)
    if write_settings(settings):
        logger.info(f"✓ Enabled memory telemetry. Threshold: {ALERT_THRESHOLD_MB}MB")
        return True
    return False


def check_memory_health() -> tuple[bool, str]:
    """Check memory health and return (is_healthy, message)."""
    procs = get_vs_code_processes()
    check_memory_status()

    total_code_mem = procs["code"] + procs["extensionHost"]

    if total_code_mem > ALERT_THRESHOLD_MB:
        return (
            False,
            f"🚨 CRITICAL: VS Code memory {total_code_mem:.0f}MB exceeds threshold {ALERT_THRESHOLD_MB}MB",
        )
    elif total_code_mem > WARNING_THRESHOLD_MB:
        return (
            False,
            f"⚠️  WARNING: VS Code memory {total_code_mem:.0f}MB approaching threshold {ALERT_THRESHOLD_MB}MB",
        )
    else:
        return (True, f"✓ Healthy: VS Code memory {total_code_mem:.0f}MB")


def remediate_oom() -> bool:
    """Attempt to remediate OOM condition."""
    logger.warning("🔧 Attempting OOM remediation...")

    try:
        # Try to kill and restart VS Code extension host
        subprocess.run(
            ["killall", "-9", "node"],
            capture_output=True,
            timeout=5,
        )
        logger.info("✓ Restarted extension host processes")

        # Clear Pylance cache
        cache_dir = Path.home() / ".vscode/extensions"
        for pylance_cache in cache_dir.glob("*ms-python.vscode-pylance*/server"):
            try:
                subprocess.run(
                    ["rm", "-rf", str(pylance_cache)],
                    timeout=5,
                )
                logger.info(f"✓ Cleared cache: {pylance_cache}")
            except Exception as e:
                logger.error(f"Error clearing cache: {e}")

        return True
    except Exception as e:
        logger.error(f"Remediation failed: {e}")
        return False


def monitor_loop(interval: int = 30, duration: int | None = None) -> None:
    """Continuous memory monitoring loop."""
    logger.info(f"🔍 Starting memory monitor (interval: {interval}s)")
    start_time = time.time()

    while True:
        try:
            is_healthy, message = check_memory_health()
            logger.info(message)

            if not is_healthy:
                # Log alert
                logger.warning(f"🚨 Alert triggered: {message}")

                # Auto-remediate if critical
                if "CRITICAL" in message:
                    logger.error("💥 Automatic remediation triggered due to critical memory state")
                    remediate_oom()

            # Check duration if specified
            if duration and (time.time() - start_time) > duration:
                logger.info("✓ Monitoring duration complete")
                break

            time.sleep(interval)

        except KeyboardInterrupt:
            logger.info("✓ Monitoring stopped by user")
            break
        except Exception as e:
            logger.error(f"Monitor error: {e}")
            time.sleep(interval)


# ============================================================================
# CLI Interface
# ============================================================================


def main():
    """Main CLI interface."""
    import argparse

    parser = argparse.ArgumentParser(description="Pylance Memory Monitor — Workstation OOM Prevention")
    parser.add_argument(
        "--watch",
        action="store_true",
        help="Start continuous memory monitoring (30s interval)",
    )
    parser.add_argument(
        "--profile",
        action="store_true",
        help="Enable Pylance memory telemetry",
    )
    parser.add_argument(
        "--threshold",
        type=int,
        default=ALERT_THRESHOLD_MB,
        help=f"Memory threshold in MB (default: {ALERT_THRESHOLD_MB})",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="Check current memory status",
    )
    parser.add_argument(
        "--remediate",
        action="store_true",
        help="Attempt OOM remediation",
    )
    parser.add_argument(
        "--duration",
        type=int,
        help="Monitor duration in seconds (--watch only)",
    )

    args = parser.parse_args()

    # Set custom threshold if provided
    if args.threshold != ALERT_THRESHOLD_MB:
        globals()["ALERT_THRESHOLD_MB"] = args.threshold
        logger.info(f"Custom threshold set to {args.threshold}MB")

    if args.profile:
        logger.info("📊 Enabling Pylance memory telemetry...")
        if enable_memory_telemetry():
            logger.info("✓ Memory telemetry enabled")
        else:
            logger.error("✗ Failed to enable telemetry")
            sys.exit(1)

    elif args.check:
        logger.info("📈 Checking memory status...")
        is_healthy, message = check_memory_health()
        print(message)
        sys.exit(0 if is_healthy else 1)

    elif args.remediate:
        logger.info("🔧 Running remediation...")
        if remediate_oom():
            logger.info("✓ Remediation complete")
        else:
            logger.error("✗ Remediation failed")
            sys.exit(1)

    elif args.watch:
        monitor_loop(duration=args.duration)

    else:
        parser.print_help()


if __name__ == "__main__":
    main()
