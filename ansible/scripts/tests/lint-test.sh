#!/bin/bash
# Test script for Ansible linting
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "==> Installing Ansible linting tools..."
pip install ansible ansible-lint yamllint

echo "==> Running yamllint..."
yamllint "$ANSIBLE_DIR/"

echo "==> Running ansible-lint on roles only..."
cd "$ANSIBLE_DIR"
# Only lint roles to avoid missing external role errors
ansible-lint roles/

echo "==> All linting checks passed!"
