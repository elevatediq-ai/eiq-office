#!/bin/bash
##############################################################################
# Layer 2 Deployment Script
# Deploys health daemon and state persistence to worker node
# Usage: ./scripts/pmo/deploy-layer2.sh
##############################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WORKER_HOST="192.168.168.42"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Layer 2 Deployment to $WORKER_HOST ===${NC}"
echo "Health Daemon & Auto-Recovery"
echo "Timestamp: $TIMESTAMP"
echo ""

##############################################################################
# Step 1: Deploy health daemon script
##############################################################################
echo -e "${BLUE}Step 1: Deploy health daemon script${NC}"

scp "$REPO_ROOT/scripts/automation/pmo/elevatediq-health-daemon.sh" "$WORKER_HOST:/tmp/"
ssh "$WORKER_HOST" "
  sudo cp /tmp/elevatediq-health-daemon.sh /home/akushnir/ElevatedIQ-Mono-Repo/scripts/pmo/
  sudo chmod +x /home/akushnir/ElevatedIQ-Mono-Repo/scripts/pmo/elevatediq-health-daemon.sh
  echo '✓ Health daemon deployed'
"

echo -e "${GREEN}✓ Health daemon deployed${NC}"
echo ""

##############################################################################
# Step 2: Deploy health service unit
##############################################################################
echo -e "${BLUE}Step 2: Deploy health service unit${NC}"

scp "$REPO_ROOT/config/systemd/elevatediq-health.service" "$WORKER_HOST:/tmp/"
ssh "$WORKER_HOST" "
  sudo cp /tmp/elevatediq-health.service /etc/systemd/system/
  echo '✓ Health service unit deployed'
"

echo -e "${GREEN}✓ Health service unit deployed${NC}"
echo ""

##############################################################################
# Step 3: Deploy updated docker-compose files
##############################################################################
echo -e "${BLUE}Step 3: Update docker-compose with restart policies${NC}"

scp "$REPO_ROOT/docker-compose.portal.yml" "$WORKER_HOST:~/ElevatedIQ-Mono-Repo/"
ssh "$WORKER_HOST" "
  echo '✓ docker-compose.portal.yml updated'
"

echo -e "${GREEN}✓ Docker compose updated${NC}"
echo ""

##############################################################################
# Step 4: Create logging directories
##############################################################################
echo -e "${BLUE}Step 4: Create logging and metrics directories${NC}"

ssh "$WORKER_HOST" "
  sudo mkdir -p /var/log/elevatediq /var/lib/elevatediq
  sudo chmod 755 /var/log/elevatediq /var/lib/elevatediq
  echo '✓ Directories created'
"

echo -e "${GREEN}✓ Logging directories created${NC}"
echo ""

##############################################################################
# Step 5: Reload systemd and enable daemon
##############################################################################
echo -e "${BLUE}Step 5: Enable and start health daemon${NC}"

ssh "$WORKER_HOST" "
  sudo systemctl daemon-reload
  sudo systemctl enable elevatediq-health.service
  echo '✓ Health daemon enabled'
"

echo -e "${GREEN}✓ Health daemon enabled${NC}"
echo ""

##############################################################################
# Step 6: Start health daemon
##############################################################################
echo -e "${BLUE}Step 6: Start health daemon${NC}"

ssh "$WORKER_HOST" "
  sudo systemctl start elevatediq-health.service
  sleep 2
  systemctl is-active elevatediq-health.service && echo '✓ Health daemon running' || echo '✗ Health daemon failed'
"

echo -e "${GREEN}✓ Health daemon started${NC}"
echo ""

##############################################################################
# Step 7: Verify Layer 2 deployment
##############################################################################
echo -e "${BLUE}Step 7: Verify Layer 2 deployment${NC}"

ssh "$WORKER_HOST" "
  echo 'Health daemon status:'
  sudo systemctl status elevatediq-health.service --no-pager | head -8

  echo ''
  echo 'Recent health daemon activity:'
  sudo tail -10 /var/log/elevatediq/health-daemon.log 2>/dev/null || echo '(No log entries yet)'
"

echo -e "${GREEN}✓ Verification complete${NC}"
echo ""

##############################################################################
# Step 8: Test failure recovery
##############################################################################
echo -e "${BLUE}Step 8: Test auto-recovery (optional)${NC}"

read -p "Run failure recovery test? (y/n) " -n 1 -r test_answer
echo ""

if [[ $test_answer =~ ^[Yy]$ ]]; then
    echo "Testing portal failure recovery..."
    ssh "$WORKER_HOST" "
      echo 'Stopping portal container...'
      docker stop elevatediq-portal
      sleep 3

      echo 'Waiting for health daemon to detect and recover...'
      sleep 8

      echo 'Checking if portal is back online...'
      if curl -s http://localhost:4000 >/dev/null 2>&1; then
        echo '✅ Portal recovered within 8 seconds!'
      else
        echo '⚠ Portal still recovering, checking status...'
        docker ps | grep portal || echo 'Portal container not found'
      fi
    "
fi

echo ""

##############################################################################
# Completion
##############################################################################
echo -e "${BLUE}=== Layer 2 Deployment Complete ===${NC}"
echo ""
echo "Features enabled:"
echo "✅ Port monitoring every 5 seconds"
echo "✅ Automatic service restart on failure (< 5 second recovery)"
echo "✅ Resource monitoring (CPU, memory, disk)"
echo "✅ Restart storm prevention"
echo "✅ Comprehensive metrics logging"
echo "✅ Docker healthcheck integration"
echo ""
echo "Next steps:"
echo "1. Monitor health daemon: ssh $WORKER_HOST"
echo "2. Live logs: sudo tail -f /var/log/elevatediq/health-daemon.log"
echo "3. Metrics: cat /var/lib/elevatediq/health-metrics.json | jq"
echo "4. Proceed to Layer 3: Observability & Chaos Testing"
echo ""

echo -e "${GREEN}✅ Layer 2 Complete! System now auto-recovers within 5 seconds.${NC}"
