import asyncio
import json
import random
import time

from aiokafka import AIOKafkaProducer


async def produce_metrics():
    """produce_metrics function."""
    producer = AIOKafkaProducer(bootstrap_servers="localhost:9092")
    await producer.start()
    try:
        while True:
            # Generate CEO/CTO/CFO metrics
            metric = {
                "type": random.choice(["REVENUE", "HEALTH", "SPEND", "SECURITY"]),
                "value": random.uniform(10.0, 1000.0),
                "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                "metadata": {"unit": "USD" if "SPEND" in metric else "SCORE"},  # noqa: F821
            }
            await producer.send_and_wait("executive-metrics", json.dumps(metric).encode("utf-8"))
            print(f"Produced: {metric}")
            await asyncio.sleep(2)
    finally:
        await producer.stop()


if __name__ == "__main__":
    asyncio.run(produce_metrics())
