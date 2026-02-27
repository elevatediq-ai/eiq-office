#!/bin/bash
# 💊 10X Self-Healing Enforcer
# Part of ElevatedIQ 10X Governance Strategy
# NIST Controls: CM-9, SI-2

echo "🚀 Starting Self-Healing Governance Enforcer..."

# 1. Run Autonomous Remediation Agent (AGRA)
echo "🔍 Scanning for architectural drift..."
python3 scripts/pmo/enhancements/04_autonomous_remediation.py

# 2. Update Governance Debt Measurement
echo "📊 Updating compliance scorecard & profiles..."
python3 scripts/pmo/enhancements/07_compliance_debt_tracker.py > /dev/null
python3 scripts/pmo/enhancements/08_developer_profiles.py > /dev/null

# 3. Regenerate Executive Dashboard
echo "🏆 Updating Executive Dashboard..."
python3 scripts/pmo/enhancements/10_executive_dashboard.py

echo "✅ Self-Healing Cycle Complete."
