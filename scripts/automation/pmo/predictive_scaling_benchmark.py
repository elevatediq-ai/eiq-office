#!/usr/bin/env python3
"""🚀 Predictive Scaling Performance Benchmark
M5.4: Predictive Scaling Algorithms Validation
NIST SI-4: Information System Monitoring.

Benchmarks AI-driven scaling performance for hyper-scale operations
"""

import asyncio
import json
import logging
from dataclasses import asdict
from datetime import datetime, timedelta
from typing import Any

import numpy as np
from cost_optimizer import CostOptimizationEngine

# Import our scaling components
from scaling_orchestrator import PredictiveScalingOrchestrator, ScalingMetrics

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class PredictiveScalingBenchmark:
    """Comprehensive predictive scaling benchmark."""

    def __init__(
        self,
        orchestrator: PredictiveScalingOrchestrator,
        cost_engine: CostOptimizationEngine,
    ):
        self.orchestrator = orchestrator
        self.cost_engine = cost_engine
        self.benchmark_results = {}
        self.system_metrics = []

    async def record_system_metrics(self) -> dict[str, Any]:
        """Record system-wide performance metrics."""
        # In production, this would collect from Prometheus/Kubernetes
        metrics = {
            "timestamp": datetime.now().isoformat(),
            "active_pods": np.random.randint(10, 100),
            "cpu_utilization_cluster": np.random.uniform(0.3, 0.9),
            "memory_utilization_cluster": np.random.uniform(0.4, 0.85),
            "network_throughput_mbps": np.random.uniform(100, 2000),
            "api_response_time_ms": np.random.uniform(10, 200),
            "error_rate_percent": np.random.uniform(0.01, 2.0),
        }
        self.system_metrics.append(metrics)
        return metrics

    async def simulate_workload_patterns(self, service_name: str, duration_minutes: int = 60) -> list[ScalingMetrics]:
        """Simulate realistic workload patterns for benchmarking."""
        logger.info(f"Simulating {duration_minutes} minutes of workload for {service_name}")

        metrics = []
        start_time = datetime.now()

        # Define workload patterns
        patterns = {
            "business_hours": {
                "hours": (9, 17),
                "base_load": 0.8,
                "peak_load": 2.0,
                "pattern": "business",
            },
            "off_hours": {
                "hours": (17, 9),
                "base_load": 0.2,
                "peak_load": 0.6,
                "pattern": "maintenance",
            },
            "weekend": {
                "hours": (0, 24),
                "base_load": 0.3,
                "peak_load": 0.8,
                "pattern": "weekend",
            },
        }

        for minute in range(duration_minutes):
            current_time = start_time + timedelta(minutes=minute)
            hour = current_time.hour
            is_weekend = current_time.weekday() >= 5

            # Determine pattern
            if is_weekend:
                pattern = patterns["weekend"]
            elif 9 <= hour <= 17:
                pattern = patterns["business_hours"]
            else:
                pattern = patterns["off_hours"]

            # Generate load based on pattern
            if pattern["pattern"] == "business":
                # Business hours: gradual increase to peak, then gradual decrease
                if hour < 12:
                    load_factor = pattern["base_load"] + (pattern["peak_load"] - pattern["base_load"]) * (
                        (hour - 9) / 3
                    )
                else:
                    load_factor = pattern["peak_load"] - (pattern["peak_load"] - pattern["base_load"]) * (
                        (hour - 12) / 5
                    )
            else:
                # Off hours/weekend: steady with some variation
                load_factor = pattern["base_load"] + np.random.uniform(0, pattern["peak_load"] - pattern["base_load"])

            # Add random spikes (simulating viral content, flash sales, etc.)
            if np.random.random() < 0.05:  # 5% chance of spike
                load_factor *= np.random.uniform(1.5, 3.0)

            # Add noise
            load_factor *= np.random.normal(1.0, 0.1)

            # Generate metrics
            metric = ScalingMetrics(
                timestamp=current_time,
                cpu_utilization=min(0.95, load_factor * np.random.uniform(0.4, 0.8)),
                memory_utilization=min(0.9, load_factor * np.random.uniform(0.5, 0.75)),
                request_rate=load_factor * np.random.uniform(1000, 50000),  # 1K-50K RPS
                response_time=load_factor * np.random.uniform(10, 150),  # 10-150ms
                error_rate=np.random.uniform(0.001, 0.03),  # 0.1%-3%
                active_connections=int(load_factor * np.random.uniform(100, 10000)),
                queue_depth=int(load_factor * np.random.uniform(0, 50)),
            )

            metrics.append(metric)

            # Small delay to simulate real-time data
            await asyncio.sleep(0.01)

        logger.info(f"Generated {len(metrics)} metrics for {service_name}")
        return metrics

    async def benchmark_scaling_accuracy(self, service_name: str, test_duration_minutes: int = 120) -> dict[str, Any]:
        """Benchmark scaling decision accuracy."""
        logger.info(f"Benchmarking scaling accuracy for {service_name}")

        # Simulate workload
        metrics = await self.simulate_workload_patterns(service_name, test_duration_minutes)

        # Feed metrics to orchestrator
        scaling_decisions = []
        actual_loads = []

        for i, metric in enumerate(metrics):
            # Add metric to orchestrator
            if service_name not in self.orchestrator.metrics_buffer:
                self.orchestrator.metrics_buffer[service_name] = []

            self.orchestrator.metrics_buffer[service_name].append(metric)

            # Keep buffer size manageable
            if len(self.orchestrator.metrics_buffer[service_name]) > 1000:
                self.orchestrator.metrics_buffer[service_name] = self.orchestrator.metrics_buffer[service_name][-1000:]

            # Record actual load
            actual_loads.append(metric.request_rate)

            # Every 10 minutes, check for scaling decisions
            if i % 10 == 0 and i > 50:  # Need some history first
                try:
                    decision = await self.orchestrator._calculate_scaling_decision(
                        service_name, self.orchestrator.metrics_buffer[service_name]
                    )
                    if decision:
                        scaling_decisions.append(
                            {
                                "timestamp": decision.timestamp,
                                "predicted_load": decision.predicted_load,
                                "recommended_replicas": decision.recommended_replicas,
                                "confidence": decision.confidence_score,
                                "actual_load_at_decision": metric.request_rate,
                            }
                        )
                except Exception as e:
                    logger.error(f"Scaling decision error: {e}")

        # Analyze scaling accuracy
        if not scaling_decisions:
            return {"error": "No scaling decisions made during test period"}

        predictions = [d["predicted_load"] for d in scaling_decisions]
        actuals = [d["actual_load_at_decision"] for d in scaling_decisions]

        # Calculate accuracy metrics
        mae = np.mean(np.abs(np.array(predictions) - np.array(actuals)))
        mape = np.mean(np.abs((np.array(predictions) - np.array(actuals)) / np.array(actuals))) * 100
        rmse = np.sqrt(np.mean((np.array(predictions) - np.array(actuals)) ** 2))

        # Scaling decision quality
        confidence_scores = [d["confidence"] for d in scaling_decisions]
        avg_confidence = np.mean(confidence_scores)

        # Cost impact analysis
        total_decisions = len(scaling_decisions)
        successful_decisions = sum(1 for d in scaling_decisions if d["confidence"] > 0.7)

        return {
            "service_name": service_name,
            "test_duration_minutes": test_duration_minutes,
            "total_decisions": total_decisions,
            "successful_decisions": successful_decisions,
            "success_rate": (successful_decisions / total_decisions if total_decisions > 0 else 0),
            "accuracy_metrics": {
                "mae": mae,
                "mape": mape,
                "rmse": rmse,
                "mean_absolute_percentage_error": mape,
            },
            "confidence_metrics": {
                "avg_confidence": avg_confidence,
                "min_confidence": min(confidence_scores),
                "max_confidence": max(confidence_scores),
            },
            "load_characteristics": {
                "avg_load": np.mean(actual_loads),
                "peak_load": max(actual_loads),
                "load_variance": np.var(actual_loads),
                "load_range": max(actual_loads) - min(actual_loads),
            },
        }

    async def benchmark_cost_optimization(self, services: list[str]) -> dict[str, Any]:
        """Benchmark cost optimization effectiveness."""
        logger.info("Benchmarking cost optimization across services")

        optimizations = []
        total_savings = 0
        total_current_cost = 0

        for service in services:
            try:
                # Simulate current resource utilization
                utilization = {
                    "cpu": np.random.uniform(0.5, 0.8),
                    "memory": np.random.uniform(0.6, 0.85),
                }

                # Get cost optimization
                optimization = self.cost_engine.optimize_instance_selection(
                    service,
                    {"min_cpu": 2, "min_memory": 4, "max_budget": 2000},
                    utilization,
                )

                optimizations.append(optimization)
                total_savings += optimization.cost_savings
                total_current_cost += optimization.current_cost

            except Exception as e:
                logger.error(f"Cost optimization error for {service}: {e}")

        overall_savings_percent = (total_savings / total_current_cost) * 100 if total_current_cost > 0 else 0

        return {
            "total_services": len(services),
            "total_current_cost": total_current_cost,
            "total_savings": total_savings,
            "overall_savings_percent": overall_savings_percent,
            "optimizations": [asdict(opt) for opt in optimizations],
            "top_savings_opportunities": sorted(
                [asdict(opt) for opt in optimizations],
                key=lambda x: x["cost_savings"],
                reverse=True,
            )[:5],
        }

    async def benchmark_multi_cloud_scaling(self, services: list[str]) -> dict[str, Any]:
        """Benchmark multi-cloud deployment optimization."""
        logger.info("Benchmarking multi-cloud scaling optimization")

        multi_cloud_deployments = []

        for service in services:
            try:
                traffic_patterns = {
                    "peak_rps": np.random.uniform(20000, 100000),
                    "avg_rps": np.random.uniform(5000, 30000),
                    "geo_distribution": {
                        "us-east": np.random.uniform(0.4, 0.7),
                        "eu-west": np.random.uniform(0.2, 0.4),
                        "asia": np.random.uniform(0.1, 0.3),
                    },
                }

                deployment = self.cost_engine.optimize_multi_cloud_deployment(service, traffic_patterns)
                multi_cloud_deployments.append(asdict(deployment))

            except Exception as e:
                logger.error(f"Multi-cloud optimization error for {service}: {e}")

        total_cost_optimization = sum(d["cost_optimization"] for d in multi_cloud_deployments)

        return {
            "total_services": len(services),
            "total_cost_optimization": total_cost_optimization,
            "avg_cost_savings_percent": (
                total_cost_optimization / len(multi_cloud_deployments) if multi_cloud_deployments else 0
            ),
            "deployments": multi_cloud_deployments,
            "cloud_distribution": self._analyze_cloud_distribution(multi_cloud_deployments),
        }

    def _analyze_cloud_distribution(self, deployments: list[dict]) -> dict[str, Any]:
        """Analyze cloud provider distribution in multi-cloud deployments."""
        primary_clouds = {}
        secondary_clouds = {}

        for deployment in deployments:
            primary = deployment["primary_cloud"]
            secondary = deployment["secondary_cloud"]

            primary_clouds[primary] = primary_clouds.get(primary, 0) + 1
            secondary_clouds[secondary] = secondary_clouds.get(secondary, 0) + 1

        return {
            "primary_cloud_distribution": primary_clouds,
            "secondary_cloud_distribution": secondary_clouds,
            "most_used_primary": (max(primary_clouds.items(), key=lambda x: x[1]) if primary_clouds else None),
            "most_used_secondary": (max(secondary_clouds.items(), key=lambda x: x[1]) if secondary_clouds else None),
        }

    async def run_comprehensive_benchmark(self, services: list[str] = None) -> dict[str, Any]:
        """Run comprehensive predictive scaling benchmark suite."""
        if services is None:
            services = [
                "api-gateway",
                "cache-service",
                "ai-inference",
                "data-processor",
            ]

        logger.info("🚀 Starting Comprehensive Predictive Scaling Benchmark")
        logger.info(f"Services: {services}")

        # Initialize components
        await self.orchestrator.initialize()

        # Record initial system state
        await self.record_system_metrics()

        # Run individual benchmarks
        scaling_accuracy_results = {}
        for service in services:
            scaling_accuracy_results[service] = await self.benchmark_scaling_accuracy(service, 60)  # 1 hour test

        cost_optimization_results = await self.benchmark_cost_optimization(services)
        multi_cloud_results = await self.benchmark_multi_cloud_scaling(services)

        # Get final orchestrator status
        orchestrator_status = await self.orchestrator.get_scaling_status()
        orchestrator_health = await self.orchestrator.health_check()

        # Record final system state
        await self.record_system_metrics()

        # Compile comprehensive results
        benchmark_results = {
            "timestamp": datetime.now().isoformat(),
            "benchmark_version": "1.0.0",
            "services_tested": services,
            "scaling_accuracy_benchmark": scaling_accuracy_results,
            "cost_optimization_benchmark": cost_optimization_results,
            "multi_cloud_benchmark": multi_cloud_results,
            "orchestrator_status": orchestrator_status,
            "orchestrator_health": orchestrator_health,
            "system_metrics": self.system_metrics,
            "summary": self._generate_benchmark_summary(
                scaling_accuracy_results, cost_optimization_results, multi_cloud_results
            ),
        }

        # Save results
        self._save_benchmark_results(benchmark_results)

        return benchmark_results

    def _generate_benchmark_summary(
        self, scaling_results: dict, cost_results: dict, multi_cloud_results: dict
    ) -> dict[str, Any]:
        """Generate comprehensive benchmark summary."""
        # Scaling accuracy summary
        avg_accuracy = np.mean(
            [
                r.get("accuracy_metrics", {}).get("mape", 100)
                for r in scaling_results.values()
                if "accuracy_metrics" in r
            ]
        )
        avg_confidence = np.mean(
            [
                r.get("confidence_metrics", {}).get("avg_confidence", 0)
                for r in scaling_results.values()
                if "confidence_metrics" in r
            ]
        )

        # Cost optimization summary
        total_cost_savings = cost_results.get("total_savings", 0)
        overall_savings_percent = cost_results.get("overall_savings_percent", 0)

        # Multi-cloud summary
        multi_cloud_savings = multi_cloud_results.get("total_cost_optimization", 0)

        # Overall performance score (0-100)
        accuracy_score = max(0, 100 - avg_accuracy)  # Lower MAPE = higher score
        confidence_score = avg_confidence * 100
        cost_score = min(100, overall_savings_percent * 10)  # Cap at 100

        overall_score = (accuracy_score + confidence_score + cost_score) / 3

        return {
            "overall_performance_score": overall_score,
            "scaling_accuracy": {
                "average_mape": avg_accuracy,
                "average_confidence": avg_confidence,
                "accuracy_score": accuracy_score,
            },
            "cost_optimization": {
                "total_savings": total_cost_savings,
                "overall_savings_percent": overall_savings_percent,
                "cost_score": cost_score,
            },
            "multi_cloud": {
                "total_optimization": multi_cloud_savings,
                "services_optimized": multi_cloud_results.get("total_services", 0),
            },
            "hyper_scale_readiness": {
                "scaling_accuracy_ready": avg_accuracy < 20,  # <20% MAPE
                "confidence_ready": avg_confidence > 0.7,  # >70% confidence
                "cost_optimization_ready": overall_savings_percent > 15,  # >15% savings
                "overall_ready": overall_score > 70,  # >70 overall score
            },
        }

    def _save_benchmark_results(self, results: dict):
        """Save benchmark results to file."""
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        filename = f"predictive_scaling_benchmark_{timestamp}.json"

        with open(filename, "w") as f:
            json.dump(results, f, indent=2, default=str)

        logger.info(f"Benchmark results saved to {filename}")

    def print_benchmark_summary(self, results: dict):
        """Print comprehensive benchmark summary."""
        print("\n" + "=" * 80)
        print("🚀 PREDICTIVE SCALING BENCHMARK RESULTS")
        print("=" * 80)

        summary = results["summary"]

        print("\n📊 OVERALL PERFORMANCE:")
        print(f"  Total Requests: {summary['total_requests']:,}")
        print(f"  Duration: {summary['duration_seconds']:.1f}s")
        print(f"  QPS: {summary['qps']:.1f}")

        print("\n🎯 SCALING ACCURACY:")
        acc = summary["scaling_accuracy"]
        print(f"  Cold Start Reduction: {acc['cold_start_reduction']:.1f}%")
        print(f"  Over-Provisioning: {acc['over_provisioning']:.1%}")
        print(f"  Cost Efficiency: {acc['cost_efficiency']:.1f}%")
        print("\n💰 COST OPTIMIZATION:")
        cost = summary["cost_optimization"]
        print(f"  Monthly Savings: ${cost['monthly_savings']:.2f}")
        print(f"  Utilization Improvement: {cost['utilization_improvement']:.1f}%")
        print(f"  Reserved Instance Usage: {cost['reserved_instance_usage']:.1f}%")

        print("\n☁️ MULTI-CLOUD OPTIMIZATION:")
        mc = summary["multi_cloud"]
        print(f"  Cross-Cloud Efficiency: {mc['cross_cloud_efficiency']:.2f}%")
        print(f"  Services Optimized: {mc['services_optimized']}")

        print("\n🏥 HYPER-SCALE READINESS:")
        ready = summary["hyper_scale_readiness"]
        print(f"  Scaling Accuracy Ready: {'✅' if ready['scaling_accuracy_ready'] else '❌'}")
        print(f"  Confidence Ready: {'✅' if ready['confidence_ready'] else '❌'}")
        print(f"  Cost Optimization Ready: {'✅' if ready['cost_optimization_ready'] else '❌'}")
        print(f"  Overall Ready: {'✅' if ready['overall_ready'] else '❌'}")

        if ready["overall_ready"]:
            print("\n🎉 PREDICTIVE SCALING: VALIDATED FOR HYPER-SCALE OPERATIONS!")
        else:
            print("\n⚠️ PREDICTIVE SCALING requires optimization for full hyper-scale performance")

        print("\n" + "=" * 80)


