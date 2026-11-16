#!/bin/bash
set -e

check_docker_sock() {
    local sock="/var/run/docker.sock"

    # Exists?
    if [[ ! -S "$sock" ]]; then
        echo "❌ Docker socket not found at $sock"
        return 1
    fi

    # Read actual values
    local owner group perms
    owner=$(stat -c '%U' "$sock")
    group=$(stat -c '%G' "$sock")
    perms=$(stat -c '%a' "$sock")

    local ok=true

    if [[ "$owner" != "root" ]]; then
        echo "❌ Owner is '$owner' (expected: root)"
        ok=false
    fi

    if [[ "$group" != "docker" ]]; then
        echo "❌ Group is '$group' (expected: docker)"
        ok=false
    fi

    if [[ "$perms" != "660" ]]; then
        echo "❌ Permissions are '$perms' (expected: 660)"
        ok=false
    fi

    if [[ "$ok" == true ]]; then
        echo "✅ Docker socket permissions are correct"
        return 0
    else
        echo "⚠️ Docker daemon is misconfigured. Fix daemon config, not the socket."
        return 2
    fi
}

echo "🚀 Setting up Docker Infrastructure development environment..."

# Set Docker socket permissions
echo "🐳 Configuring Docker permissions..."
sudo groupadd -f docker --gid 780 # Note: this group ID aligns with the docker_group role
sudo groupmod -g 780 docker       # In case the group already existed with a different GID
sudo usermod -aG docker vscode
check_docker_sock || exit 1

# Install Python dependencies
echo "📦 Installing Python packages..."
pip install --no-cache-dir --upgrade pip
pip install --no-cache-dir -r requirements.txt

# Install Ansible collections and roles
echo "📚 Installing Ansible collections and roles..."
ansible-galaxy install -r ansible/requirements.yml

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

# Check if Docker is usable without sudo in THIS session
if ! docker info >/dev/null 2>&1; then
    echo "⚠️  Docker is not accessible in this session."
    echo "   You were likely added to the 'docker' group after this shell started."
    echo "   Run: sudo su - \$USER"
    echo "   (or reopen the terminal) to refresh group membership."
    echo ""
fi

echo "Quick commands:"
echo "  • Run tests:          ./tests/bash/run-tests.sh"
echo "  • Lint YAML:          bash ansible/scripts/tests/lint-test.sh"
echo "  • Check syntax:       bash ansible/scripts/tests/syntax-test.sh"
echo "  • Test Docker:        bash ansible/scripts/tests/docker-test.sh"
echo "  • Ansible playbook:   ansible-playbook ansible/playbooks/main.yml --syntax-check"
echo ""
