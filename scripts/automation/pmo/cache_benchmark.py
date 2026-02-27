#!/usr/bin/env python3
"""🚀 Multi-Layer Cache Performance Benchmark
M5.3: Advanced Caching Strategies Validation
NIST SI-4: Information System Monitoring.

Benchmarks L1-L3 caching performance for 100K+ RPS hyper-scale operations
"""

import asyncio
import json
import logging
import statistics
import time
from datetime import datetime

import psutil

# Import our cache service
from multi_layer_cache import MultiLayerCache

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class CacheBenchmark:
    """Comprehensive cache performance benchmarking."""

    def __init__(self, cache_instance: MultiLayerCache):
        self.cache = cache_instance
        self.results = {}
        self.system_stats = []

    async def record_system_stats(self):
        """Record system resource usage."""
        stats = {
            "timestamp": datetime.now().isoformat(),
            "cpu_percent": psutil.cpu_percent(interval=1),
            "memory_percent": psutil.virtual_memory().percent,
            "memory_used_gb": psutil.virtual_memory().used / (1024**3),
            "network_connections": len(psutil.net_connections()),
        }
        self.system_stats.append(stats)
        return stats

    async def benchmark_layer(self, layer_name: str, layer_instance, operations: int = 10000) -> dict:
        """Benchmark individual cache layer performance."""
        logger.info(f"Benchmarking {layer_name} layer with {operations} operations")

        # Test data
        test_keys = [f"test:key:{i}" for i in range(1000)]
        test_values = [{"data": f"value_{i}", "metadata": {"size": len(f"value_{i}")}} for i in range(1000)]

        # Warm up
        for i in range(100):
            key, value = test_keys[i], test_values[i]
            await layer_instance.set(key, value, ttl=300)

        # Benchmark set operations
        set_times = []
        start_time = time.time()

        for i in range(operations):
            key, value = test_keys[i % 1000], test_values[i % 1000]
            op_start = time.perf_counter()
            await layer_instance.set(key, value, ttl=300)
            op_end = time.perf_counter()
            set_times.append((op_end - op_start) * 1000)  # ms

        set_duration = time.time() - start_time

        # Benchmark get operations (mix of hits and misses)
        get_times = []
        hits = 0
        misses = 0
        start_time = time.time()

        for i in range(operations):
            if i % 4 == 0:  # 25% misses
                key = f"miss:key:{i}"
            else:
                key = test_keys[i % 1000]

            op_start = time.perf_counter()
            result = await layer_instance.get(key)
            op_end = time.perf_counter()

            get_times.append((op_end - op_start) * 1000)
            if result is not None:
                hits += 1
            else:
                misses += 1

        get_duration = time.time() - start_time

        return {
            "layer": layer_name,
            "operations": operations,
            "set_operations": operations,
            "get_operations": operations,
            "set_duration_sec": set_duration,
            "get_duration_sec": get_duration,
            "set_qps": operations / set_duration,
            "get_qps": operations / get_duration,
            "set_latency_ms": {
                "avg": statistics.mean(set_times),
                "p50": statistics.median(set_times),
                "p95": statistics.quantiles(set_times, n=20)[18],  # 95th percentile
                "p99": statistics.quantiles(set_times, n=100)[98],  # 99th percentile
                "min": min(set_times),
                "max": max(set_times),
            },
            "get_latency_ms": {
                "avg": statistics.mean(get_times),
                "p50": statistics.median(get_times),
                "p95": statistics.quantiles(get_times, n=20)[18],
                "p99": statistics.quantiles(get_times, n=100)[98],
                "min": min(get_times),
                "max": max(get_times),
            },
            "hit_rate": hits / (hits + misses) if (hits + misses) > 0 else 0,
            "hits": hits,
            "misses": misses,
        }

    async def benchmark_multi_layer(self, operations: int = 50000) -> dict:
        """Benchmark complete multi-layer cache system."""
        logger.info(f"Benchmarking multi-layer cache with {operations} operations")

        # Test data simulating real workload
        test_data = {
            "user_profiles": [{"user_id": i, "name": f"User_{i}", "data": "x" * 100} for i in range(1000)],
            "api_responses": [{"endpoint": f"/api/v1/data/{i}", "response": {"data": "x" * 200}} for i in range(1000)],
            "static_content": [{"path": f"/static/file_{i}.css", "content": "x" * 500} for i in range(1000)],
        }

        async def fetch_user_data(key: str):
            user_id = int(key.split(":")[1])
            return test_data["user_profiles"][user_id % 1000]

        async def fetch_api_data(key: str):
            idx = int(key.split(":")[1])
            return test_data["api_responses"][idx % 1000]

        async def fetch_static_data(key: str):
            idx = int(key.split(":")[1])
            return test_data["static_content"][idx % 1000]

        fetch_functions = {
            "user": fetch_user_data,
            "api": fetch_api_data,
            "static": fetch_static_data,
        }

        # Generate mixed workload
        operations_data = []
        for i in range(operations):
            if i % 3 == 0:
                op_type = "user"
                key = f"user:{i % 1000}"
            elif i % 3 == 1:
                op_type = "api"
                key = f"api:{i % 1000}"
            else:
                op_type = "static"
                key = f"static:{i % 1000}"

            operations_data.append((key, op_type))

        # Execute benchmark
        latencies = []
        hits = 0
        misses = 0
        start_time = time.time()

        for key, op_type in operations_data:
            op_start = time.perf_counter()
            result = await self.cache.get(key, fetch_functions[op_type])
            op_end = time.perf_counter()

            latency_ms = (op_end - op_start) * 1000
            latencies.append(latency_ms)

            if result is not None:
                hits += 1
            else:
                misses += 1

        duration = time.time() - start_time

        return {
            "benchmark_type": "multi_layer_mixed_workload",
            "operations": operations,
            "duration_sec": duration,
            "qps": operations / duration,
            "latency_ms": {
                "avg": statistics.mean(latencies),
                "p50": statistics.median(latencies),
                "p95": statistics.quantiles(latencies, n=20)[18],
                "p99": statistics.quantiles(latencies, n=100)[98],
                "min": min(latencies),
                "max": max(latencies),
            },
            "hit_rate": hits / operations,
            "hits": hits,
            "misses": misses,
            "workload_distribution": {
                "user_data": operations // 3,
                "api_responses": operations // 3,
                "static_content": operations // 3,
            },
        }

    async def benchmark_scalability(self, concurrency_levels: list[int] = [10, 50, 100, 500, 1000]) -> dict:
        """Benchmark cache performance under different concurrency levels."""
        logger.info("Running scalability benchmark")

        results = {}

        for concurrency in concurrency_levels:
            logger.info(f"Testing concurrency level: {concurrency}")

            async def worker(worker_id: int, operations: int = 1000):
                latencies = []
                for i in range(operations):
                    key = f"scale_test:{worker_id}:{i}"
                    start = time.perf_counter()
                    # Simulate cache operation
                    await self.cache.set(key, f"value_{i}", ttl=60)
                    await self.cache.get(key)
                    end = time.perf_counter()
                    latencies.append((end - start) * 1000)
                return latencies

            # Run concurrent operations
            start_time = time.time()
            tasks = [worker(i) for i in range(concurrency)]
            results_list = await asyncio.gather(*tasks)
            duration = time.time() - start_time

            # Flatten latencies
            all_latencies = [lat for worker_latencies in results_list for lat in worker_latencies]

            results[concurrency] = {
                "concurrency": concurrency,
                "total_operations": len(all_latencies),
                "duration_sec": duration,
                "qps": len(all_latencies) / duration,
                "latency_ms": {
                    "avg": statistics.mean(all_latencies),
                    "p95": statistics.quantiles(all_latencies, n=20)[18],
                    "p99": statistics.quantiles(all_latencies, n=100)[98],
                },
            }

        return results

    async def run_full_benchmark(self) -> dict:
        """Run complete benchmark suite."""
        logger.info("Starting comprehensive cache benchmark suite")

        # Initialize cache
        await self.cache.initialize()

        # Record initial system stats
        await self.record_system_stats()

        # Individual layer benchmarks
        layer_results = {}
        layers = {
            "L1": self.cache.l1_cache,
            "L2": self.cache.l2_cache,
            "L3": self.cache.l3_cache,
        }

        for layer_name, layer_instance in layers.items():
            layer_results[layer_name] = await self.benchmark_layer(layer_name, layer_instance, 5000)

        # Multi-layer benchmark
        multi_layer_result = await self.benchmark_multi_layer(25000)

        # Scalability benchmark
        scalability_results = await self.benchmark_scalability([10, 50, 100, 200])

        # Final system stats
        await self.record_system_stats()

        # Cache statistics
        cache_stats = await self.cache.get_stats()

        # Health check
        health_status = await self.cache.health_check()

        benchmark_results = {
            "timestamp": datetime.now().isoformat(),
            "benchmark_version": "1.0.0",
            "layer_benchmarks": layer_results,
            "multi_layer_benchmark": multi_layer_result,
            "scalability_benchmark": scalability_results,
            "cache_statistics": cache_stats,
            "health_status": health_status,
            "system_stats": self.system_stats,
            "summary": {
                "total_qps_achieved": multi_layer_result["qps"],
                "average_latency_ms": multi_layer_result["latency_ms"]["p95"],
                "cache_hit_rate": multi_layer_result["hit_rate"],
                "scalability_verified": scalability_results[max(scalability_results.keys())]["qps"] > 50000,
            },
        }

        # Save results
        self.save_results(benchmark_results)

        return benchmark_results

    def save_results(self, results: dict):
        """Save benchmark results to file."""
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        filename = f"cache_benchmark_results_{timestamp}.json"

        with open(filename, "w") as f:
            json.dump(results, f, indent=2, default=str)

        logger.info(f"Benchmark results saved to {filename}")

    def print_summary(self, results: dict):
        """Print benchmark summary."""
        print("\n" + "=" * 80)
        print("🚀 MULTI-LAYER CACHE BENCHMARK RESULTS")
        print("=" * 80)

        print("\n📊 OVERALL PERFORMANCE:")
        print(f"  Total Operations: {results['total_operations']:,}")
        print(f"  Duration: {results['duration_seconds']:.2f}s")
        print(f"  Overall QPS: {results['overall_qps']:.1f}")

        print("\n🔍 CACHE STATISTICS:")
        cache_stats = results["cache_statistics"]
        print(f"  Overall Hit Rate: {cache_stats['overall_hit_rate']:.1%}")
        print(f"  L1 Hit Rate: {cache_stats['layers']['L1']['hit_rate']:.1%}")
        print(f"  L2 Hit Rate: {cache_stats['layers']['L2']['hit_rate']:.1%}")

        print("\n⚡ LAYER PERFORMANCE:")
        for layer, stats in results["layer_benchmarks"].items():
            print(f"  {layer}: {stats['get_qps']:.0f} QPS, {stats['get_latency_ms']['p95']:.1f}ms P95")

        print("\n📈 SCALABILITY:")
        scale_results = results["scalability_benchmark"]
        for concurrency, stats in scale_results.items():
            print(f"  {concurrency} concurrent: {stats['qps']:.0f} QPS, {stats['latency_ms']['p95']:.1f}ms P95")

        print("\n🏥 HEALTH STATUS:")
        health = results["health_status"]
        print(f"  Overall: {health['overall']}")
        for layer, status in health["layers"].items():
            print(f"  {layer}: {status['status']} ({status.get('latency', 0):.1f}ms)")

        print("\n✅ BENCHMARK COMPLETE")
        print("=" * 80)