async def main():
    """Main benchmark execution function."""
    # Initialize components
    orchestrator = PredictiveScalingOrchestrator()
    cost_engine = CostOptimizationEngine()

    # Create benchmark instance
    benchmark = PredictiveScalingBenchmark(orchestrator, cost_engine)

    try:
        # Run comprehensive benchmark
        results = await benchmark.run_comprehensive_benchmark()

        # Print summary
        benchmark.print_benchmark_summary(results)

        # Validate hyper-scale requirements
        summary = results["summary"]
        overall_score = summary["overall_performance_score"]
        accuracy_ready = summary["hyper_scale_readiness"]["scaling_accuracy_ready"]
        confidence_ready = summary["hyper_scale_readiness"]["confidence_ready"]
        cost_ready = summary["hyper_scale_readiness"]["cost_optimization_ready"]

        print("\n🎯 HYPER-SCALE VALIDATION:")
        print(f"  Target Overall Score: 70+ | Achieved: {overall_score:.1f} {'✅' if overall_score >= 70 else '❌'}")
        print(f"  Scaling Accuracy (<20% MAPE): {'✅' if accuracy_ready else '❌'}")
        print(f"  Decision Confidence (>70%): {'✅' if confidence_ready else '❌'}")
        print(f"  Cost Optimization (>15% savings): {'✅' if cost_ready else '❌'}")

    finally:
        await orchestrator.close()


if __name__ == "__main__":
    asyncio.run(main())
