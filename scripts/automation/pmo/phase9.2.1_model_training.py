import asyncio
import os
import sys
from datetime import datetime, timedelta

import numpy as np
import pandas as pd

# Add libs to path
sys.path.append(os.path.join(os.getcwd(), "libs"))

from ml.cost_predictor import CostPredictor


def generate_synthetic_data(samples=5000):
    """Generate synthetic infrastructure cost data.
    Cost = (CPU * 0.05) + (Mem * 0.02) + (NodeCount * 0.5) + noise.
    """
    np.random.seed(42)
    start_date = datetime.now() - timedelta(days=200)

    data = []
    for i in range(samples):
        timestamp = start_date + timedelta(hours=i)
        cpu = np.random.uniform(10, 90)
        mem = np.random.uniform(20, 80)
        nodes = np.random.randint(2, 20)
        spokes = 140
        storage = np.random.uniform(100, 5000)
        network = np.random.uniform(10, 1000)

        # Base cost logic
        base_cost = (cpu * 0.05) + (mem * 0.02) + (nodes * 0.5) + (storage * 0.001)

        # Add seasonality (more expensive during business hours)
        hour = timestamp.hour
        hour_factor = 1.2 if 9 <= hour <= 18 else 0.8

        # Add noise
        noise = np.random.normal(0, base_cost * 0.01)  # 1% noise

        cost = (base_cost * hour_factor) + noise

        data.append(
            {
                "timestamp": timestamp,
                "cpu_utilization": cpu,
                "memory_utilization": mem,
                "storage_gb": storage,
                "network_egress_gb": network,
                "spoke_count": spokes,
                "node_count": nodes,
                "cost": cost,
            }
        )

    return pd.DataFrame(data)


async def main():
    """Main function."""
    print("🚀 Starting Phase 9.2.1: Cost Prediction Model Training...")

    # 1. Generate Data
    df = generate_synthetic_data(10000)
    print(f"📊 Generated {len(df)} synthetic data points.")

    # 2. Train Model
    predictor = CostPredictor(model_path="libs/ml/models/cost_model_v1.json")

    # Split data
    train_df = df.iloc[:8000]
    test_df = df.iloc[8000:]

    await predictor.train(train_df)

    # 3. Evaluate
    print("\n--- Model Evaluation ---")
    X_test, y_test = predictor.preprocess_data(test_df)
    preds = predictor.regressor.predict(X_test)

    # Calculate MAPE
    mape = np.mean(np.abs((y_test - preds) / (y_test + 1e-5))) * 100
    print(f"📊 Validation MAPE: {mape:.4f}%")

    if mape < 5:
        print("✅ SUCCESS: Model meets Phase 9.2.1 target (MAPE < 5%)")
    else:
        print("❌ FAILURE: Model accuracy below target")

    # 4. Test Single Prediction
    sample = test_df.iloc[0].to_dict()
    prediction_24h = predictor.predict_next_24h(sample)
    print(f"\n🔮 Prediction for next 24h: ${prediction_24h:.2f}")


if __name__ == "__main__":
    asyncio.run(main())
