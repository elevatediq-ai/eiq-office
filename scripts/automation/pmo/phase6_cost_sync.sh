#!/bin/bash
# NIST-AU-2 | FinOps Multi-Cloud Cost Sync
echo "🚀 Initializing Multi-Cloud Cost Aggregator Sync..."
curl -s -X GET "http://localhost:8000/api/v1/costs/multi-cloud" -H "X-API-KEY: $COST_API_KEY" | jq .
echo "✅ Mult-Cloud Spend Aggregated."
