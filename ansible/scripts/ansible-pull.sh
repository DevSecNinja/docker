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
if ! command -v ansible-playbook &> /dev/null; then
    log "Ansible not found, installing..."
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        echo "Error: Script must be run as root or with sudo" >&2
        exit 1
    fi
    apt-get update
    apt-get install -y ansible git gpg
fi

# Clone or update the repository first so requirements.yml is available
# before running ansible-pull (which would fail on missing roles otherwise)
if [ -d "$WORKDIR/.git" ]; then
    log "Updating existing repository..."
    git -C "$WORKDIR" fetch origin
    git -C "$WORKDIR" reset --hard origin/main
else
    log "Cloning repository..."
    git clone --branch main "$REPO_URL" "$WORKDIR"
fi

# Install all required collections and roles from requirements.yml upfront
if [ -f "$WORKDIR/ansible/requirements.yml" ]; then
    log "Ensuring required Ansible collections are installed..."
    ansible-galaxy collection install -r "$WORKDIR/ansible/requirements.yml" 2>&1
    log "Ensuring required Ansible roles are installed..."
    ansible-galaxy role install -r "$WORKDIR/ansible/requirements.yml" 2>&1
fi

# Run the playbook directly since the repo is already up to date above.
# Using ansible-playbook avoids a redundant git pull and the host pattern
# warning that ansible-pull emits during its internal git-check step.
log "Starting Ansible Playbook at $(date +'%Y-%m-%d %H:%M:%S')"
ansible-playbook \
    --inventory "$WORKDIR/$INVENTORY_PATH" \
    --extra-vars "target_host=$TARGET_HOST" \
    "$WORKDIR/$PLAYBOOK_PATH"

log "Ansible-playbook completed successfully"
