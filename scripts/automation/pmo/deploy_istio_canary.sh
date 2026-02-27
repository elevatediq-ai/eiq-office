#!/bin/bash
# 🚀 Phase 6: Istio Canary Deployment
# NIST-SC-7 | NIST-SI-4

set -e

NAMESPACE="hub-system"
CANARY_FILE="apps/hub-core/k8s/service-mesh/canary-virtualservice.yaml"

echo "🌐 Deploying Istio Canary Routing (95/5 split)..."

# 1. Label namespace for Istio injection
kubectl label namespace $NAMESPACE istio-injection=enabled --overwrite

# 2. Deploy Canary Service Mesh manifests
kubectl apply -f $CANARY_FILE -n $NAMESPACE

# 3. Verify deployment status
echo "🔍 Verifying Istio VirtualServices..."
kubectl get virtualservice -n $NAMESPACE

echo "✅ Canary Routing deployed successfully."
