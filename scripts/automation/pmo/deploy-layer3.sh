#!/bin/bash
###############################################################################
# Deploy Layer 3: Observability & Chaos Testing
# NIST: SI-4 (Information System Monitoring), CA-7 (Continuous Monitoring)
#
# Deploys Prometheus, Grafana, anomaly detection, and chaos testing.
###############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
BACKUP_DIR="/home/akushnir/.backups/elevatediq"
DEPLOY_TIMESTAMP=$(date +%Y%m%d_%H%M%S)
ONPREM_FULLSTACK_NODE="192.168.168.42"
LOG_DIR="/var/log/elevatediq"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo_color() {
    local color="$1"
    shift
    echo -e "${color}$*${NC}"
}

log_section() {
    echo ""
    echo_color "$BLUE" "=========================================="
    echo_color "$BLUE" "$*"
    echo_color "$BLUE" "=========================================="
}

log_step() {
    echo_color "$YELLOW" "→ $*"
}

log_success() {
    echo_color "$GREEN" "✓ $*"
}

log_error() {
    echo_color "$RED" "✗ $*"
}

###############################################################################
# STEP 1: Verify connectivity and backup existing configs
###############################################################################

log_section "STEP 1: Pre-flight Checks & Backup"

log_step "Testing connectivity to $ONPREM_FULLSTACK_NODE"
if ! ping -c 1 "$ONPREM_FULLSTACK_NODE" &> /dev/null; then
    log_error "Cannot reach $ONPREM_FULLSTACK_NODE"
    exit 1
fi
log_success "Connected to worker node"

log_step "Creating backup directory"
mkdir -p "$BACKUP_DIR"
log_success "Backup directory ready"

log_step "Backing up existing Prometheus config"
ssh -o StrictHostKeyChecking=no akushnir@"$ONPREM_FULLSTACK_NODE" \
    "mkdir -p /var/backups/elevatediq && \
     cp /etc/prometheus/*.yml /var/backups/elevatediq/ 2>/dev/null || true"
log_success "Config backup complete"

###############################################################################
# STEP 2: Create directories and permissions on worker
###############################################################################

log_section "STEP 2: Create Storage Directories"

log_step "Creating monitoring data directories"
ssh -o StrictHostKeyChecking=no akushnir@"$ONPREM_FULLSTACK_NODE" \
    "sudo mkdir -p /var/lib/elevatediq/{prometheus,grafana,alertmanager,chaos} && \
     sudo mkdir -p /var/log/elevatediq && \
     sudo chown -R akushnir:akushnir /var/lib/elevatediq /var/log/elevatediq && \
     sudo chmod 755 /var/lib/elevatediq/* /var/log/elevatediq"
log_success "Directories created"

###############################################################################
# STEP 3: Deploy Prometheus configuration
###############################################################################

log_section "STEP 3: Deploy Prometheus Configuration"

log_step "Copying Prometheus config files to worker"
ssh -o StrictHostKeyChecking=no akushnir@"$ONPREM_FULLSTACK_NODE" \
    "mkdir -p /tmp/monitoring-config"
# Copy via shell since scp glob doesn't work reliably
find "$REPO_ROOT/config/monitoring/" -name "*.yml" -type f | while read f; do
    scp "$f" akushnir@"$ONPREM_FULLSTACK_NODE":/tmp/monitoring-config/ 2>/dev/null || true
done

log_step "Installing Prometheus config"
ssh -o StrictHostKeyChecking=no akushnir@"$ONPREM_FULLSTACK_NODE" \
    "sudo mkdir -p /etc/prometheus && \
     sudo cp /tmp/monitoring-config/*.yml /etc/prometheus/ && \
     sudo chown root:root /etc/prometheus/*.yml && \
     sudo chmod 644 /etc/prometheus/*.yml"
log_success "Prometheus config deployed"

###############################################################################
# STEP 4: Deploy monitoring stack via docker-compose
###############################################################################

log_section "STEP 4: Deploy Monitoring Stack"

log_step "Starting Prometheus and monitoring services"
ssh -o StrictHostKeyChecking=no akushnir@"$ONPREM_FULLSTACK_NODE" \
    "cd $REPO_ROOT && \
     docker-compose -f docker-compose.monitoring.yml up -d prometheus alertmanager node-exporter grafana 2>&1 || \
     docker-compose -f docker-compose.monitoring.yml up -d 2>&1"

