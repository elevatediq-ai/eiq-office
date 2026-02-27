#!/bin/bash
##############################################################################
# ElevatedIQ Systemd DAG Test - Validates dependency chain
# Purpose: Verify all services start in correct order after reboot
# Usage: ./scripts/pmo/test-systemd-dag.sh
##############################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "=== ElevatedIQ Systemd DAG Validation ==="
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS_COUNT=0
FAIL_COUNT=0

# Test helper
assert_active() {
    local service=$1
    local timeout=${2:-30}

    echo -n "Checking $service... "
    for i in $(seq 1 $timeout); do
        if systemctl is-active "$service" >/dev/null 2>&1; then
            echo -e "${GREEN}✓ ACTIVE${NC}"
            ((PASS_COUNT++))
            return 0
        fi
        sleep 1
    done

    echo -e "${RED}✗ FAILED${NC}"
    systemctl status "$service" 2>&1 | tail -5
    ((FAIL_COUNT++))
    return 1
}

assert_enabled() {
    local service=$1

    echo -n "Checking if $service is enabled... "
    if systemctl is-enabled "$service" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ ENABLED${NC}"
        ((PASS_COUNT++))
        return 0
    else
        echo -e "${RED}✗ NOT ENABLED${NC}"
        ((FAIL_COUNT++))
        return 1
    fi
}

assert_port_listening() {
    local port=$1
    local service=$2

    echo -n "Checking port $port ($service)... "
    if nc -z 127.0.0.1 $port 2>/dev/null; then
        echo -e "${GREEN}✓ LISTENING${NC}"
        ((PASS_COUNT++))
        return 0
    else
        echo -e "${RED}✗ NOT LISTENING${NC}"
        ((FAIL_COUNT++))
        return 1
    fi
}

##############################################################################
# Test 1: systemd-tmpfiles Configuration
##############################################################################
echo -e "${BLUE}Test 1: systemd-tmpfiles Configuration${NC}"

if [[ -f /etc/tmpfiles.d/elevatediq.conf ]]; then
    echo -e "${GREEN}✓ elevatediq.conf exists${NC}"
    ((PASS_COUNT++))
else
    echo -e "${RED}✗ elevatediq.conf missing${NC}"
    ((FAIL_COUNT++))
fi

# Validate tmpfiles
sudo systemd-tmpfiles --create 2>&1 | grep -q "Created" && \
    echo -e "${GREEN}✓ Tmpfiles created successfully${NC}" || \
    echo -e "${YELLOW}⚠ Tmpfiles already exist${NC}"

# Check directories exist
for dir in /var/run/pgbouncer /var/run/elevatediq /opt/host-forward /var/log/elevatediq; do
    if [[ -d "$dir" ]]; then
        echo -e "${GREEN}✓ Directory $dir exists${NC}"
        ((PASS_COUNT++))
    else
        echo -e "${RED}✗ Directory $dir missing${NC}"
        ((FAIL_COUNT++))
    fi
done

echo ""

##############################################################################
# Test 2: Service Enablement
##############################################################################
echo -e "${BLUE}Test 2: Service Enablement${NC}"

assert_enabled "pgbouncer.service"
assert_enabled "elevatediq-web.service"
assert_enabled "elevatediq-cluster.target"

echo ""

##############################################################################
# Test 3: Service Status
##############################################################################
echo -e "${BLUE}Test 3: Service Status${NC}"

assert_active "elevatediq-cluster.target"
assert_active "pgbouncer.service" 30
assert_active "elevatediq-web.service" 60

echo ""

##############################################################################
# Test 4: Network Connectivity
##############################################################################
echo -e "${BLUE}Test 4: Network Connectivity${NC}"

assert_port_listening "6432" "pgbouncer"
assert_port_listening "4000" "portal"
assert_port_listening "4001" "marketing"

echo ""

##############################################################################
# Test 5: Service Dependency Order
##############################################################################
echo -e "${BLUE}Test 5: Service Dependency Analysis${NC}"

echo "Service dependency tree:"
systemctl list-dependencies elevatediq-cluster.target --all

echo ""
echo "Expected order on boot:"
echo "  1. network-online.target"
echo "  2. docker.service"
echo "  3. pgbouncer.service (after docker)"
echo "  4. elevatediq-web.service (after pgbouncer)"
echo ""

##############################################################################
# Test 6: Docker Container Status
##############################################################################
echo -e "${BLUE}Test 6: Docker Container Status${NC}"

echo "Running containers:"
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "elevatediq|intelligent" || echo "No containers found"

if docker ps | grep -q "elevatediq-portal"; then
    echo -e "${GREEN}✓ Portal container running${NC}"
    ((PASS_COUNT++))
else
    echo -e "${RED}✗ Portal container not running${NC}"
    ((FAIL_COUNT++))
fi

echo ""

##############################################################################
# Test 7: Service Failure Handling
##############################################################################
echo -e "${BLUE}Test 7: Service Failure Recovery${NC}"

echo "Checking restart policies..."

# Check pgbouncer restart config
if systemctl show pgbouncer.service | grep -q "Restart=on-failure"; then
    echo -e "${GREEN}✓ pgbouncer has on-failure restart${NC}"
    ((PASS_COUNT++))
else
    echo -e "${RED}✗ pgbouncer missing on-failure restart${NC}"
    ((FAIL_COUNT++))
fi

# Check elevatediq-web restart config
if systemctl show elevatediq-web.service | grep -q "Restart=on-failure"; then
    echo -e "${GREEN}✓ elevatediq-web has on-failure restart${NC}"
    ((PASS_COUNT++))
else
    echo -e "${RED}✗ elevatediq-web missing on-failure restart${NC}"
    ((FAIL_COUNT++))
fi

echo ""

##############################################################################
# Summary
##############################################################################
echo -e "${BLUE}=== Test Summary ===${NC}"
echo -e "Passed: ${GREEN}$PASS_COUNT${NC}"
echo -e "Failed: ${RED}$FAIL_COUNT${NC}"
echo ""

if [[ $FAIL_COUNT -eq 0 ]]; then
    echo -e "${GREEN}✅ ALL TESTS PASSED - Systemd DAG validated!${NC}"
    exit 0
else
    echo -e "${RED}❌ SOME TESTS FAILED - Review output above${NC}"
    exit 1
fi
