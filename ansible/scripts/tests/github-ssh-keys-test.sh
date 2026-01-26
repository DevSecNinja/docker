#!/bin/bash
# Test script for github_ssh_keys role
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "==> Installing Ansible..."
pip install ansible

echo "==> Creating test inventory..."
mkdir -p /tmp/test-inventory
cat > /tmp/test-inventory/hosts.yml <<'EEOF'
---
all:
  children:
    test_servers:
      hosts:
        localhost:
          ansible_connection: local
          ansible_become: true
          ansible_user: runner
          server_features:
            - github_ssh_keys
          github_ssh_keys_username: DevSecNinja
EEOF

echo "==> Testing github_ssh_keys role in check mode..."
cd "$ANSIBLE_DIR"
ansible-playbook \
    --check \
    --inventory /tmp/test-inventory/hosts.yml \
    --extra-vars "target_host=localhost" \
    --tags github_ssh_keys \
    playbooks/main.yml

echo "==> Verifying GitHub SSH keys can be fetched..."
curl -f -s https://github.com/DevSecNinja.keys > /dev/null && echo "GitHub keys API is accessible"

echo "==> github_ssh_keys role test passed!"
