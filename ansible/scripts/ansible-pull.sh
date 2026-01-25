#!/bin/bash
# Ansible Pull Script for automated configuration management
# This script checks for Git commits and pulls changes if available

set -e

# Configuration
REPO_URL="${ANSIBLE_PULL_REPO_URL:-https://github.com/DevSecNinja/docker.git}"
PLAYBOOK_PATH="${ANSIBLE_PULL_PLAYBOOK:-ansible/playbooks/main.yml}"
INVENTORY_PATH="${ANSIBLE_PULL_INVENTORY:-ansible/inventory/hosts.yml}"
WORKDIR="${ANSIBLE_PULL_WORKDIR:-/var/lib/ansible/local}"
LOG_FILE="${ANSIBLE_PULL_LOG:-/var/log/ansible-pull.log}"
TARGET_HOST="${ANSIBLE_PULL_TARGET:-$(hostname)}"

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

# Function to log messages
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log "Starting ansible-pull run"

# Install Ansible if not present
if ! command -v ansible-pull &> /dev/null; then
    log "Ansible not found, installing..."
    apt-get update
    apt-get install -y ansible git
fi

# Run ansible-pull with git commit checking
ansible-pull \
    --url "$REPO_URL" \
    --checkout main \
    --directory "$WORKDIR" \
    --inventory "$INVENTORY_PATH" \
    --extra-vars "target_host=$TARGET_HOST" \
    --only-if-changed \
    "$PLAYBOOK_PATH" 2>&1 | tee -a "$LOG_FILE"

PULL_EXIT_CODE=${PIPESTATUS[0]}

if [ $PULL_EXIT_CODE -eq 0 ]; then
    log "Ansible-pull completed successfully"
else
    log "Ansible-pull failed with exit code $PULL_EXIT_CODE"
    exit $PULL_EXIT_CODE
fi
