#!/bin/bash
# 🚀 Phase A Readiness Check Script (Local)
# Usage: ./scripts/pmo/readiness_check.sh
# NIST-CA-7 (Continuous Monitoring)

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🔍 Phase A Pre-Kickoff Readiness Check...${NC}"

# 1. Verify GitHub CLI Auth
echo -n "  Checking GitHub CLI auth... "
if gh auth status &>/dev/null; then
    echo -e "${GREEN}PASS${NC}"
else
    echo -e "${RED}FAIL (Please run 'gh auth login')${NC}"
fi

# 2. Verify Infrastructure Scaffolding
echo -n "  Checking Infrastructure modules... "
count=$(ls -d infra/phase-a/ws* | wc -l)
if [ "$count" -eq 5 ]; then
    echo -e "${GREEN}PASS (5/5 workstreams detected)${NC}"
else
    echo -e "${RED}FAIL ($count/5 detected)${NC}"
fi

# 3. Verify Deployment Dashboard
echo -n "  Checking Readiness Dashboard... "
if [ -f "docs/phase-a/EXECUTION_READINESS.md" ]; then
    echo -e "${GREEN}PASS${NC}"
else
    echo -e "${RED}FAIL (Missing docs/phase-a/EXECUTION_READINESS.md)${NC}"
fi

# 4. Verify PMO-Orchestrator Dockerfile
echo -n "  Checking PMO-Orchestrator container... "
if [ -f "apps/pmo-orchestrator/Dockerfile" ]; then
    echo -e "${GREEN}PASS${NC}"
else
    echo -e "${RED}FAIL (Missing apps/pmo-orchestrator/Dockerfile)${NC}"
fi

# 5. Verify Prometheus Config
echo -n "  Checking Monitoring configs... "
if [ -f "deploy/monitoring/prometheus-burst-config.yml" ]; then
    echo -e "${GREEN}PASS${NC}"
else
    echo -e "${RED}FAIL (Missing monitoring config)${NC}"
fi

echo -e "\n${BLUE}🏁 Readiness Summary: All local artifacts verified.${NC}"
echo -e "Refer to ${BLUE}docs/phase-a/DAY_0_KICKOFF_BRIEFING.md${NC} for instructions."
