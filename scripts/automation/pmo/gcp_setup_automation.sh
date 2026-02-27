#!/bin/bash
# Dedicated Phase 4: Google OAuth Setup & Automation
# NIST Aligned (IA-2, AC-2, AU-2)

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}====================================================${NC}"
echo -e "${BLUE}  ElevatedIQ Phase 4: Google OAuth Setup Assistant   ${NC}"
echo -e "${BLUE}====================================================${NC}\n"

# Step 1: Check prerequisites
echo -e "${YELLOW}[1/4] Checking environment prerequisites...${NC}"
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}✗ python3 is required but not installed.${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Prerequisites met.${NC}"

# Step 2: Run Python Validator
echo -e "${YELLOW}[2/4] Validating current configuration...${NC}"
if [ -f "scripts/pmo/gcp_oauth_validator.py" ]; then
    python3 scripts/pmo/gcp_oauth_validator.py
else
    echo -e "${RED}✗ Validator script missing: scripts/pmo/gcp_oauth_validator.py${NC}"
    exit 1
fi

# Step 3: Check Backend Connection
echo -e "${YELLOW}[3/4] Verifying Backend OAuth Provider Initialization...${NC}"
# We check if the environment variables are correctly picked up by the app
# By running a small python snippet to import the config
export PYTHONPATH=$PYTHONPATH:$(pwd)/apps/control_plane/src
if python3 -c "from control_plane.oauth2_provider import oauth_config; print(f'Configured Client ID: {oauth_config.client_id[:10]}...'); exit(0 if oauth_config.client_id != 'your-client-id.apps.googleusercontent.com' else 1)" &> /dev/null; then
    echo -e "${GREEN}✓ Backend successfully initialized with user credentials.${NC}"
else
    echo -e "${RED}✗ Backend is still using placeholder credentials.${NC}"
    echo -e "${YELLOW}Please update config/.env with your Google OAuth details.${NC}"
fi

# Step 4: Final Security Audit Setup
echo -e "${YELLOW}[4/4] Preparing NIST Security Audit logs...${NC}"
mkdir -p apps/logs/oauth-audit
touch apps/logs/oauth-audit/access.log
chmod 600 apps/logs/oauth-audit/access.log
echo -e "${GREEN}✓ NIST 800-53 (AU-2) audit logs initialized.${NC}"

echo -e "\n${GREEN}====================================================${NC}"
echo -e "${GREEN}   PHASE 4.1 SETUP COMPLETE - READY FOR TESTS      ${NC}"
echo -e "${GREEN}====================================================${NC}"
echo -e "Next Action: Run 'npm run test:e2e' in front_end to verify flow."
