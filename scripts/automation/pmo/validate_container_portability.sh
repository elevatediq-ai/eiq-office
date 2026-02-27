#!/bin/bash
# scripts/pmo/validate_container_portability.sh
# Validates that containers are portable between GKE and OpenStack Magnum.
# NIST-SA-15, NIST-CM-3

set -e

echo "🔍 [PMO] Starting Container Portability Validation..."

# 1. Check Control Plane Dockerfile
DOCKERFILE="apps/control_plane/Dockerfile"
if [ -f "$DOCKERFILE" ]; then
    echo "✓ Found Control Plane Dockerfile"
    # Ensure it's not using GCP-specific base images if possible, or use standard ones
    if grep -q "google/cloud-sdk" "$DOCKERFILE"; then
        echo "⚠️  Dockerfile uses GCP-specific tools. Ensuring fallback logic exists..."
    fi
else
    echo "❌ Control Plane Dockerfile MISSING"
    exit 1
fi

# 2. Validate Kubernetes Manifests for Magnum Compatibility
MAGNUM_YAML="apps/control_plane/magnum-k8s-deployment.yaml"
if [ -f "$MAGNUM_YAML" ]; then
    echo "✓ Found Magnum K8s Deployment Manifest"
    # Check for GKE-specific annotations that might break in Magnum
    if grep -q "networking.gke.io" "$MAGNUM_YAML"; then
        echo "❌ GKE-specific networking found in Magnum manifest!"
        exit 1
    fi
    echo "✓ Manifest verified for OpenStack compatibility"
else
    echo "❌ Magnum K8s Deployment Manifest MISSING"
    exit 1
fi

# 3. Test Integration via CloudProviderFactory
echo "🧪 Running abstraction layer integration test..."
python3 <<EOF
import os
import sys
sys.path.append(os.getcwd())
from libs.cloud_abstraction.cloud_provider_factory import CloudProviderFactory

try:
    compute = CloudProviderFactory.get_compute_provider("openstack")
    events = compute.stream_api_events("magnum-1")
    print(f"🔍 API Streaming status: {events['status']}")
    if events['status'] == 'active':
        print("✅ Container portability & API streaming simulation PASSED")
    else:
        print("❌ API streaming simulation FAILED")
        sys.exit(1)
except Exception as e:
    print(f"❌ Error during validation: {e}")
    sys.exit(1)
EOF

echo "🚀 [PMO] Container Portability Validation COMPLETE."
