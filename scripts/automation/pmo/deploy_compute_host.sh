#!/usr/bin/env bash
# Deploy vLLM + monitoring to an on-prem compute host via SSH
# Usage: SSH_USER=ubuntu HOST=192.168.168.42 ./scripts/pmo/deploy_compute_host.sh
# Requires: SSH access and docker/docker-compose on remote host
set -euo pipefail

SSH_USER=${SSH_USER:-$(whoami)}
HOST=${HOST:-${ONPREM_COMPUTE_HOST:-192.168.168.42}}
# Use an absolute path if possible, or ensure it resolves clearly
REPO_DIR=${REPO_DIR:-"/home/akushnir/ElevatedIQ-Mono-Repo"}

echo "Deploy: $HOST (user=$SSH_USER)"

# 1) copy infra/hosts.env (if present locally)
if [[ -f infra/hosts.env ]]; then
  echo "Copying infra/hosts.env -> $SSH_USER@$HOST:$REPO_DIR/infra/hosts.env"
  scp infra/hosts.env "$SSH_USER@$HOST:$REPO_DIR/infra/hosts.env"
else
  echo "Warning: infra/hosts.env not found locally — remote should already have topology file"
fi

# 1.5) copy .env (CRITICAL for secrets/config)
if [[ -f .env ]]; then
  echo "Copying .env -> $SSH_USER@$HOST:$REPO_DIR/.env"
  scp .env "$SSH_USER@$HOST:$REPO_DIR/.env"
fi

# 1.6) copy config directory (REQUIRED for Prometheus/OpenStack)
if [[ -d config ]]; then
  echo "Copying config/ -> $SSH_USER@$HOST:$REPO_DIR/config"
  # Use rsync if available for speed, falling back to scp -r
  if command -v rsync &> /dev/null; then
      rsync -az config/ "$SSH_USER@$HOST:$REPO_DIR/config/"
  else
      scp -r config "$SSH_USER@$HOST:$REPO_DIR/"
  fi
fi

# 1.7) copy updated compose files (infra/openstack, compose/monitoring)
echo "Syncing docker-compose files..."
scp infra/openstack/docker-compose.yml "$SSH_USER@$HOST:$REPO_DIR/infra/openstack/docker-compose.yml"
# Copy OpenStack specific environment file
if [ -f infra/openstack/.env ]; then
    echo "Copying infra/openstack/.env -> $SSH_USER@$HOST:$REPO_DIR/infra/openstack/.env"
    scp infra/openstack/.env "$SSH_USER@$HOST:$REPO_DIR/infra/openstack/.env"
fi
scp compose/docker-compose.monitoring.yml "$SSH_USER@$HOST:$REPO_DIR/compose/docker-compose.monitoring.yml"

# 2) remote commands: pull images and start compute and monitoring stacks
REMOTE_CMDS=$(cat <<EOF
set -e
REPO_DIR="$REPO_DIR"
cd "\$REPO_DIR"

# Detect host ip to set specific optimizations
# ROBUST IP CHECK: Look for 192.168.168.31 specifically in the IP list
HOST_IPS=\$(hostname -I)
if [[ "\$HOST_IPS" == *"192.168.168.31"* ]]; then
  echo "Applying VS-CODE-NODE configuration (.31)"
  echo "Error: .31 node is strictly for coding. Use .42 for all compute workloads."
  exit 1
else
  echo "Applying WORKER-NODE (.42) PROD-GPU optimizations"
  # Load environment variables from .env if present
  if [ -f .env ]; then
    set -a
    source .env
    set +a
  fi

  export VLLM_MODEL="casperhansen/llama-3-8b-instruct-awq"
  export VLLM_QUANTIZATION="awq"
  export VLLM_GPU_MEMORY_UTILIZATION=0.90
  export VLLM_MAX_MODEL_LEN=4096
  export VLLM_PORT=8000
  export DEPLOY_VLLM="true"
  export PROFILE="compute-host"
fi

# Detect docker-compose V1 vs V2 plugin
if docker compose version >/dev/null 2>&1; then
  COMPOSE_CMD="docker compose"
elif docker-compose version >/dev/null 2>&1; then
  COMPOSE_CMD="docker-compose"
else
  echo "Error: docker-compose not found on remote."
  exit 1
fi

echo "Using command: \$COMPOSE_CMD"

# Pull and start vLLM
if [[ "\$DEPLOY_VLLM" == "true" ]]; then
  echo "🚀 Deploying vLLM..."
  \$COMPOSE_CMD -f compose/docker-compose.vllm.yml --profile \$PROFILE pull || true
  \$COMPOSE_CMD -f compose/docker-compose.vllm.yml --profile \$PROFILE up -d
fi

# Start monitoring stack (Prometheus / node-exporter / exporters)
if [ -f "compose/docker-compose.monitoring.yml" ]; then
  echo "📊 Deploying Monitoring Stack..."
  \$COMPOSE_CMD -f compose/docker-compose.monitoring.yml pull || true
  \$COMPOSE_CMD -f compose/docker-compose.monitoring.yml up -d
fi

# Start OpenStack (Kolla/Wallaby)
if [ -f "infra/openstack/docker-compose.yml" ]; then
  echo "☁️ Deploying OpenStack (Wallaby)..."
  # Use force-recreate to ensure config changes are picked up (COPY_ALWAYS strategy)
  \$COMPOSE_CMD -f infra/openstack/docker-compose.yml pull || true
  \$COMPOSE_CMD -f infra/openstack/docker-compose.yml up -d --force-recreate
fi

# Wait for services to become ready
sleep 10
# Basic health checks
curl -sS --max-time 3 http://127.0.0.1:8000/v1/models || echo "vLLM not ready yet"
curl -sS --max-time 3 http://127.0.0.1:9090/-/ready || echo "Prometheus not ready yet"
EOF
)

echo "Running remote deploy commands on $HOST"
ssh "$SSH_USER@$HOST" "$REMOTE_CMDS"

# 3) post-deploy verification from caller
echo "Remote deploy finished. Run 'bash scripts/bootstrap/test_backend_capacity.sh' locally to re-check endpoints."
exit 0
