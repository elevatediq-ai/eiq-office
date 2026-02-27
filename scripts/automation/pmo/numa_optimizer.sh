#!/usr/bin/env bash
# ElevatedIQ NUMA and CPU Affinity Optimizer
# Aligned with NIST 800-53 SC-5 (Denial of Service Protection) via Resource Management

set -euo pipefail

# --- Configuration ---
# 8-Core Topology Mapping (Local Host)
# Logic: Scaled to 8 physical cores for dev stability

TOTAL_CORES=$(nproc)

if [ "$TOTAL_CORES" -le 8 ]; then
    POOL_AI_TRAINING="0-3"    # 4 Cores
    POOL_CONTROL_PLANE="4-5"  # 2 Cores
    POOL_OBSERVABILITY="6-7" # 2 Cores
else
    # i9-10900X Topology Mapping (10 Core / 20 Thread)
    # Physical Cores: 0, 1, 2, 3, 4, 5, 6, 7, 8, 9
    # Logical Pairs: (0,10), (1,11), (2,12), (3,13), (4,14), (5,15), (6,16), (7,17), (8,18), (9,19)
    POOL_AI_TRAINING="0-5,10-15"
    POOL_CONTROL_PLANE="6-7,16-17"
    POOL_OBSERVABILITY="8-9,18-19"
fi

log() {
    echo -e "\033[1;34m[NUMA-OPTIMIZER]\033[0m $1"
}

error() {
    echo -e "\033[1;31m[ERROR]\033[0m $1"
    exit 1
}

show_usage() {
    echo "Usage: $0 <pool> <command...>"
    echo "Pools: ai, control, ops"
    exit 1
}

# --- Main Logic ---
if [ $# -lt 2 ]; then
    show_usage
fi

POOL_NAME=$1
shift
COMMAND=("$@")

case $POOL_NAME in
    ai)
        CPUS=$POOL_AI_TRAINING
        ;;
    control)
        CPUS=$POOL_CONTROL_PLANE
        ;;
    ops)
        CPUS=$POOL_OBSERVABILITY
        ;;
    *)
        error "Unknown pool: $POOL_NAME"
        ;;
esac

log "Optimizing resource allocation for pool: $POOL_NAME"
log "Binding process to CPUs: $CPUS"

# Check if numactl is available for memory node binding
# Even with 1 node, specifying --localalloc ensures local memory allocation
if command -v numactl >/dev/null 2>&1; then
    log "Executing via numactl..."
    exec numactl --physcpubind="$CPUS" --localalloc "${COMMAND[@]}"
else
    log "Executing via taskset (numactl not found)..."
    exec taskset -c "$CPUS" "${COMMAND[@]}"
fi
