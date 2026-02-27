#!/usr/bin/env python3
"""🚀 Citus Cluster Performance Benchmark
M5.1: Distributed Database Clustering Validation
NIST SI-4: Information System Monitoring.

Validates 100K+ RPS throughput with distributed PostgreSQL cluster
"""

import argparse
import asyncio
import json
import statistics
import time
from datetime import datetime

import asyncpg


class CitusBenchmark:
    """CitusBenchmark class."""

    def __init__(self, host, port, user, password, database, worker_count=50):
        self.host = host
        self.port = port
        self.user = user
        self.password = password
        self.database = database
        self.worker_count = worker_count
        self.connection_pool = None

    async def init_pool(self):
        """Initialize connection pool for benchmarking."""
        self.connection_pool = await asyncpg.create_pool(
            host=self.host,
            port=self.port,
            user=self.user,
            password=self.password,
            database=self.database,
            min_size=10,
            max_size=100,
            command_timeout=30,
        )

    async def run_single_query(self, query_id):
        """Execute a single distributed query."""
        async with self.connection_pool.acquire() as conn:
            # Test distributed table query (will be routed to appropriate shard)
            await conn.execute(
                """
                INSERT INTO api_requests (user_id, endpoint, method, status_code, response_time_ms, ip_address)
                VALUES ($1, $2, $3, $4, $5, $6)
            """,
                query_id % 10000,
                f"/api/v1/users/{query_id % 1000}",
                "GET",
                200,
                50 + (query_id % 100),
                f"192.168.1.{query_id % 255}",
            )

            # Test distributed read query
            result = await conn.fetchval(
                """
                SELECT count(*) FROM api_requests
                WHERE user_id = $1 AND created_at > NOW() - INTERVAL '1 hour'
            """,
                query_id % 10000,
            )

            return result

    async def benchmark_rps(self, target_rps, duration_seconds):
        """Benchmark sustained RPS for specified duration."""
        print(f"🚀 Starting {target_rps} RPS benchmark for {duration_seconds}s...")

        start_time = time.time()
        end_time = start_time + duration_seconds
        query_count = 0
        response_times = []
        errors = 0

        async def worker():
            nonlocal query_count, errors
            query_id = 0
            while time.time() < end_time:
                try:
                    query_start = time.time()
                    await self.run_single_query(query_id)
                    query_end = time.time()

                    response_time = (query_end - query_start) * 1000  # ms
                    response_times.append(response_time)
                    query_count += 1
                    query_id += 1

                    # Rate limiting to target RPS (throttle by sleeping briefly when necessary)
                    elapsed = time.time() - start_time
                    expected_queries = elapsed * target_rps

                    if query_count > expected_queries:
                        await asyncio.sleep(0.001)  # Small delay to prevent overwhelming

                except Exception:
                    errors += 1
                    if errors % 100 == 0:
                        print(f"⚠️  {errors} errors encountered")

        # Run multiple workers
        tasks = [worker() for _ in range(self.worker_count)]
        await asyncio.gather(*tasks)

        actual_duration = time.time() - start_time
        actual_rps = query_count / actual_duration

        return {
            "target_rps": target_rps,
            "actual_rps": actual_rps,
            "total_queries": query_count,
            "duration": actual_duration,
            "errors": errors,
            "avg_response_time": statistics.mean(response_times) if response_times else 0,
            "p95_response_time": statistics.quantiles(response_times, n=20)[18] if len(response_times) > 20 else 0,
            "p99_response_time": statistics.quantiles(response_times, n=100)[98] if len(response_times) > 100 else 0,
        }

    async def benchmark_scalability(self):
        """Test scalability from 1K to 100K RPS."""
        print("📊 Testing Citus cluster scalability...")

        results = []
        test_levels = [1000, 5000, 10000, 25000, 50000, 75000, 100000]

        for rps in test_levels:
            print(f"\n🎯 Testing {rps} RPS...")
            result = await self.benchmark_rps(rps, 30)  # 30 second test
            results.append(result)

            print(
                f"actual_rps={result['actual_rps']:.2f} | "
                f"avg_resp={result['avg_response_time']:.2f}ms | "
                f"p99={result['p99_response_time']:.2f}ms | errors={result['errors']}"
            )

            # Stop if error rate is too high
            if result["total_queries"] > 0 and (result["errors"] / result["total_queries"]) > 0.1:  # >10% error rate
                print("⚠️  High error rate detected, stopping scalability test")
                break

        return results

    async def run_full_benchmark(self):
        """Run complete Citus cluster benchmark suite."""
        print("🚀 Citus Cluster Performance Benchmark [M5.1]")
        print("=" * 60)

        try:
            await self.init_pool()
            print("✅ Connected to Citus coordinator")

            # Test 1: Basic connectivity and Citus status
            async with self.connection_pool.acquire() as conn:
                worker_count = await conn.fetchval("SELECT count(*) FROM citus_get_active_worker_nodes()")
                shard_count = await conn.fetchval("SELECT count(*) FROM citus_shards")

            print(f"📊 Cluster Status: {worker_count} workers, {shard_count} shards")

            # Test 2: Scalability benchmark
            scalability_results = await self.benchmark_scalability()

            # Test 3: Sustained 100K RPS test
            print("\n🎯 Sustained 100K RPS Test (60 seconds)...")
            sustained_result = await self.benchmark_rps(100000, 60)

            # Generate report
            report = {
                "timestamp": datetime.now().isoformat(),
                "cluster_status": {"workers": worker_count, "shards": shard_count},
                "scalability_tests": scalability_results,
                "sustained_100k_test": sustained_result,
                "summary": {
                    "max_achieved_rps": max(r["actual_rps"] for r in scalability_results),
                    "target_100k_achieved": sustained_result["actual_rps"] >= 95_000,  # 95% of target
                    "avg_response_time_100k": sustained_result["avg_response_time"],
                    "error_rate_100k": (
                        sustained_result["errors"] / sustained_result["total_queries"]
                        if sustained_result["total_queries"] > 0
                        else 0
                    ),
                },
            }

            # Save results
            with open("/tmp/citus-benchmark-results.json", "w") as f:
                json.dump(report, f, indent=2)

            print("\n" + "=" * 60)
            print("📊 BENCHMARK RESULTS SUMMARY")
            print("=" * 60)
            print(f"Max Achieved RPS: {report['summary']['max_achieved_rps']:.0f}")
            print(f"100K Target Achieved: {'✅ YES' if report['summary']['target_100k_achieved'] else '❌ NO'}")
            print(f"Avg Response Time (100K RPS): {report['summary']['avg_response_time_100k']:.2f}ms")
            print(f"Error Rate (100K RPS): {report['summary']['error_rate_100k'] * 100:.2f}%")
            print("=" * 60)

            return report

        finally:
            if self.connection_pool:
                await self.connection_pool.close()


async def main():
    """Main function."""
    parser = argparse.ArgumentParser(description="Citus Cluster Performance Benchmark")
    parser.add_argument("--host", default="citus-coordinator.elevatediq.svc.cluster.local")
    parser.add_argument("--port", type=int, default=5432)
    parser.add_argument("--user", required=True)
    parser.add_argument("--password", required=True)
    parser.add_argument("--database", default="elevatediq")
    parser.add_argument("--workers", type=int, default=50)

    args = parser.parse_args()

    benchmark = CitusBenchmark(
        host=args.host,
        port=args.port,
        user=args.user,
        password=args.password,
        database=args.database,
        worker_count=args.workers,
    )

    await benchmark.run_full_benchmark()


if __name__ == "__main__":
    asyncio.run(main())
