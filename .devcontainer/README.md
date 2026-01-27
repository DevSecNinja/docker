# DevContainer Configuration

This devcontainer provides a complete development environment for the Docker Infrastructure repository.

## Features

### Installed Tools

- **Ansible 2.20+**: Infrastructure automation
- **Python 3.14**: Required for Ansible
- **Docker-in-Docker**: For testing Docker configurations
- **Bats**: Testing framework
- **yamllint**: YAML linting
- **ansible-lint**: Ansible best practices linting
- **GitHub CLI**: GitHub integration

### VS Code Extensions

- **GitHub Copilot**: AI pair programming
- **Ansible**: Syntax highlighting and IntelliSense
- **YAML**: Advanced YAML support with schema validation
- **Docker**: Docker container management
- **Bats**: Bats test file support

## Getting Started

### Prerequisites

- VS Code with Remote - Containers extension
- Docker Desktop (with Docker Compose v2)

### Opening the DevContainer

1. Open this repository in VS Code
2. Click "Reopen in Container" when prompted, or
3. Use Command Palette: `Remote-Containers: Reopen in Container`

The initial setup will take a few minutes to:
- Pull the base Debian image
- Install all required tools and dependencies
- Configure the development environment

## Available Commands

### Testing

```bash
# Run all tests
./tests/bash/run-tests.sh

# Run specific test suite
./tests/bash/run-tests.sh --test lint-test.bats

# Run in CI mode (generates JUnit XML)
./tests/bash/run-tests.sh --ci
```

### Linting

```bash
# Lint YAML files
bash ansible/scripts/tests/lint-test.sh

# Check Ansible syntax
bash ansible/scripts/tests/syntax-test.sh
```

### Ansible

```bash
# Check playbook syntax
ansible-playbook ansible/playbooks/main.yml --syntax-check

# Test specific playbook
ansible-playbook ansible/playbooks/main.yml --check

# Install collections
ansible-galaxy collection install -r ansible/requirements.yml

# Install roles
ansible-galaxy role install geerlingguy.docker
```

### Docker

```bash
# Test Docker provisioning
bash ansible/scripts/tests/docker-test.sh

# List running containers
docker ps

# View container logs
docker logs <container_name>
```

## Directory Structure

The devcontainer has access to the entire repository:

```
/workspaces/docker/
├── .devcontainer/          # DevContainer configuration
├── ansible/                # Ansible playbooks, roles, and inventory
├── tests/                  # Bats test suite
└── ...
```

## Configuration

### VS Code Settings

The devcontainer configures:
- Format on save
- LF line endings
- YAML indentation (2 spaces)
- Ansible-specific YAML schemas
- ShellCheck integration

### Docker-in-Docker

The container runs Docker-in-Docker to support:
- Testing Docker installations
- Running Docker Compose modules
- Container-based testing

Note: The Docker socket is mounted for better performance.

## Troubleshooting

### Docker Socket Permission Issues

If you encounter Docker permission issues:

```bash
sudo chmod 666 /var/run/docker.sock
```

### Ansible Collections Not Found

Reinstall collections:

```bash
ansible-galaxy collection install -r ansible/requirements.yml --force
```

### Bats Tests Failing

Ensure Bats libraries are installed:

```bash
ls /usr/local/lib/bats/
# Should show: bats-support, bats-assert
```

### Slow Container Startup

First-time setup takes longer due to:
- Installing Ansible and dependencies
- Downloading Ansible collections/roles
- Installing Bats framework

Subsequent rebuilds are faster due to Docker layer caching.

## Customization

### Adding Python Packages

Edit [post-create.sh](.devcontainer/post-create.sh):

```bash
pip install --no-cache-dir your-package
```

### Adding VS Code Extensions

Edit [devcontainer.json](.devcontainer/devcontainer.json):

```json
"extensions": [
  "publisher.extension-id"
]
```

### Changing Shell

To use a different default shell (e.g., zsh, fish):

1. Install the shell in `post-create.sh`:
   ```bash
   sudo apt-get install -y fish
   ```

2. Update `devcontainer.json`:
   ```json
   "terminal.integrated.defaultProfile.linux": "fish"
   ```

## Resources

- [Ansible Documentation](https://docs.ansible.com/)
- [Bats Testing](https://github.com/bats-core/bats-core)
- [VS Code DevContainers](https://code.visualstudio.com/docs/devcontainers/containers)
- [Repository README](../README.md)

## Support

For issues related to the devcontainer setup, please open an issue in this repository.
