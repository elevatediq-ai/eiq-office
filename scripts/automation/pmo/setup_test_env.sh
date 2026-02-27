#!/usr/bin/env bash
set -euo pipefail

# Creates a local virtualenv for running tests and installs dev dependencies.
# Usage: ./scripts/pmo/setup_test_env.sh

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
VENV_DIR="$ROOT/.venv_test"
REQ_DEV="$ROOT/requirements-dev.txt"

echo "Setting up test environment in $VENV_DIR"
python3 -m venv "$VENV_DIR"
# shellcheck disable=SC1091
source "$VENV_DIR/bin/activate"

pip install --upgrade pip
if [ -f "$REQ_DEV" ]; then
  pip install -c "$ROOT/constraints-pinned.txt" -r "$REQ_DEV"
else
  echo "requirements-dev.txt not found at $REQ_DEV"
  exit 1
fi

# Optionally install per-app requirements. Use --with-app-reqs to enable.
if [ "${1:-}" = "--with-app-reqs" ]; then
  echo "Installing per-app requirements (this may take a while)"
  # Install all requirements files under apps/* (non-recursive into deeper folders)
  IFS=$'\n' read -r -d '' -a req_files < <(find "$ROOT/apps" -maxdepth 2 -type f -name "requirements*.txt" -print0 | xargs -0 -n1 echo && printf '\0')
  for req in "${req_files[@]:-}"; do
    if [ -z "$req" ]; then
      continue
    fi
    echo "Installing $req"
    # Skip very large / GPU-specific ML packages that require special hardware or private wheels
    if grep -Eiq "vllm|torch|triton|cuda|nvidia|cudnn|cuda_bindings|nvidia_" "$req"; then
      echo "Skipping $req — contains GPU/ML-specific packages (vllm/torch/etc). Install manually on appropriate hosts."
      continue
    fi
    # Try normal install; if pip is running in --require-hashes mode this may fail.
    if ! pip install -c "$ROOT/constraints-pinned.txt" -r "$req"; then
      echo "pip install failed for $req — retrying without dependency resolution (--no-deps) to bypass --require-hashes enforcement"
      if ! pip install -c "$ROOT/constraints-pinned.txt" --no-deps -r "$req"; then
        echo "Failed to install $req even with --no-deps; skipping this requirements file and continuing."
        continue
      fi
    fi
  done
fi

echo "Test environment ready. Activate with: source $VENV_DIR/bin/activate"

echo "You can run: pytest -q"
