#!/usr/bin/env python3
"""🚀 ElevatedIQ: Phase 6 Global Health Monitor
NIST-CA-7 | Continuous Monitoring.

Aggregates regional health metrics from federated Prometheus to provide
a global view of the executive plane.
"""

import json
import logging
import os
from datetime import datetime

from prometheus_api_client import PrometheusConnect

# Setup logging
logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(name)s - %(levelname)s - %(message)s")
logger = logging.getLogger("GlobalHealthMonitor")

REGIONS = {
    "us-east-1": os.getenv("PROMETHEUS_US_EAST_1", "http://us-east-1.prometheus.elevatediq.com:9090"),
    "eu-west-1": os.getenv("PROMETHEUS_EU_WEST_1", "http://eu-west-1.prometheus.elevatediq.com:9090"),
    "ap-southeast-1": os.getenv(
        "PROMETHEUS_AP_SOUTHEAST_1",
        "http://ap-southeast-1.prometheus.elevatediq.com:9090",
    ),
}

# Critical metrics to check for NIST-SI-4 Compliance
METRIC_QUERIES = {
    "api_latency_p95": "histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket[5m])) by (le))",
    "error_rate_5xx": 'sum(rate(http_requests_total{status=~"5.."}[5m])) / sum(rate(http_requests_total[5m]))',
    "kafka_lag_max": "max(kafka_consumer_lag_offsets)",
    "db_replication_lag": "max(aurora_replication_lag_seconds)",
}


def get_region_metrics(region, prom_url):
    """Query Prometheus for a specific region's health metrics."""
    metrics = {}
    try:
        # In actual Phase 6, we point to the federated prometheus or regional endpoints
        prom = PrometheusConnect(url=prom_url, disable_ssl=True)
        for name, query in METRIC_QUERIES.items():
            result = prom.custom_query(query=query)
            if result and len(result) > 0:
                metrics[name] = float(result[0]["value"][1])
            else:
                metrics[name] = 0.0
        return metrics, "ONLINE"
    except Exception:
        logger.warning(f"Could not reach Prometheus for {region} at {prom_url}. Using cached/null metrics.")
        return {k: 0.0 for k in METRIC_QUERIES.keys()}, "UNREACHABLE"


def determine_health_status(metrics, region_status):
    """Determine health status based on thresholds (NIST-CP-10)."""
    if region_status != "ONLINE":
        return "CRITICAL"

    # Thresholds for Phase 6 Performance (Four 9s targets)
    if metrics.get("api_latency_p95", 0) > 0.5:  # 500ms
        return "DEGRADED"
    if metrics.get("error_rate_5xx", 0) > 0.01:  # 1%
        return "DEGRADED"
    if metrics.get("kafka_lag_max", 0) > 10000:
        return "WARNING"

    return "HEALTHY"


def check_global_health():
    """Executes the global health check sequence."""
    logger.info("🚀 Initiating Global Health Audit [NIST-CA-7]")

    report = {
        "timestamp": datetime.now().isoformat(),
        "version": "1.1.0",
        "nist_alignment": ["CA-7", "SI-4", "CP-10"],
        "summary": {"health_score": 0, "active_regions": 0},
        "regions": {},
    }

    healthy_count = 0
    for region, url in REGIONS.items():
        metrics, region_status = get_region_metrics(region, url)
        status = determine_health_status(metrics, region_status)

        report["regions"][region] = {
            "status": status,
            "endpoint_connected": region_status == "ONLINE",
            "metrics": metrics,
            "last_check": datetime.now().isoformat(),
        }

        if status == "HEALTHY":
            healthy_count += 1
        if region_status == "ONLINE":
            report["summary"]["active_regions"] += 1

        logger.info(f"Region {region:15} | Status: {status:10} | Stats: {metrics}")

    # Calculate aggregate health score
    report["summary"]["health_score"] = (healthy_count / len(REGIONS)) * 100

    # Save report for executive dashboard / PMO
    report_dir = "/home/akushnir/ElevatedIQ-Mono-Repo/reports/monitoring"
    os.makedirs(report_dir, exist_ok=True)
    report_path = os.path.join(report_dir, "global_health_latest.json")

    with open(report_path, "w") as f:
        json.dump(report, f, indent=2)

    logger.info(f"✅ Global Audit Complete. Health Score: {report['summary']['health_score']}%")
    logger.info(f"Report persisted to {report_path}")

    return report


if __name__ == "__main__":
    check_global_health()
