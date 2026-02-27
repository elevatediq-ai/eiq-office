#!/bin/bash
##############################################################################
# ElevatedIQ Worker Node Post-Reboot Recovery Script
# Purpose: Recover all failed services after system reboot
# Target: 192.168.168.42 (dev-elevatediq-2)
# Run: ./scripts/pmo/worker-recovery.sh
##############################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SYSTEMD_CONFIG_DIR="$REPO_ROOT/config/systemd"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="/var/log/elevatediq-recovery-$TIMESTAMP.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== ElevatedIQ Worker Recovery Script ===${NC}" | tee -a "$LOG_FILE"
echo "Started: $(date)" | tee -a "$LOG_FILE"
echo "Log: $LOG_FILE" | tee -a "$LOG_FILE"

##############################################################################
# Step 1: Verify we're on the correct host
##############################################################################
HOSTNAME=$(hostname -s)
IP_ADDR=$(hostname -I | awk '{print $1}')

if [[ "$IP_ADDR" != "192.168.168.42" ]]; then
    echo -e "${RED}ERROR: This script must run on 192.168.168.42 (worker node)${NC}" | tee -a "$LOG_FILE"
    echo "Current IP: $IP_ADDR" | tee -a "$LOG_FILE"
    exit 1
fi

echo -e "${GREEN}✓ Running on correct host: $HOSTNAME ($IP_ADDR)${NC}" | tee -a "$LOG_FILE"

##############################################################################
# Step 2: Check systemd service status
##############################################################################
echo -e "\n${BLUE}--- Checking Service Status ---${NC}" | tee -a "$LOG_FILE"

systemctl list-units --type=service --state=failed 2>&1 | tee -a "$LOG_FILE"

##############################################################################
# Step 3: Fix pgbouncer runtime directory
##############################################################################
echo -e "\n${BLUE}--- Fixing pgbouncer runtime directory ---${NC}" | tee -a "$LOG_FILE"

if ! [[ -d /var/run/pgbouncer ]]; then
    mkdir -p /var/run/pgbouncer
    chmod 755 /var/run/pgbouncer
    chown postgres:postgres /var/run/pgbouncer
    echo "✓ Created /var/run/pgbouncer" | tee -a "$LOG_FILE"
else
    echo "✓ /var/run/pgbouncer already exists" | tee -a "$LOG_FILE"
fi

##############################################################################
# Step 4: Verify host-forward nginx config
##############################################################################
echo -e "\n${BLUE}--- Checking host-forward nginx config ---${NC}" | tee -a "$LOG_FILE"

if [[ -f /opt/host-forward/nginx-proxy.conf ]]; then
    echo "✓ nginx config exists" | tee -a "$LOG_FILE"
else
    mkdir -p /opt/host-forward
    # Create minimal nginx proxy config if missing
    cat > /opt/host-forward/nginx-proxy.conf <<'EOF'
upstream portal {
    server 127.0.0.1:4000;
}

upstream marketing {
    server 127.0.0.1:4001;
}

upstream api {
    server 127.0.0.1:8000;
}

