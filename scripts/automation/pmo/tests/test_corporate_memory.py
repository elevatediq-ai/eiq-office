import os
import sys
import unittest

# Add libs to path
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "../../../libs")))

from pmo_core.corporate_memory import CorporateMemory


class TestCorporateMemory(unittest.TestCase):
    def setUp(self):
        self.memory = CorporateMemory()
        # Seed some common infrastructure failures
        self.memory.learn(
            "INC-001",
            "OOMKilled OOM error on pod 'hub-core-api' due to memory leak in billing service",
            "Increase memory limits to 2Gi and apply leak fix #442",
        )
        self.memory.learn(
            "INC-002",
            "GCP Quota exceeded for 'compute.googleapis.com/instances' in region us-central1",
            "Request quota increase or shift workloads to us-east1",
        )
        self.memory.learn(
            "INC-003",
            "Redis connection timeout: pool exhausted for 'cache-cluster-01'",
            "Increase Redis max-connections and tune connection pooling in client",
        )

    def test_semantic_match_oom(self):
        # Query with similar but not identical text
        query = "Container was terminated with OOM error in billing service"
        suggestions = self.memory.suggest_resolutions(query)

        self.assertTrue(len(suggestions) > 0)
        self.assertEqual(suggestions[0]["incident_id"], "INC-001")
        self.assertIn("Increase memory limits", suggestions[0]["resolution"])
        print(f"✅ OOM Match Score: {suggestions[0]['score']}")

    def test_semantic_match_redis(self):
        query = "Timeout connecting to Redis cache, connections full"
        suggestions = self.memory.suggest_resolutions(query)

        self.assertTrue(len(suggestions) > 0)
        self.assertEqual(suggestions[0]["incident_id"], "INC-003")
        print(f"✅ Redis Match Score: {suggestions[0]['score']}")

    def test_no_match(self):
        query = "Office coffee machine is broken"
        suggestions = self.memory.suggest_resolutions(query, threshold=0.8)
        self.assertEqual(len(suggestions), 0)

    def test_stats(self):
        stats = self.memory.get_stats()
        self.assertEqual(stats["total_incidents_remembered"], 3)
        self.assertTrue(stats["ml_active"])


if __name__ == "__main__":
    unittest.main()
