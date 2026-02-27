"""Smoke test for Phase 9.1 High-Performance Governance Engine.
Verifies sub-ms parsing and evaluation logic.
"""

import os
import sys
import time
from pprint import pprint

# Add libs to path
sys.path.append(os.path.join(os.getcwd(), "libs"))

# Enable logging
import logging

from governance.fast_engine import evaluator

logging.basicConfig(level=logging.DEBUG)


def test_engine():
    """test_engine function."""
    print("🚀 Starting Governance Engine Smoke Test...")

    # 1. Test DSL Parsing
    statements = [
        'allow read if user.role == "admin" and resource.type == "storage"',
        'deny delete if context.region != "us-east-1"',
        'allow write if user.id in "123,456,789" or user.is_superuser == 1',
    ]

    parsed_rules = []
    print("\n--- Parsing Tests ---")
    for s in statements:
        start = time.perf_counter()
        parsed = evaluator.parse_statement(s)
        end = time.perf_counter()
        print(f"Parsed: '{s}'")
        print(f"Latency: {(end - start) * 1000:.4f}ms")
        parsed_rules.append(parsed)

    # 2. Test Evaluation
    context = {
        "user": {"role": "admin", "id": "123", "is_superuser": 0},
        "resource": {"type": "storage"},
        "context": {"region": "us-east-1"},
    }

    print("\n--- Evaluation Tests ---")
    for rule in parsed_rules:
        print(f"\nEvaluating Rule: {rule['action']}")
        pprint(rule["condition"])
        start = time.perf_counter()
        result = evaluator.evaluate_condition(rule["condition"], context)
        end = time.perf_counter()

        decision = rule["decision"] if result else "N/A"
        print(f"Rule: {rule['action']} -> {decision}")
        print(f"Eval Latency: {(end - start) * 1000:.4f}ms")


if __name__ == "__main__":
    test_engine()
