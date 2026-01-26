#!/bin/bash
# Test script for Ansible syntax check
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "==> Installing Ansible..."
pip install -q ansible

echo "==> Installing Ansible collections..."
ansible-galaxy collection install -q community.general ansible.posix community.docker

echo "==> Installing required roles..."
ansible-galaxy install -q -r "$ANSIBLE_DIR/requirements.yml" || {
    echo "Note: Some roles may not be available in offline mode"
}

echo "==> Running syntax check..."
cd "$ANSIBLE_DIR"
ansible-playbook --syntax-check playbooks/main.yml

echo "==> Syntax check passed!"
