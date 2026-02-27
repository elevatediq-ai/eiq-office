#!/usr/bin/env python3
"""Phase 9.3: Intelligence Engine Master Runner
Orchestrates multi-cloud ingest, cost forecasting, and commitment optimization.
NIST AU-2, CA-7, CM-6 Aligned.
"""

import logging
import os
import sys
from datetime import datetime

import numpy as np
import pandas as pd

# Ensure project root is in path
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))

from libs.ml.commitment_optimizer import CommitmentOptimizer
from libs.ml.cost_forecaster import EnsembleForecaster
from libs.ml.db_utils import IntelligenceDBConnector
from scripts.pmo.multi_cloud_ingest import ingest_all_provider_data

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] [%(name)s] %(message)s")
logger = logging.getLogger("IntelligenceRunner")


def run_intelligence_cycle(model_type="ensemble"):  # noqa: PLR0915
    """run_intelligence_cycle function."""
    logger.info(f"🚀 Starting Phase 9.3 Intelligence Cycle [Model: {model_type}] [NIST-CA-7]")

    db = IntelligenceDBConnector()
    db_available = False
    try:
        db.connect()
        db_available = True
    except Exception as e:
        logger.warning(f"Database unavailable, proceeding in MOCK mode: {str(e)}")

    try:
        # 1. Multi-Cloud Ingest
        logger.info("📡 Step 1: Multi-Cloud Data Ingestion (NIST-CC-7)")
        # In a real environment, this actually pulls and saves to DB
        ingest_all_provider_data(days_back=30)

        # 2. Fetch data facts from DB
        logger.info("📥 Step 2: Fetching cost facts from Data Lake")
        facts_df = pd.DataFrame()
        if db_available:
            facts_df = db.fetch_cost_facts(lookback_days=90)

        if facts_df.empty:
            logger.warning("No cost facts found for training. Using fallback logic.")
            # Mock data for demonstration - two resources for better validation
            r1 = ["i-0abcd1234"] * 60
            r2 = ["i-0efgh5678"] * 60
            dates = pd.date_range(end=datetime.now(), periods=60).tolist() * 2
            costs = np.concatenate([np.random.uniform(10, 20, 60), np.random.uniform(5, 10, 60)])
            facts_df = pd.DataFrame(
                {
                    "resource_id": r1 + r2,
                    "usage_date": dates,
                    "cost": costs,
                    "usage_type": (["ec2.t3.medium"] * 60) + (["ec2.t3.large"] * 60),
                }
            )

        # 3. Time Series Forecasting
        logger.info(f"📈 Step 3: Generating Cost Forecasts ({model_type.upper()}) (NIST-CM-6)")

        all_forecast_records = []
        for resource_id in facts_df["resource_id"].unique():
            resource_df = facts_df[facts_df["resource_id"] == resource_id].copy()

            logger.info(f"Processing forecasts for {resource_id}...")
            forecaster = EnsembleForecaster(resource_id=resource_id)

            # Fit and forecast
            forecaster.fit(resource_df)
            forecasts = forecaster.forecast(steps=30)

            # Prepare for DB
            for f in forecasts:
                all_forecast_records.append(
                    {
                        "resource_id": f.resource_id,
                        "forecast_date": f.forecast_date,
                        "predicted_cost": f.predicted_cost,
                        "lower_bound": f.lower_bound,
                        "upper_bound": f.upper_bound,
                        "model_type": f.model_type,
                        "model_version": "v1.1.0",
                    }
                )

        if db_available:
            db.save_forecasts(all_forecast_records)
        else:
            logger.info(
                f"MOCK: Would save {len(all_forecast_records)} forecasts to DB for {len(facts_df['resource_id'].unique())} resources."
            )

        # 4. Commitment Optimization
        logger.info("💡 Step 4: Analyzing Commitment Opportunities (NIST-CM-3)")
        optimizer = CommitmentOptimizer()
        recommendations = optimizer.generate_recommendations(facts_df)

        for rec in recommendations:
            logger.info(f"Recommendation for {rec['resource_id']}: {len(rec['recommendations'])} plans generated.")

        if db_available:
            db.save_commitment_recommendations(recommendations)

            # Phase 9.3: Sync to Executive Dashboard API if URL provided
            exec_db_url = os.getenv("EXECUTIVE_DB_URL")
            if exec_db_url:
                logger.info("📡 Syncing results to Executive Dashboard API Database...")
                db.sync_intelligence_to_exec_metrics(exec_db_url)
        else:
            logger.info(f"MOCK: Would save recommendations for {len(recommendations)} resources to DB.")

        logger.info("✅ Intelligence Cycle Complete [NIST-AU-2]")

    except Exception as e:
        logger.error(f"Intelligence Cycle Failed: {str(e)}")
        import traceback

        logger.error(traceback.format_exc())
    finally:
        if db_available:
            db.close()


if __name__ == "__main__":
    model = "ensemble"
    if len(sys.argv) > 1:
        model = sys.argv[1]
    run_intelligence_cycle(model_type=model)
