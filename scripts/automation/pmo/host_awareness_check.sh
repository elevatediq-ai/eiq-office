#!/usr/bin/env bash
################################################################################
# ElevatedIQ Host Awareness & Pre-Flight Check
# NIST 800-53: SC-7, CM-8
# Description: Verifies the current execution host and enforces rules.
################################################################################

set -euo pipefail

# ANSI Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Host & User Definitions (NIST AC-2)
PRIMARY_USER="akushnir"
WORKSTATION_IP="192.168.168.31"
FULLSTACK_IP="192.168.168.42"
FULLSTACK_IDENTITY="akushnir@192.168.168.42"
WORKSTATION_IDENTITY="akushnir@192.168.168.31"

CURRENT_IP=$(hostname -I | awk '{print $1}')
CURRENT_USER=$(whoami)
LOCAL_HOSTNAME=$(hostname)
CURRENT_IDENTITY="${CURRENT_USER}@${CURRENT_IP}"

echo -e "${CYAN}ElevatedIQ Environment Awareness Check${NC}"
echo -e "----------------------------------------"
echo -e "${BLUE}Hostname:${NC} $LOCAL_HOSTNAME"
echo -e "${BLUE}Primary IP:${NC} $CURRENT_IP"
echo -e "${BLUE}Current User:${NC} $CURRENT_USER"
echo -e "${BLUE}Current Identity:${NC} $CURRENT_IDENTITY"
echo ""

# User Identity Validation
if [[ "$CURRENT_USER" != "$PRIMARY_USER" ]]; then
    echo -e "${YELLOW}⚠️  WARNING: Running as '$CURRENT_USER' (expected: '$PRIMARY_USER')${NC}"
    echo -e "   Ensure you have proper authorization for infrastructure operations."
    echo ""
fi

if [[ "$CURRENT_IP" == *"$WORKSTATION_IP"* ]]; then
    echo -e "${YELLOW}Detected: WORKSTATION PLANE (.31)${NC}"
    echo -e "${BLUE}Identity:${NC} $WORKSTATION_IDENTITY"
    echo -e "✅ Allowed: git, terraform plan, documentation, VS Code"
    echo -e "❌ FORBIDDEN: Docker, GPU, vLLM, Service Deployment, Pytest (Compute)"

    # Strict mode enforcement (NIST-SC-7)
    if [[ "${STRICT_WORKLOAD_ISOLATION:-false}" == "true" ]]; then
       echo -e "${RED}ERROR: Workload rejected. Target node 192.168.168.42 required for compute/services.${NC}"
       exit 1
    fi
elif [[ "$CURRENT_IP" == *"$FULLSTACK_IP"* ]]; then
    echo -e "${GREEN}Detected: FULLSTACK COMPUTE NODE (.42)${NC}"
    echo -e "${BLUE}Identity:${NC} $FULLSTACK_IDENTITY"
    echo -e "✅ Allowed: Docker, OpenStack, GPU Inference, All Services"
    echo -e "⚠️  Note: Ensure all code is committed before running workloads."
else
    echo -e "${RED}WARNING: Unknown Execution Environment!${NC}"
    echo -e "Primary IP $CURRENT_IP is not in the canonical topology."
fi

echo -e "----------------------------------------"
