#!/bin/bash
# Test script for Ansible linting
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "==> Installing Ansible linting tools..."
pip install -q ansible ansible-lint yamllint

echo "==> Running yamllint..."
yamllint "$ANSIBLE_DIR/" || {
    echo "YAML linting failed"
    exit 1
}

echo "==> Running ansible-lint..."
cd "$ANSIBLE_DIR"
ansible-lint playbooks/ roles/ || {
    echo "Ansible linting failed"
    exit 1
}

echo "==> All linting checks passed!"
