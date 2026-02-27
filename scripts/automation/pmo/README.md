scripts/pmo/deploy_compute_host.sh — runbook

Usage:
  SSH_USER=ubuntu HOST=192.168.168.42 scripts/pmo/deploy_compute_host.sh

Notes:
- The script will attempt to copy `infra/hosts.env` to the remote repository path.
- The script expects Docker and Docker Compose to be installed on the remote host.
- For automated CI, add `SSH_PRIVATE_KEY`, `SSH_USER`, `COMPUTE_HOST` to repo secrets and trigger the workflow.
