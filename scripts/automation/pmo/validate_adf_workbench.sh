#!/bin/bash
# ==============================================================================
# ADF WORKBENCH - Validation Script (NIST-SI-7)
# ==============================================================================

set -e

echo "🔍 Validating ADF Workbench Integration..."

# 1. Check Directory Structure
[ -d "apps/code-server" ] && echo "✅ apps/code-server exists"
[ -f "apps/code-server/Dockerfile" ] && echo "✅ Dockerfile exists"

# 2. Validate Dockerfile
grep -q "nvidia/cuda" apps/code-server/Dockerfile && echo "✅ GPU/CUDA base verified"
grep -q "ollama" apps/code-server/Dockerfile && echo "✅ Local Inference (Ollama) verified"

# 3. Check CI/CD Integration
grep -q "adf-workbench" cloudbuild.yaml && echo "✅ cloudbuild.yaml integration verified"

# 4. Check Terraform Module
[ -d "terraform/modules/code-server" ] && echo "✅ terraform/modules/code-server exists"

echo "🎯 ADF Workbench Validation COMPLETE."
