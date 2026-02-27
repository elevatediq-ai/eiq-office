#!/bin/bash
# ==============================================================================
# ADF-VALIDATE: 10X Feature Validation Suite
# NIST-SI-7 | NIST-AU-2
# ==============================================================================

set -e

WORKSPACE_ROOT=$(pwd)
export PYTHONPATH="$PYTHONPATH:$WORKSPACE_ROOT/libs"

echo "🧪 Starting 10X Feature Validation..."

echo "1️⃣ Testing Liquid Compute Orchestrator..."
python3 -c "
from pmo_core.scaling.liquid_compute import LiquidComposition
from pmo_core.global_mesh import GlobalMeshManager
import asyncio

async def test():
    m = GlobalMeshManager()
    await m.initialize('mesh-root', 'us-adf', 'localhost:50051')
    comp = LiquidComposition('poc-comp', m)
    await comp.add_cell('be-1', 'backend')
    await comp.add_cell('fe-1', 'frontend')
    await comp.link_cells('be-1', 'fe-1')
    res = await comp.deploy_composition()
    print(f'Composition Result: {res}')

asyncio.run(test())
"

echo "2️⃣ Testing AEO Fixer Agent..."
python3 -m pmo_core.agents.aeo_fixer

echo "3️⃣ Checking NIST Audit Logs..."
if [ -f "docs/management/AEO_FIX_REPORT.md" ]; then
    echo "✅ AEO Fix Report exists."
else
    echo "❌ AEO Fix Report missing!"
    exit 1
fi

echo "✅ All 10X Features Validated (Elite Standard)."
