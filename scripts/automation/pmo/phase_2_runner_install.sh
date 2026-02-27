#!/bin/bash
# PHASE 2: GitHub Actions Runner Installation
# Installs and configures self-hosted runner on .42
# Execute on: 192.168.168.42
# Usage: ssh akushnir@192.168.168.42 'bash /path/to/phase_2_runner_install.sh YOUR_GITHUB_TOKEN'

set -e

######################################
# CONFIGURATION
######################################
GITHUB_TOKEN="${1:-${GITHUB_TOKEN}}"
REPO_URL="https://github.com/kushin77/ElevatedIQ-Mono-Repo"
RUNNER_NAME="dev-elevatediq-42-runner"
RUNNER_DIR="/home/akushnir/actions-runner"
HOME_DIR="/home/akushnir"

######################################
# VALIDATION
######################################
if [[ -z "$GITHUB_TOKEN" ]]; then
  echo "❌ ERROR: GitHub token not provided"
  echo "Usage: bash phase_2_runner_install.sh YOUR_GITHUB_TOKEN"
  echo "       or set GITHUB_TOKEN environment variable"
  exit 1
fi

echo "🚀 PHASE 2: GitHub Actions Runner Installation"
echo "=================================================="
echo "Timestamp: $(date)"
echo "Token: ${GITHUB_TOKEN:0:10}***"
echo "Runner Dir: $RUNNER_DIR"
echo ""

######################################
# STEP 1: Clean up if previous install exists
######################################
if [ -d "$RUNNER_DIR" ]; then
  echo "📋 Found existing runner directory, skipping download (already installed)"
else
  echo "📥 Downloading GitHub Actions runner..."

  RUNNER_VERSION=$(curl -s https://api.github.com/repos/actions/runner/releases/latest \
    | grep 'tag_name' | cut -d'"' -f4 | sed 's/^v//')

  if [[ -z "$RUNNER_VERSION" ]]; then
    echo "❌ Failed to get runner version"
    exit 1
  fi

  echo "Latest runner version: v${RUNNER_VERSION}"

  cd "$HOME_DIR"

  RUNNER_FILE="actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz"
  RUNNER_SHA="$RUNNER_FILE.sha256"

  echo "Downloading from GitHub releases..."
  curl -L -o "$RUNNER_FILE" \
    "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz" || exit 1

  echo "Verifying checksum..."
  curl -L -o "$RUNNER_SHA" \
    "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz.sha256" || exit 1

  sha256sum -c "$RUNNER_SHA" || {
    echo "❌ Checksum verification failed"
    exit 1
  }

  echo "✅ Checksum verified"

  echo "📦 Extracting runner..."
  mkdir -p "$RUNNER_DIR"
  cd "$RUNNER_DIR"
  tar xzf "$HOME_DIR/$RUNNER_FILE"

  echo "✅ Runner extracted to $RUNNER_DIR"
  
  echo ""
  echo "⚙️  Configuring runner..."
  mkdir -p _work

  ./config.sh \
    --url "$REPO_URL" \
    --token "$GITHUB_TOKEN" \
    --name "$RUNNER_NAME" \
    --runnergroup default \
    --labels "self-hosted,high-mem,linux,x64" \
    --work _work \
    --replace \
    --unattended || { echo "❌ Configuration failed"; exit 1; }

  echo "✅ Runner configured"
  
  echo ""
  echo "🧹 Cleaning up archives..."
  rm -f "$HOME_DIR/$RUNNER_FILE" "$HOME_DIR/$RUNNER_SHA"
fi

######################################
# STEP 2: Install/Restart as service
######################################
echo ""
echo "🔧 Setting up systemd service..."

cd "$RUNNER_DIR"

# Try to install/restart service (requires sudo)
if sudo systemctl status actions-runner >/dev/null 2>&1; then
  echo "⚠️  Service already exists, restarting..."
  sudo systemctl restart actions-runner
else
  echo "Installing service for the first time..."
  sudo bash svc.sh install || true
  sudo systemctl start actions-runner
  sudo systemctl enable actions-runner
fi

sleep 3

echo ""
echo "📊 Service Status:"
sudo systemctl status actions-runner --no-pager 2>&1 | head -5 || echo "Checking status..."

######################################
# STEP 3: Verify runner registration
######################################
echo ""
echo "🔍 Verifying runner registration with GitHub..."
sleep 5

RUNNER_CHECK=$(curl -s -H "Authorization: token ${GITHUB_TOKEN}" \
  "https://api.github.com/repos/kushin77/ElevatedIQ-Mono-Repo/actions/runners" \
  | grep -o '"name":"[^"]*' | grep "$RUNNER_NAME" | head -1 || echo "")

if [[ ! -z "$RUNNER_CHECK" ]]; then
  echo "✅ RUNNER REGISTERED WITH GITHUB"
else
  echo "⚠️ Runner may be initializing (check GitHub Actions settings)"
fi

######################################
# FINAL STATUS
######################################
echo ""
echo "✅ PHASE 2 COMPLETE"
echo "=================================================="
echo "Timestamp: $(date)"
echo "Runner: $RUNNER_NAME"
echo "Status: Run 'sudo systemctl status actions-runner' to check"

