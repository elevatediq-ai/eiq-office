import asyncio
import datetime
import json
import os
import random

from aiokafka import AIOKafkaProducer

KAFKA_BOOTSTRAP_SERVERS = os.getenv("KAFKA_BOOTSTRAP_SERVERS", "localhost:9092")
TOPIC = "executive-metrics"


async def produce_mock_metrics():
    """produce_mock_metrics function."""
    producer = AIOKafkaProducer(bootstrap_servers=KAFKA_BOOTSTRAP_SERVERS)
    await producer.start()
    try:
        while True:
            # Generate various metrics
            timestamp = datetime.datetime.utcnow().isoformat()
            metrics = [
                {
                    "metric": "REVENUE",
                    "value": 1500000 + random.uniform(-10000, 10000),
                    "timestamp": timestamp,
                },
                {
                    "metric": "RISK",
                    "value": 0.15 + random.uniform(-0.01, 0.01),
                    "timestamp": timestamp,
                },
                {
                    "metric": "HEALTH",
                    "value": 0.999 + random.uniform(-0.005, 0.005),
                    "timestamp": timestamp,
                },
                {
                    "metric": "BURN",
                    "value": 450000 + random.uniform(-5000, 5000),
                    "timestamp": timestamp,
                },
            ]

            for m in metrics:
                await producer.send_and_wait(TOPIC, json.dumps(m).encode("utf-8"))
                print(f"Sent Metric: {m}")

            # Periodically simulate an incident
            if random.random() < 0.1:  # 10% chance
                incident = {
                    "type": "INCIDENT",
                    "title": random.choice(
                        [
                            "GKE Node Outage",
                            "Kafka Latency Spike",
                            "Auth Service Timeout",
                        ]
                    ),
                    "severity": random.choice(["CRITICAL", "HIGH", "MEDIUM"]),
                    "timestamp": timestamp,
                }
                await producer.send_and_wait(TOPIC, json.dumps(incident).encode("utf-8"))
                print(f"Sent Incident: {incident}")

            await asyncio.sleep(5)  # Every 5 seconds
    finally:
        await producer.stop()


if __name__ == "__main__":
    import os

    asyncio.run(produce_mock_metrics())
