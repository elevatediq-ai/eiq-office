#!/bin/bash
# Phase A Deployment - Post-Launch Smoke Test (Verification)
# NIST Alignment: SI-4, CA-7
# Purpose: Verify that GCP/AWS FinOps resources are functional post-launch

set -e

echo "🔍 Starting Phase A Smoke Test (FinOps Inception)"

# AWS Check
echo "--- AWS WS2 Verification ---"
if aws s3 ls s3://elevatediq-cur-data/ >/dev/null 2>&1; then
    echo "✅ [PASS] CUR S3 Bucket exists and is accessible"
else
    echo "❌ [FAIL] CUR S3 Bucket not found or access denied"
fi

if aws athena get-work-group --work-group "finops_athena_workgroup" >/dev/null 2>&1; then
    echo "✅ [PASS] Athena Workgroup 'finops_athena_workgroup' active"
else
    echo "❌ [FAIL] Athena Workgroup missing"
fi

# GCP Check
echo "--- GCP WS1 Verification ---"
if gcloud billing budgets list --billing-account="012345-6789AB-CDEF01" >/dev/null 2>&1; then
    echo "✅ [PASS] GCP Budgets are configured and accessible"
else
    echo "❌ [FAIL] GCP Budgets access error"
fi

# Anomaly Engine Check
echo "--- WS3 Anomaly Engine Verification ---"
# Check if the anomaly engine service is responding (simulated endpoint)
if curl -s -f http://localhost:8080/health >/dev/null 2>&1; then
    echo "✅ [PASS] Anomaly Engine health check successful"
else
    echo "⚠️ [WARN] Anomaly Engine not reachable on localhost:8080 (check pod status)"
fi

echo "--- Verification Complete ---"
