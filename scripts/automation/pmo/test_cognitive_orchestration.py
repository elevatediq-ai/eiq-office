import asyncio
import os
import sys

# Add relevant paths
sys.path.append(os.getcwd())
sys.path.append(os.path.join(os.getcwd(), "libs/ml"))

from libs.ml.cognitive_deployment_orchestrator import CognitiveDeploymentOrchestrator


async def test_cognitive_orchestrator():
    print("🚀 Initializing Cognitive Orchestrator Test...")
    orchestrator = CognitiveDeploymentOrchestrator()

    # Wait for synthetic data training
    print("⏳ Waiting for model training...")
    await asyncio.sleep(2)

    service = "intelligence-api"
    regions = ["us-east-1", "us-west-2", "eu-west-1", "ap-southeast-1"]
    resources = {"cpu": 85, "memory": 90}
    user_location = "us-east-1"

    print(f"🔍 Testing recommendation for {service}...")
    recommendation = await orchestrator.recommend_optimal_region(service, "aws", regions, resources, user_location)

    print("\n✅ Recommendation Result:")
    print(f"Best Region: {recommendation['best_region']}")
    print(f"Composite Score: {recommendation['score']:.4f}")

    print("\n📊 Regional Rankings:")
    for rank in recommendation["all_ranked_regions"]:
        print(f" - {rank['region']}: {rank['score']:.4f} (latency score: {rank['latency_score']:.4f})")

    # Phase 9.2: Test Feedback Loop
    print("\n🔄 Testing Feedback Loop (Phase 9.2)...")
    print("📉 Recording 10 consecutive failures in 'us-east-1' for 'intelligence-api'...")
    for i in range(10):
        await orchestrator.record_deployment_outcome(
            deployment_id=f"fail-loop-{i}",
            service_name=service,
            cloud_provider="aws",
            region="us-east-1",
            success=False,
            duration_seconds=500.0,
            failure_reason="simulated_failure",
        )

    print("\n🔍 Re-testing recommendation after failures...")
    new_recommendation = await orchestrator.recommend_optimal_region(service, "aws", regions, resources, user_location)

    print(f"New Best Region: {new_recommendation['best_region']}")
    print(
        f"New Score for us-east-1: {next(r['score'] for r in new_recommendation['all_ranked_regions'] if r['region'] == 'us-east-1'):.4f}"
    )

    if new_recommendation["best_region"] != "us-east-1":
        print("✅ Success: ML Orchestrator learned to avoid us-east-1 after failures!")
    else:
        print("⚠️ Warning: ML Orchestrator still prefers us-east-1 (may need more samples or stronger weight)")


if __name__ == "__main__":
    asyncio.run(test_cognitive_orchestrator())
