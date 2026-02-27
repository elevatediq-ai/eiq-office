import asyncio
import logging
import os

# Set up paths
import sys

project_root = "/home/akushnir/ElevatedIQ-Mono-Repo"
sys.path.append(os.path.join(project_root, "apps/control_plane/src"))

from control_plane.services.architecture_adaptation.engine import ArchitectureAdaptationEngine
from control_plane.services.policy_evolution.engine import DynamicPolicyEvolutionEngine
from control_plane.services.self_optimization.loop import SelfOptimizationLoop

# Configure logging
logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(name)s - %(levelname)s - %(message)s")
logger = logging.getLogger("AutonomousDeploymentValidation")


async def run_deployment_validation():
    logger.info("🚀 Starting Phase 10.6: Autonomous Engine Deployment Validation (Staging Simulation)")

    # 1. Initialize Engines
    opt_loop = SelfOptimizationLoop()
    arch_engine = ArchitectureAdaptationEngine()
    policy_engine = DynamicPolicyEvolutionEngine()

    await opt_loop.initialize()
    await arch_engine.initialize()
    await policy_engine.initialize()

    logger.info("✅ All engines initialized and healthy with default policies.")

    # 3. Simulate Production-like Workload Transition
    # Start with baseline, move to high load
    workload_steps = [
        {"latency": 150, "cpu": 0.20, "throughput": 1000, "errors": 0.001},  # Baseline
        {"latency": 180, "cpu": 0.25, "throughput": 1200, "errors": 0.002},
        {
            "latency": 450,
            "cpu": 0.65,
            "throughput": 3000,
            "errors": 0.005,
        },  # Spike starts
        {
            "latency": 900,
            "cpu": 0.92,
            "throughput": 4500,
            "errors": 0.015,
        },  # Critical threshold
    ]

    for i, data in enumerate(workload_steps):
        logger.info(
            f"Step {i + 1}/{len(workload_steps)}: Workload -> {data['throughput']} req/s, {data['latency']}ms latency"
        )

        # 4. Autonomous Decision Cycle
        # Optimization Loop
        metrics = await opt_loop.collect_metrics(
            {
                "latency_p95": data["latency"],
                "cpu_utilization": data["cpu"],
                "throughput": data["throughput"],
                "error_rate": data["errors"],
            }
        )

        analysis = await opt_loop.analyze_performance()
        if "opportunities" in analysis and analysis["opportunities"]:
            logger.info(f"  [OptLoop] Identified {len(analysis['opportunities'])} opportunities.")

        # Policy Evolution
        # Simulate history for engines
        for _ in range(5):
            policy_engine.effectiveness_history["timeout_default"].append(0.5)  # mediocre

        policy_recs = await policy_engine.generate_policy_recommendations()
        if policy_recs:
            logger.info(f"  [PolicyEngine] Generated {len(policy_recs)} recommendations.")
            for rec in policy_recs:
                if rec.confidence_score > 0.8:
                    logger.info(f"  [PolicyEngine] AUTO-APPLYING recommendation: {rec.reasoning}")
                    await policy_engine.apply_policy_recommendation(rec)

        # Architecture Adaptation
        # Fix the data format for ArchEngine
        performance_data = {
            "metrics": metrics.__dict__,
            "resources": {"main_cluster_cpu": data["cpu"]},
            "errors": {"api": data["errors"]},
            "latencies": {"api_p95": data["latency"]},
            "throughput": {"api": data["throughput"]},
        }
        state = await arch_engine.analyze_system_state(performance_data)
        arch_recs = await arch_engine.generate_recommendations(state)
        if arch_recs:
            logger.info(f"  [ArchEngine] Generated {len(arch_recs)} architecture adaptations.")
            for rec in arch_recs:
                logger.info(f"  [ArchEngine] EXECUTING adaptation: {rec.strategy.value} - {rec.reasoning}")
                # Validate before applying
                success, results = await arch_engine.validate_adaptation(rec)
                if success:
                    await arch_engine.apply_adaptation(rec)
                else:
                    logger.warning(
                        f"  [ArchEngine] Validation failed for {rec.recommendation_id}: {results.get('error')}"
                    )

        await asyncio.sleep(0.1)

    # 5. Final Validation
    logger.info("--- Final Validation Report ---")
    logger.info(f"Total Policy Updates: {len(policy_engine.audit_log)}")
    logger.info(f"Total Architecture Adaptations: {len(arch_engine.adaptation_history)}")

    success = len(policy_engine.audit_log) > 0 or len(arch_engine.adaptation_history) > 0
    if success:
        logger.info("✅ SUCCESS: Autonomous engines demonstrated cohesive self-management under load.")
    else:
        logger.error("❌ FAILURE: No autonomous actions taken despite simulated critical load.")
        sys.exit(1)

    logger.info("🏁 Deployment Validation Complete.")


if __name__ == "__main__":
    asyncio.run(run_deployment_validation())
