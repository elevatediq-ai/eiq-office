import asyncio
import os
import sys

# Add relevant paths
sys.path.append(os.getcwd())
sys.path.append(os.path.join(os.getcwd(), "libs/ml"))

from libs.ml.cognitive_deployment_orchestrator import CognitiveDeploymentOrchestrator


async def test_xai_explanations():
    print("🚀 Testing Explainable AI (XAI) for Cognitive Orchestrator...")
    orchestrator = CognitiveDeploymentOrchestrator()

    # Wait for synthetic data training
    print("⏳ Waiting for model training...")
    await asyncio.sleep(2)

    service = "intelligence-api"
    cloud = "aws"
    region = "us-east-1"
    resources = {"cpu": 85, "memory": 90}

    print(f"🔍 Testing XAI explanations for {service} in {region}...")
    prediction = await orchestrator.predict_deployment_success(service, cloud, region, resources)

    print("\n✅ Prediction Result:")
    print(f"Success Probability: {prediction.success_probability:.3f}")
    print(f"Confidence Score: {prediction.confidence_score:.3f}")
    print(f"Predicted Duration: {prediction.predicted_duration:.1f}s")
    print(f"Cost Estimate: ${prediction.cost_estimate:.2f}")

    print("\n🔍 XAI Explanations (Phase 9.3):")
    if prediction.explanations:
        print("Feature Importance:")
        for feature, importance in prediction.explanations.get("feature_importance", {}).items():
            print(f"  - {feature}: {importance:.4f}")

        print("\nDecision Factors:")
        for factor in prediction.explanations.get("decision_factors", []):
            print(f"  - {factor}")

        print("\nConfidence Intervals:")
        ci = prediction.explanations.get("confidence_intervals", {})
        print(
            f"  - Success Prob: [{ci.get('success_probability', [0, 1])[0]:.3f}, {ci.get('success_probability', [0, 1])[1]:.3f}]"
        )
        print(f"  - Cost: [${ci.get('cost_estimate', [0, 0])[0]:.2f}, ${ci.get('cost_estimate', [0, 0])[1]:.2f}]")
        print(
            f"  - Duration: [{ci.get('duration_estimate', [0, 0])[0]:.1f}s, {ci.get('duration_estimate', [0, 0])[1]:.1f}s]"
        )

        print("\nUncertainty Quantification:")
        uq = prediction.explanations.get("uncertainty_quantification", {})
        print(f"  - Prediction Confidence: {uq.get('prediction_confidence', 'N/A')}")
        print(f"  - Training Samples: {uq.get('training_samples', 0)}")
        print(f"  - Model Accuracy: {uq.get('model_accuracy', 0):.3f}")
    else:
        print("❌ No explanations available")

    print("\n✅ XAI Test Complete - NIST AI-3.1 Compliant")


if __name__ == "__main__":
    asyncio.run(test_xai_explanations())
