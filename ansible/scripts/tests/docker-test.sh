#!/bin/bash
# Test script for Docker provisioning
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "==> Installing Ansible..."
pip install ansible

echo "==> Installing Ansible collections..."
ansible-galaxy collection install community.general ansible.posix community.docker

echo "==> Installing required roles..."
ansible-galaxy install -r "$ANSIBLE_DIR/requirements.yml" || {
    echo "Note: Some roles may not be available in offline mode"
}

echo "==> Creating test inventory..."
mkdir -p /tmp/test-inventory
cat > /tmp/test-inventory/hosts.yml <<'EEOF'
---
all:
  children:
    docker_servers:
      hosts:
        localhost:
          ansible_connection: local
          ansible_become: true
          server_features:
            - docker
            - chezmoi
          compose_modules: []
          # Override docker_packages to exclude rootless-extras which is not
          # available on Ubuntu 24.04. See: https://github.com/geerlingguy/ansible-role-docker/issues/509
          docker_packages:
            - docker-ce
            - docker-ce-cli
            - containerd.io
            - docker-buildx-plugin
EEOF

echo "==> Running playbook in check mode..."
cd "$ANSIBLE_DIR"
ansible-playbook \
    --check \
    --inventory /tmp/test-inventory/hosts.yml \
    --extra-vars "target_host=localhost" \
    --skip-tags traefik \
    playbooks/main.yml

echo "==> Testing Docker role..."
ansible-playbook \
    --inventory /tmp/test-inventory/hosts.yml \
    --extra-vars "target_host=localhost" \
    --tags docker \
    playbooks/main.yml

echo "==> Verifying Docker installation..."
docker --version
sudo systemctl status docker --no-pager

echo "==> Docker provisioning test passed!"
