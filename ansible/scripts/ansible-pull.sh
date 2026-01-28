#!/bin/bash
# Ansible Pull Script for automated configuration management
# This script checks for Git commits and pulls changes if available

set -e

# Configuration
REPO_URL="${ANSIBLE_PULL_REPO_URL:-https://github.com/DevSecNinja/docker.git}"
PLAYBOOK_PATH="${ANSIBLE_PULL_PLAYBOOK:-ansible/playbooks/main.yml}"
INVENTORY_PATH="${ANSIBLE_PULL_INVENTORY:-ansible/inventory/hosts.yml}"
WORKDIR="${ANSIBLE_PULL_WORKDIR:-/var/lib/ansible/local}"
TARGET_HOST="${ANSIBLE_PULL_TARGET:-$(hostname | tr '[:upper:]' '[:lower:]')}"

# Function to log messages (output goes to journalctl)
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

log "Starting ansible-pull run"

# Install Ansible if not present
if ! command -v ansible-pull &> /dev/null; then
    log "Ansible not found, installing..."
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        echo "Error: Script must be run as root or with sudo" >&2
        exit 1
    fi
    apt-get update
    apt-get install -y ansible git gpg
fi

# Install required Ansible collections
log "Ensuring required Ansible collections are installed..."
ansible-galaxy collection install community.general --force 2>&1
ansible-galaxy collection install community.docker --force 2>&1

# Run ansible-pull to enforce configuration state
# Note: ansible-pull will clone the repo first if it doesn't exist
ansible-pull \
    --url "$REPO_URL" \
    --checkout main \
    --directory "$WORKDIR" \
    --inventory "$INVENTORY_PATH" \
    --extra-vars "target_host=$TARGET_HOST" \
    "$PLAYBOOK_PATH"

PULL_EXIT_CODE=${PIPESTATUS[0]}

# Install required external roles from requirements.yml after repo is cloned
if [ -f "$WORKDIR/ansible/requirements.yml" ]; then
    log "Installing required external roles..."
    cd "$WORKDIR"
    ansible-galaxy role install -r ansible/requirements.yml 2>&1

    # Re-run ansible-pull after installing roles
    log "Re-running ansible-pull with external roles installed..."
    ansible-pull \
        --url "$REPO_URL" \
        --checkout main \
        --directory "$WORKDIR" \
        --inventory "$INVENTORY_PATH" \
        --extra-vars "target_host=$TARGET_HOST" \
        "$PLAYBOOK_PATH"

    PULL_EXIT_CODE=$?
fi

PULL_EXIT_CODE=${PIPESTATUS[0]}

if [ $PULL_EXIT_CODE -eq 0 ]; then
    log "Ansible-pull completed successfully"
else
    log "Ansible-pull failed with exit code $PULL_EXIT_CODE"
    exit $PULL_EXIT_CODE
fi