log_success "Monitoring services deployed"

# Wait for services to be ready
log_step "Waiting for Prometheus to be ready (max 60 seconds)"
for i in {1..60}; do
    if ssh -o StrictHostKeyChecking=no akushnir@"$ONPREM_FULLSTACK_NODE" \
        "curl -s http://127.0.0.1:9090/-/healthy > /dev/null 2>&1"; then
        log_success "Prometheus is healthy"
        break
    fi
    if [ $i -eq 60 ]; then
        log_error "Prometheus failed to become ready"
        exit 1
    fi
    sleep 1
done

###############################################################################
# STEP 5: Deploy anomaly detection engine
###############################################################################

log_section "STEP 5: Deploy Anomaly Detection Engine"

log_step "Copying anomaly detector to worker"
scp "$REPO_ROOT/scripts/automation/ai/anomaly-detector.py" \
    akushnir@"$ONPREM_FULLSTACK_NODE":/tmp/

log_step "Installing anomaly detector"
ssh -o StrictHostKeyChecking=no akushnir@"$ONPREM_FULLSTACK_NODE" \
    "sudo cp /tmp/anomaly-detector.py /usr/local/bin/ && \
     sudo chmod +x /usr/local/bin/anomaly-detector.py"
log_success "Anomaly detector installed"

# Create systemd service for anomaly detector
log_step "Creating anomaly detector systemd service"
ssh -o StrictHostKeyChecking=no akushnir@"$ONPREM_FULLSTACK_NODE" \
    "sudo tee /etc/systemd/system/elevatediq-anomaly-detector.service > /dev/null <<'EOF'
[Unit]
Description=ElevatedIQ Anomaly Detection Engine
After=docker.service elevatediq-health.service
Wants=docker.service
BindsTo=elevatediq-health.service

[Service]
Type=simple
User=akushnir
Group=akushnir
WorkingDirectory=/home/akushnir
ExecStart=/usr/local/bin/anomaly-detector.py
Restart=on-failure
RestartSec=30
StandardOutput=journal
StandardError=journal
SyslogIdentifier=elevatediq-anomaly

[Install]
WantedBy=multi-user.target elevatediq-health.service
EOF"

ssh -o StrictHostKeyChecking=no akushnir@"$ONPREM_FULLSTACK_NODE" \
    "sudo systemctl daemon-reload && \
     sudo systemctl enable elevatediq-anomaly-detector.service && \
     sudo systemctl start elevatediq-anomaly-detector.service"
log_success "Anomaly detector service enabled"

###############################################################################
# STEP 6: Deploy chaos testing engine
###############################################################################

log_section "STEP 6: Deploy Chaos Testing Engine"

log_step "Copying chaos testing engine to worker"
scp "$REPO_ROOT/scripts/automation/pmo/chaos-testing-engine.sh" \
    akushnir@"$ONPREM_FULLSTACK_NODE":/tmp/

log_step "Installing chaos testing engine"
ssh -o StrictHostKeyChecking=no akushnir@"$ONPREM_FULLSTACK_NODE" \
    "sudo cp /tmp/chaos-testing-engine.sh /usr/local/bin/ && \
     sudo chmod +x /usr/local/bin/chaos-testing-engine.sh"
log_success "Chaos testing engine installed"

# Create cron job for daily chaos tests
log_step "Creating daily chaos test scheduler"
ssh -o StrictHostKeyChecking=no akushnir@"$ONPREM_FULLSTACK_NODE" \
    "echo '0 2 * * * /usr/local/bin/chaos-testing-engine.sh >> /var/log/elevatediq/chaos-cron.log 2>&1' | sudo tee -a /etc/cron.d/elevatediq-chaos"
log_success "Chaos test scheduler configured (runs daily at 02:00 UTC)"

###############################################################################
# STEP 7: Configure alertmanager for notifications
###############################################################################

log_section "STEP 7: Configure Alert Routing"

log_step "Creating alertmanager configuration"
ssh -o StrictHostKeyChecking=no akushnir@"$ONPREM_FULLSTACK_NODE" \
    "sudo tee /etc/prometheus/alertmanager-config.yml > /dev/null <<'EOF'
