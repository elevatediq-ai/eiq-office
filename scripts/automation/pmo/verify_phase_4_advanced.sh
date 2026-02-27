#!/bin/bash
# scripts/pmo/verify_phase_4_advanced.sh
# Verifies advanced OpenStack features integration: Ironic, Barbican, Freezer.
# NIST-SC-28, NIST-CP-9, NIST-CM-3

set -e

echo "🚀 [PMO] Starting Phase 4 Advanced Features Verification..."

# 1. Check docker-compose for Ironic/Barbican
if grep -q "openstack_ironic" infra/openstack/docker-compose.yml; then
    echo "✓ Ironic service found in docker-compose"
else
    echo "❌ Ironic service MISSING in docker-compose"
    exit 1
fi

if grep -q "openstack_barbican" infra/openstack/docker-compose.yml; then
    echo "✓ Barbican service found in docker-compose"
else
    echo "❌ Barbican service MISSING in docker-compose"
    exit 1
fi

# 2. Test CloudProviderFactory Integration
echo "🧪 Testing Bare Metal and Secret Management abstraction..."
python3 <<EOF
import os
import sys
sys.path.append(os.getcwd())
from libs.cloud_abstraction.cloud_provider_factory import CloudProviderFactory

try:
    # Test Bare Metal
    bm = CloudProviderFactory.get_baremetal_provider("openstack")
    nodes = bm.list_nodes()
    print(f"🔍 Found bare metal nodes: {nodes}")

    # Test Secret Management
    secrets = CloudProviderFactory.get_secret_provider("openstack")
    val = secrets.get_secret("test-key")
    print(f"🔍 Barbican secret retrieve: {val}")

    # Test Backup
    backup = CloudProviderFactory.get_backup_provider("openstack")
    b_id = backup.create_backup("vol-1", "daily-backup")
    print(f"🔍 Freezer backup created: {b_id}")

    print("✅ Advanced features abstraction layer integration PASSED")
except Exception as e:
    print(f"❌ Error during advanced features validation: {e}")
    sys.exit(1)
EOF

echo "🚀 [PMO] Phase 4 Advanced Features Verification COMPLETE."