async def main():
    """Main benchmark execution."""
    # Initialize cache
    cache = MultiLayerCache()

    # Create benchmark instance
    benchmark = CacheBenchmark(cache)

    try:
        # Run full benchmark suite
        results = await benchmark.run_full_benchmark()

        # Print summary
        benchmark.print_summary(results)

        # Validate hyper-scale requirements
        qps_achieved = results["summary"]["total_qps_achieved"]
        latency_p95 = results["summary"]["average_latency_ms"]
        hit_rate = results["summary"]["cache_hit_rate"]

        print("\n🎯 HYPER-SCALE VALIDATION:")
        print(f"  Target QPS: 100,000+ | Achieved: {qps_achieved:.0f} {'✅' if qps_achieved >= 100000 else '❌'}")
        print(f"  Target P95 Latency: <50ms | Achieved: {latency_p95:.1f}ms {'✅' if latency_p95 < 50 else '❌'}")
        print(f"  Target Hit Rate: >85% | Achieved: {hit_rate:.1%} {'✅' if hit_rate > 0.85 else '❌'}")

        if qps_achieved >= 100000 and latency_p95 < 50 and hit_rate > 0.85:
            print("\n🎉 M5.3 ADVANCED CACHING STRATEGIES: VALIDATED FOR HYPER-SCALE!")
        else:
            print("\n⚠️  M5.3 requires optimization for full hyper-scale performance")

    finally:
        await cache.close()


if __name__ == "__main__":
    asyncio.run(main())
