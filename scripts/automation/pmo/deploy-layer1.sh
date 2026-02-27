#!/bin/bash
##############################################################################
# Layer 1 Deployment Script
# Deploys systemd-tmpfiles, cluster target, and service DAG to worker node
# Usage: ./scripts/pmo/deploy-layer1.sh
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

echo -e "${BLUE}=== Layer 1 Deployment to $WORKER_HOST ===${NC}"
echo "Timestamp: $TIMESTAMP"
echo ""

##############################################################################
# Step 1: Pre-deployment backup
##############################################################################
echo -e "${BLUE}Step 1: Backup existing configuration${NC}"

ssh "$WORKER_HOST" "
  mkdir -p ~/elevatediq-backup-$TIMESTAMP/{etc,config,systemd}
  [[ -f /etc/tmpfiles.d/elevatediq.conf ]] && cp /etc/tmpfiles.d/elevatediq.conf ~/elevatediq-backup-$TIMESTAMP/etc/ || true
  [[ -d /etc/systemd/system ]] && cp /etc/systemd/system/elevatediq* ~/elevatediq-backup-$TIMESTAMP/systemd/ || true
  echo 'Backup created'
"

echo -e "${GREEN}✓ Backup created${NC}"
echo ""

##############################################################################
# Step 2: Deploy tmpfiles configuration
##############################################################################
echo -e "${BLUE}Step 2: Deploy systemd-tmpfiles configuration${NC}"

scp "$REPO_ROOT/etc/tmpfiles.d/elevatediq.conf" "$WORKER_HOST:/tmp/"
ssh "$WORKER_HOST" "
  sudo cp /tmp/elevatediq.conf /etc/tmpfiles.d/
  sudo systemd-tmpfiles --create
  echo '✓ Tmpfiles deployed'
"

echo -e "${GREEN}✓ Tmpfiles deployed and created${NC}"
echo ""

##############################################################################
# Step 3: Deploy cluster target
##############################################################################
echo -e "${BLUE}Step 3: Deploy systemd cluster target${NC}"

scp "$REPO_ROOT/config/systemd/elevatediq-cluster.target" "$WORKER_HOST:/tmp/"
ssh "$WORKER_HOST" "
  sudo cp /tmp/elevatediq-cluster.target /etc/systemd/system/
  echo '✓ Cluster target deployed'
"

echo -e "${GREEN}✓ Cluster target deployed${NC}"
echo ""

##############################################################################
# Step 4: Deploy updated service files
##############################################################################
echo -e "${BLUE}Step 4: Deploy updated service files${NC}"

for service in pgbouncer.service elevatediq-web.service; do
    echo "Deploying $service..."
    scp "$REPO_ROOT/config/systemd/$service" "$WORKER_HOST:/tmp/"
    ssh "$WORKER_HOST" "
        sudo cp /tmp/$service /etc/systemd/system/
        echo '✓ $service deployed'
    "
done

echo -e "${GREEN}✓ Service files deployed${NC}"
echo ""

##############################################################################
# Step 5: Reload systemd
##############################################################################
echo -e "${BLUE}Step 5: Reload systemd daemon${NC}"

ssh "$WORKER_HOST" "
  sudo systemctl daemon-reload
  echo '✓ Systemd daemon reloaded'
"

echo -e "${GREEN}✓ Systemd reloaded${NC}"
echo ""

##############################################################################
# Step 6: Enable services
##############################################################################
echo -e "${BLUE}Step 6: Enable services for auto-start${NC}"

ssh "$WORKER_HOST" "
  sudo systemctl enable elevatediq-cluster.target
  sudo systemctl enable pgbouncer.service
  sudo systemctl enable elevatediq-web.service
  echo '✓ All services enabled'
"

echo -e "${GREEN}✓ Services enabled for auto-start${NC}"
echo ""

##############################################################################
# Step 7: Restart services
##############################################################################
echo -e "${BLUE}Step 7: Restart services with new configuration${NC}"

ssh "$WORKER_HOST" "
  echo 'Stopping services...'
  sudo systemctl stop elevatediq-web.service 2>/dev/null || true
  sudo systemctl stop pgbouncer.service 2>/dev/null || true
  sleep 3

  echo 'Starting services in correct order...'
  sudo systemctl start elevatediq-cluster.target
  sleep 5

  # Give services time to fully start
  sleep 10

  echo '✓ Services restarted'
"

echo -e "${GREEN}✓ Services restarted${NC}"
echo ""

##############################################################################
# Step 8: Verify deployment
##############################################################################
echo -e "${BLUE}Step 8: Verify Layer 1 deployment${NC}"

echo "Checking service status..."
ssh "$WORKER_HOST" "
  echo 'Cluster target:'
  systemctl is-active elevatediq-cluster.target || echo 'Not active'

  echo 'Pgbouncer:'
  systemctl is-active pgbouncer.service || echo 'Not active'

  echo 'ElevatedIQ-web:'
  systemctl is-active elevatediq-web.service || echo 'Not active'

  echo ''
  echo 'Running containers:'
  docker ps --format 'table {{.Names}}\t{{.Status}}' | grep -E 'elevatediq|intelligent' | head -3 || echo 'No containers'

  echo ''
  echo 'Port status:'
  nc -z 127.0.0.1 6432 && echo '✓ pgbouncer (6432) listening' || echo '✗ pgbouncer not listening'
  nc -z 127.0.0.1 4000 && echo '✓ portal (4000) listening' || echo '✗ portal not listening'
"

echo -e "${GREEN}✓ Verification complete${NC}"
echo ""

##############################################################################
# Step 9: Deploy test script
##############################################################################
echo -e "${BLUE}Step 9: Deploy test script${NC}"

scp "$REPO_ROOT/scripts/pmo/test-systemd-dag.sh" "$WORKER_HOST:~/test-systemd-dag.sh"
ssh "$WORKER_HOST" "chmod +x ~/test-systemd-dag.sh && echo '✓ Test script deployed'"

echo -e "${GREEN}✓ Test script deployed${NC}"
echo ""

##############################################################################
# Completion
##############################################################################
echo -e "${BLUE}=== Layer 1 Deployment Complete ===${NC}"
echo ""
echo "Next steps:"
echo "1. SSH to worker: ssh $WORKER_HOST"
echo "2. Run tests: ~/test-systemd-dag.sh"
echo "3. Review logs: sudo journalctl -u pgbouncer.service -f"
echo "4. Schedule reboot test: sudo reboot"
echo ""
echo "Backup location: ~/elevatediq-backup-$TIMESTAMP"
echo ""

echo -e "${GREEN}✅ Layer 1 Ready! Services will auto-recover on reboot.${NC}"
