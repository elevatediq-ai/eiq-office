#!/usr/bin/env python3
"""AI Data Ingestion Trigger
NIST-SI-4: Continuous Monitoring.

Triggers the ingestion of core production metrics into the AI Data Lake.
Scheduled via cron or Airflow.
"""

import asyncio
import logging

# Add libs to path
import os
import sys

sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "../../")))

try:
    from libs.predictive_ops.forecasting.pipeline import DataPipelineOrchestrator, MetricIngestor, ParquetArchiver
    from libs.predictive_ops.prometheus import PrometheusClient
except ImportError as e:
    print(f"Failed to import libs: {e}")
    sys.exit(1)

logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(name)s - %(levelname)s - %(message)s")
logger = logging.getLogger("AI-Ingestion-Trigger")


async def main():
    """Main function."""
    # Configuration (In production, these come from environment variables or Vault)
    prom_url = os.getenv("PROMETHEUS_URL", "http://prometheus-hub.elevatediq.svc.cluster.local:9090")
    lake_bucket = os.getenv("AI_LAKE_BUCKET", "elevatediq-ai-metrics-lake-prod")

    logger.info("Starting AI Data Ingestion Pipeline...")

    prom_client = PrometheusClient(base_url=prom_url)
    ingestor = MetricIngestor(prom_client)
    archiver = ParquetArchiver(bucket_name=lake_bucket)
    orchestrator = DataPipelineOrchestrator(ingestor, archiver)

    # Core metrics to ingest for Phase 7 prediction
    core_metrics = [
        "node_cpu_seconds_total",
        "node_memory_MemAvailable_bytes",
        "http_request_duration_seconds_bucket",
        "container_memory_usage_bytes",
        "kube_pod_container_resource_limits",
    ]

    try:
        await orchestrator.run_daily_ingestion(core_metrics)
        logger.info("✅ Daily ingestion complete.")
    except Exception as e:
        logger.error(f"❌ Ingestion failed: {str(e)}")
        sys.exit(1)


if __name__ == "__main__":
    asyncio.run(main())