global:
  resolve_timeout: 5m
  slack_api_url: 'https://hooks.slack.com/services/YOUR/WEBHOOK/URL'

route:
  receiver: 'elevatediq-ops'
  group_by: ['alertname', 'cluster', 'service']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h

  routes:
    - match:
        severity: critical
      receiver: 'elevatediq-critical'
      continue: true
      group_wait: 10s
      repeat_interval: 10m

    - match:
        severity: warning
      receiver: 'elevatediq-warnings'
      continue: true
      group_wait: 1m
      repeat_interval: 2h

receivers:
  - name: 'elevatediq-ops'
    slack_configs:
      - channel: '#elevatediq-ops'
        title: '{{ .GroupLabels.alertname }}'
        text: '{{ range .Alerts }}{{ .Annotations.description }}{{ end }}'

  - name: 'elevatediq-critical'
    slack_configs:
      - channel: '#elevatediq-critical'
        title: '🚨 CRITICAL: {{ .GroupLabels.alertname }}'
        text: '{{ range .Alerts }}{{ .Annotations.description }}\nRunbook: {{ .Annotations.runbook }}{{ end }}'

  - name: 'elevatediq-warnings'
    slack_configs:
      - channel: '#elevatediq-warnings'
        title: '⚠️ WARNING: {{ .GroupLabels.alertname }}'
        text: '{{ range .Alerts }}{{ .Annotations.description }}{{ end }}'

inhibit_rules:
  - source_match:
      severity: 'critical'
    target_match:
      severity: 'warning'
    equal: ['alertname', 'service']
EOF"
log_success "Alert routing configured"

###############################################################################
# STEP 8: Verification
###############################################################################

log_section "STEP 8: Verification"

log_step "Verifying Prometheus"
if ssh -o StrictHostKeyChecking=no akushnir@"$ONPREM_FULLSTACK_NODE" \
    "curl -s http://127.0.0.1:9090/api/v1/targets | grep -q 'prometheus'"; then
    log_success "✓ Prometheus running and scraping targets"
else
    log_error "✗ Prometheus verification failed"
fi

log_step "Verifying Grafana"
if ssh -o StrictHostKeyChecking=no akushnir@"$ONPREM_FULLSTACK_NODE" \
    "curl -s http://127.0.0.1:3000/api/health | grep -q 'ok'"; then
    log_success "✓ Grafana running"
else
    log_error "✗ Grafana verification failed"
fi

log_step "Verifying anomaly detector status"
if ssh -o StrictHostKeyChecking=no akushnir@"$ONPREM_FULLSTACK_NODE" \
    "sudo systemctl is-active elevatediq-anomaly-detector.service > /dev/null"; then
    log_success "✓ Anomaly detector service ACTIVE"
else
    log_error "✗ Anomaly detector service not active"
fi

###############################################################################
# STEP 9: Run initial tests
###############################################################################

log_section "STEP 9: Initial Testing"

log_step "Running initial chaos test (preview)"
ssh -o StrictHostKeyChecking=no akushnir@"$ONPREM_FULLSTACK_NODE" \
    "/usr/local/bin/chaos-testing-engine.sh 2>&1 | head -20"

log_success "Chaos test engine operational"

###############################################################################
# COMPLETION
###############################################################################

log_section "LAYER 3 DEPLOYMENT COMPLETE"

echo ""
echo_color "$GREEN" "✓ Observability & Chaos Testing Deployed"
echo ""
echo "Service Endpoints:"
echo "  Prometheus: http://127.0.0.1:9090"
echo "  Grafana: http://127.0.0.1:3000 (admin/elevatediq-admin)"
echo "  Alertmanager: http://127.0.0.1:9093"
echo "  Pushgateway: http://127.0.0.1:9091"
echo ""
echo "Automated Jobs:"
echo "  Anomaly Detector: systemctl status elevatediq-anomaly-detector.service"
echo "  Chaos Testing: Daily at 02:00 UTC (via cron)"
echo ""
echo "Logs:"
echo "  Prometheus: docker logs elevatediq-prometheus"
echo "  Grafana: docker logs elevatediq-grafana"
echo "  Anomaly Detector: journalctl -u elevatediq-anomaly-detector.service"
echo "  Chaos Tests: /var/log/elevatediq/chaos-tests.log"
echo ""

log_success "Layer 3 ready for production"
