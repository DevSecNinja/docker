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
APT_LOCK_TIMEOUT="${ANSIBLE_PULL_APT_LOCK_TIMEOUT:-600}"
# Applied to every apt-get invocation so apt waits for the lock instead of
# failing outright when another package manager is running.
APT_LOCK_OPTS=(-o "DPkg::Lock::Timeout=$APT_LOCK_TIMEOUT")

# Function to log messages (output goes to journalctl)
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

# Wait for apt/dpkg to become available.
# Shortly after boot, apt-daily, apt-daily-upgrade and unattended-upgrades
# routinely hold the dpkg frontend lock. Ansible tasks that shell out to dpkg
# (e.g. dpkg_selections) fail immediately in that situation, which aborts the
# whole run. "apt-get check" acquires the same frontend lock and honours
# DPkg::Lock::Timeout, so it blocks until the other process is done.
#
# Never fatal: this is only a best-effort gate, and the playbook itself is what
# repairs a broken package state. Non-lock failures are logged verbatim rather
# than silently reported as lock contention.
wait_for_apt_locks() {
    if ! command -v apt-get &> /dev/null; then
        return 0
    fi

    local output rc=0

    log "Waiting up to ${APT_LOCK_TIMEOUT}s for apt/dpkg locks to be released..."
    output=$(apt-get "${APT_LOCK_OPTS[@]}" check 2>&1) || rc=$?

    if [ "$rc" -eq 0 ]; then
        log "apt/dpkg locks are available"
    elif grep -qiE 'could not get lock|unable to acquire|frontend lock|temporarily unavailable' <<< "$output"; then
        log "WARNING: apt/dpkg still locked after ${APT_LOCK_TIMEOUT}s, continuing anyway"
    else
        log "WARNING: 'apt-get check' failed for a non-lock reason (rc=$rc), continuing anyway:"
        log "$output"
    fi
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
    wait_for_apt_locks
    apt-get "${APT_LOCK_OPTS[@]}" update
    apt-get "${APT_LOCK_OPTS[@]}" install -y ansible git gpg
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

# Run ansible-pull to enforce configuration state
# The repo is already cloned above; ansible-pull will detect no changes and
# skip the clone step, then proceed directly to running the playbook.
wait_for_apt_locks

ansible-pull \
    --url "$REPO_URL" \
    --checkout main \
    --directory "$WORKDIR" \
    --inventory "$INVENTORY_PATH" \
    --extra-vars "target_host=$TARGET_HOST" \
    "$PLAYBOOK_PATH"

log "Ansible-pull completed successfully"
