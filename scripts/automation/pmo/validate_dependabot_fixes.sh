#!/bin/bash
# Dependabot batch remediation validation
# NIST: [SI-2] Flaw Remediation
# Purpose: Verify security patches are applied and validated

set -e

echo "🔒 Starting Dependabot Batch Remediation Validation (#3071)"
echo "=================================================="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

cd "$REPO_ROOT"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

PASS_COUNT=0
FAIL_COUNT=0

# Test 1: Python security scanning
echo ""
echo "📋 Test 1: Python Ecosystem Validation"
if command -v pip-audit &> /dev/null; then
    echo "✅ pip-audit installed"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo "⚠️  pip-audit not installed (install it for comprehensive scanning)"
fi

# Test 2: vLLM patch verification
echo ""
echo "📋 Test 2: vLLM RCE Patch Verification"
# Use Python-based robust version check to allow 0.12.2 or higher
if python3 -c "import re; r = open('apps/ai-inference-server/requirements-vllm.txt').read(); m = re.search(r'vllm==(\d+\.\d+\.\d+)', r); v = [int(x) for x in m.group(1).split('.')]; exit(0 if v >= [0, 12, 2] else 1)" 2>/dev/null; then
    VLLM_VER=$(grep "vllm==" apps/ai-inference-server/requirements-vllm.txt | cut -d'=' -f3)
    echo "✅ vLLM version $VLLM_VER satisfies security minimum (>=0.12.2)"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo "❌ vLLM version not patched or below 0.12.2"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# Test 3: Cryptography patch verification
echo ""
echo "📋 Test 3: Cryptography Security Patch"
# Check both local requirements and root requirements/pyproject.toml
if python3 -c "import re; r = open('apps/ai-inference-server/requirements-vllm.txt').read() + open('pyproject.toml').read(); m = re.search(r'cryptography[>=]=(\d+\.\d+\.\d+)', r); v = [int(x) for x in m.group(1).split('.')]; exit(0 if v >= [46, 0, 5] else 1)" 2>/dev/null; then
    echo "✅ Cryptography satisfies security minimum (>=46.0.5)"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo "❌ Cryptography not updated to at least 46.0.5"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# Test 4: Go oauth2 patch verification
echo ""
echo "📋 Test 4: Go OAuth2 Patch Verification"
if grep -q "golang.org/x/oauth2 v0.35.0" apps/pmo-orchestrator/go.mod; then
    echo "✅ oauth2 updated to v0.35.0"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo "❌ oauth2 not updated to v0.35.0"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# Test 5: Security test availability
echo ""
echo "📋 Test 5: Security Test Suite"
test_files=("tests/test_security_vllm_rce_patch.py" "apps/pmo-orchestrator/oauth2_security_test.go")
missing=0
for file in "${test_files[@]}"; do
    if [ -f "$file" ]; then
        echo "✅ Found: $file"
    else
        echo "❌ Missing: $file"
        ((missing++))
    fi
done

if [ $missing -eq 0 ]; then
    PASS_COUNT=$((PASS_COUNT + 1))
else
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# Test 6: Go module validation (if go available)
echo ""
echo "📋 Test 6: Go Module Integrity"
if command -v go &> /dev/null; then
    cd apps/pmo-orchestrator
    if go mod verify 2>/dev/null; then
        echo "✅ Go modules verified"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "❌ Go module verification failed"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
    cd "$REPO_ROOT"
else
    echo "⚠️  Go not installed (skipping)"
fi

# Test 7: python-ecdsa mitigation check
echo ""
echo "📋 Test 7: python-ecdsa mitigation"
# Fail the validation if python-ecdsa is present (Dependabot advisory GHSA-wj6h-64fc-37mp)
if grep -q "^ecdsa==" apps/control-plane/requirements.txt; then
    echo "❌ python-ecdsa detected in apps/control-plane/requirements.txt — mitigation required (see: #3438)"
    FAIL_COUNT=$((FAIL_COUNT + 1))
else
    echo "✅ No direct python-ecdsa dependency found in control-plane manifest"
    PASS_COUNT=$((PASS_COUNT + 1))
fi

# Test 8: PyJWT Replacement (mitigates GHSA-wj6h-64fc-37mp)
echo ""
echo "📋 Test 8: PyJWT Replacement (Executive API)"
if grep -q "PyJWT" apps/executive-api/requirements.txt && ! grep -q "^python-jose" apps/executive-api/requirements.txt; then
    echo "✅ PyJWT verified and python-jose removed in executive-api"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo "❌ PyJWT missing or python-jose still present in executive-api"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# Summary
echo ""
echo "=================================================="
echo "📊 Validation Summary"
echo "=================================================="
echo -e "✅ Passed: ${GREEN}${PASS_COUNT}${NC}"
echo -e "❌ Failed: ${RED}${FAIL_COUNT}${NC}"
echo ""

if [ $FAIL_COUNT -eq 0 ]; then
    echo -e "${GREEN}✅ All Dependabot batch remediation validation checks PASSED${NC}"
    echo ""
    echo "Next Steps:"
    echo "  1. Run full test suite: pytest tests/ -v"
    echo "  2. Execute security scans: bandit -r . && snyk test"
    echo "  3. Review git log: git log --oneline | head -5"
    exit 0
else
    echo -e "${RED}❌ Some validation checks FAILED - remediation incomplete${NC}"
    echo ""
    echo "Required Actions:"
    echo "  1. Review failed checks above"
    echo "  2. Apply missing security patches"
    echo "  3. Rerun validation"
    exit 1
fi