server {
    listen 80 default_server;
    server_name _;

    location / {
        proxy_pass http://portal;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /api/ {
        proxy_pass http://api/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }

    location /marketing/ {
        proxy_pass http://marketing/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
EOF
    echo "✓ Created nginx proxy config" | tee -a "$LOG_FILE"
fi

##############################################################################
# Step 5: Deploy updated systemd service files
##############################################################################
echo -e "\n${BLUE}--- Deploying systemd service files ---${NC}" | tee -a "$LOG_FILE"

if [[ -d "$SYSTEMD_CONFIG_DIR" ]]; then
    for service in elevatediq-web.service pgbouncer.service host-forward.service; do
        SRC="$SYSTEMD_CONFIG_DIR/$service"
        DEST="/etc/systemd/system/$service"

        if [[ -f "$SRC" ]]; then
            sudo cp "$SRC" "$DEST"
            echo "✓ Deployed $service" | tee -a "$LOG_FILE"
        else
            echo "⚠ Warning: $SRC not found" | tee -a "$LOG_FILE"
        fi
    done

    # Reload systemd daemon
    sudo systemctl daemon-reload
    echo "✓ Systemd daemon reloaded" | tee -a "$LOG_FILE"
else
    echo -e "${YELLOW}⚠ Warning: $SYSTEMD_CONFIG_DIR not found${NC}" | tee -a "$LOG_FILE"
fi

##############################################################################
# Step 6: Stop failed services and clean up
##############################################################################
echo -e "\n${BLUE}--- Stopping and cleaning failed services ---${NC}" | tee -a "$LOG_FILE"

for service in elevatediq-web pgbouncer host-forward; do
    echo "Stopping $service..." | tee -a "$LOG_FILE"
    sudo systemctl stop "$service.service" 2>/dev/null || true
done

# Clean up stale docker containers
echo "Cleaning docker containers..." | tee -a "$LOG_FILE"
docker rm -f elevatediq-portal 2>/dev/null || true
docker rm -f elevatediq-marketing 2>/dev/null || true
docker rm -f host-forward-nginx 2>/dev/null || true
docker system prune -f --filter "until=24h" 2>/dev/null || true

##############################################################################
# Step 7: Restart services in correct order
##############################################################################
echo -e "\n${BLUE}--- Restarting services (correct order) ---${NC}" | tee -a "$LOG_FILE"

# Order: pgbouncer → elevatediq-web → host-forward
for service in pgbouncer.service elevatediq-web.service host-forward.service; do
    echo "Starting $service..." | tee -a "$LOG_FILE"
    sudo systemctl start "$service" 2>&1 | tee -a "$LOG_FILE"
    sleep 3

    STATUS=$(sudo systemctl is-active "$service" 2>&1)
    if [[ "$STATUS" == "active" ]]; then
        echo -e "${GREEN}✓ $service is ACTIVE${NC}" | tee -a "$LOG_FILE"
    else
        echo -e "${YELLOW}⚠ $service status: $STATUS${NC}" | tee -a "$LOG_FILE"
        echo "Details:" | tee -a "$LOG_FILE"
        sudo systemctl status "$service" 2>&1 | tail -20 | tee -a "$LOG_FILE"
    fi
done

##############################################################################
# Step 8: Enable services for auto-start
##############################################################################
echo -e "\n${BLUE}--- Enabling services for auto-start ---${NC}" | tee -a "$LOG_FILE"

for service in pgbouncer.service elevatediq-web.service host-forward.service; do
    sudo systemctl enable "$service"
    echo "✓ $service enabled" | tee -a "$LOG_FILE"
done

##############################################################################
# Step 9: Verify all services
##############################################################################
echo -e "\n${BLUE}--- Final Status Check ---${NC}" | tee -a "$LOG_FILE"

failed_count=$(systemctl list-units --type=service --state=failed --no-legend 2>&1 | wc -l)

if [[ $failed_count -eq 0 ]]; then
    echo -e "${GREEN}✓ All services recovered successfully!${NC}" | tee -a "$LOG_FILE"
else
    echo -e "${YELLOW}⚠ Some services still in failed state:${NC}" | tee -a "$LOG_FILE"
    systemctl list-units --type=service --state=failed 2>&1 | tee -a "$LOG_FILE"
fi

# Show running docker containers
echo -e "\n${BLUE}--- Docker Container Status ---${NC}" | tee -a "$LOG_FILE"
docker ps --format "table {{.Names}}\t{{.Status}}" 2>&1 | tee -a "$LOG_FILE"

##############################################################################
# Step 10: Create recovery summary
##############################################################################
echo -e "\n${BLUE}=== Recovery Complete ===${NC}" | tee -a "$LOG_FILE"
echo "Finished: $(date)" | tee -a "$LOG_FILE"
echo -e "\nNext steps:" | tee -a "$LOG_FILE"
echo "1. Monitor logs: sudo journalctl -u elevatediq-web -f" | tee -a "$LOG_FILE"
echo "2. Check health: curl http://localhost" | tee -a "$LOG_FILE"
echo "3. View full log: cat $LOG_FILE" | tee -a "$LOG_FILE"

echo -e "\n${GREEN}Recovery script completed. Check log for details.${NC}"
cat "$LOG_FILE" | tail -10

exit 0
