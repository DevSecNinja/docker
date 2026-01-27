#!/bin/bash
set -e

echo "🚀 Setting up Docker Infrastructure development environment..."

# Set Docker socket permissions
echo "🐳 Configuring Docker permissions..."
sudo groupadd -f docker
sudo usermod -aG docker $USER
sudo chown root:docker /var/run/docker.sock
sudo chmod 660 /var/run/docker.sock

# Install Python dependencies
echo "📦 Installing Python packages..."
pip install --no-cache-dir --upgrade pip
pip install --no-cache-dir -r requirements-dev.txt

# Install Ansible collections
echo "📚 Installing Ansible collections..."
ansible-galaxy collection install -r ansible/requirements.yml

# Install Ansible roles
echo "🎭 Installing Ansible roles..."
ansible-galaxy role install geerlingguy.docker

# Install Bats testing framework
echo "🧪 Installing Bats testing framework..."
sudo apt-get update
sudo apt-get install -y bats

# Verify installations
echo "✅ Verifying installations..."
echo "  Ansible: $(ansible --version | head -n1)"
echo "  Python: $(python3 --version)"
echo "  Bats: $(bats --version)"
echo "  yamllint: $(yamllint --version)"
echo "  ansible-lint: $(ansible-lint --version)"
echo "  Docker: $(docker --version)"
echo "  Docker Compose: $(docker compose version)"

# Set up git configuration helpers
echo "🔧 Configuring Git..."
git config --global core.autocrlf input
git config --global pull.rebase false

echo "✨ Development environment ready!"
echo ""
echo "Quick commands:"
echo "  • Run tests:          ./tests/bash/run-tests.sh"
echo "  • Lint YAML:          bash ansible/scripts/tests/lint-test.sh"
echo "  • Check syntax:       bash ansible/scripts/tests/syntax-test.sh"
echo "  • Test Docker:        bash ansible/scripts/tests/docker-test.sh"
echo "  • Ansible playbook:   ansible-playbook ansible/playbooks/main.yml --syntax-check"
echo ""
