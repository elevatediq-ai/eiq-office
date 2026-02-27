"""🚀 Federated AI Gateway - Performance Benchmarker
Measure throughput and latency for various routing strategies.
Strategies: local-first, cost-indexed, parallel-fastest, majority-consensus.
"""

import asyncio
import statistics
import time
from enum import StrEnum

import httpx

# Config
GATEWAY_URL = "http://localhost:8096"
TOTAL_REQUESTS = 30
CONCURRENCY = 5

class Strategy(StrEnum):
    LOCAL = "local-first"
    COST = "cost-indexed"
    FASTEST = "fastest"
    MAJORITY = "majority"

async def run_benchmark_request(client, strategy: Strategy):
    start_time = time.time()
    payload = {
        "prompt": "Benchmark request for Federated AI Gateway performance validation.",
        "max_tokens": 128,
        "consensus": "single" if strategy in [Strategy.LOCAL, Strategy.COST] else strategy.value
    }

    # Overriding strategy via env or header if the API supports it,
    # but for simplicity we assume the gateway is pre-configured or uses the consensus field.
    try:
        resp = await client.post("/v1/chat/completions", json=payload, timeout=30.0)
        resp.raise_for_status()
        data = resp.json()
        latency = (time.time() - start_time) * 1000
        return {
            "latency": latency,
            "provider": data["provider"],
            "cost": data.get("cost_estimate_usd", 0.0),
            "status": "success"
        }
    except Exception as e:
        return {"status": "error", "error": str(e)}

async def run_strategy_benchmark(strategy: Strategy):
    print(f"\n📊 Starting Benchmark Strategy: {strategy.value}")

    async with httpx.AsyncClient(base_url=GATEWAY_URL) as client:
        # Check health first
        try:
            health = await client.get("/health")
            health.raise_for_status()
        except:
            print(f"❌ Gateway at {GATEWAY_URL} is UNREACHABLE. Benchmark skipped.")
            return

        tasks = []
        semaphore = asyncio.Semaphore(CONCURRENCY)

        async def sem_request():
            async with semaphore:
                return await run_benchmark_request(client, strategy)

        for _ in range(TOTAL_REQUESTS):
            tasks.append(sem_request())

        results = await asyncio.gather(*tasks)

        # Process results
        latencies = [r["latency"] for r in results if r["status"] == "success"]
        costs = [r["cost"] for r in results if r["status"] == "success"]
        providers = [r["provider"] for r in results if r["status"] == "success"]
        errors = [r for r in results if r["status"] == "error"]

        if not latencies:
            print(f"❌ All {TOTAL_REQUESTS} requests failed for {strategy.value}")
            return

        print(f"✅ Completed: {len(latencies)} success, {len(errors)} failed")
        print(f"⏱️  Avg Latency: {statistics.mean(latencies):.2f}ms")
        print(f"⏱️  P95 Latency: {statistics.quantiles(latencies, n=20)[18]:.2f}ms")
        print(f"💰 Avg Cost: ${statistics.mean(costs):.6f}")
        print(f"🏢 Provider Distribution: { {p: providers.count(p) for p in set(providers)} }")

async def main():
    print("🧠 Federated AI Gateway Performance Baseline Tool")
    print("="*50)

    # Run strategies in sequence to avoid noise
    for s in [Strategy.LOCAL, Strategy.COST, Strategy.FASTEST, Strategy.MAJORITY]:
        await run_strategy_benchmark(s)

if __name__ == "__main__":
    asyncio.run(main())
