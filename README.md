# Docker Infrastructure

Automated infrastructure management using Ansible Pull for Docker-based services.

## Overview

This repository contains Ansible configurations for automated server provisioning and management. It uses **Ansible Pull** approach, where servers pull their configuration from this repository and apply changes automatically when Git commits are detected.

## Features

- 🔄 **Ansible Pull Configuration**: Servers automatically pull and apply configurations
- 🔑 **GitHub SSH Keys**: Automatically install SSH keys from GitHub profiles; enable by adding `github_ssh_keys` to `server_features` in your inventory
- 🐳 **Docker Management**: Automated Docker installation and configuration
- 🐙 **Modular Docker Compose**: Easily add/remove compose modules per server
- 🔥 **UFW Firewall**: Automated firewall configuration with sensible defaults
- 🌐 **Traefik Module**: Reverse proxy as a compose module
- 📦 **Chezmoi Integration**: Dotfiles management support
- ⚙️ **Automated Updates**: Self-configuring ansible-pull with cron or systemd
- 🔧 **Automated Maintenance**: Daily and weekly OS patch schedules
- 🧪 **CI/CD Testing**: GitHub Actions with reusable test scripts
- 📈 **Scalable Structure**: Easy to add new servers and modules

## Quick Start

For new servers, see the [Installation Guide](INSTALL.md).

For Ansible documentation and structure, see [ansible/README.md](ansible/README.md).

## Repository Structure

```
.
├── ansible.cfg                 # Ansible configuration (for ansible-pull)
├── Taskfile.yml                # Task runner configuration
├── ansible/                    # Ansible configuration directory
│   ├── ansible.cfg            # Ansible configuration (for local runs)
│   ├── requirements.yml       # External roles and collections
│   ├── playbooks/             # Ansible playbooks
│   │   ├── main.yml          # Main playbook for ansible-pull
│   │   ├── maintenance-update.yml   # Update config & images
│   │   ├── maintenance-daily.yml    # Daily OS patches
│   │   └── maintenance-weekly.yml   # Weekly patches & reboot
│   ├── inventory/             # Inventory and host variables
│   │   ├── hosts.yml         # Server inventory
│   │   └── host_vars/        # Host-specific variables
│   ├── roles/                 # Custom Ansible roles
│   │   ├── chezmoi/          # Chezmoi dotfiles management
│   │   ├── docker_compose_modules/  # Modular Docker Compose
│   │   ├── github_ssh_keys/  # GitHub SSH keys management
│   │   └── maintenance/      # Automated maintenance
│   └── scripts/               # Helper scripts
│       ├── ansible-pull.sh   # Ansible-pull wrapper
│       └── tests/            # Test scripts (deprecated)
├── tests/
│   └── bash/                  # Bats test suite
│       ├── run-tests.sh      # Test runner
│       ├── lint-test.bats    # Linting tests
│       ├── syntax-test.bats  # Syntax tests
│       ├── docker-test.bats  # Docker provisioning tests
│       └── ansible-pull-test.bats  # ansible-pull tests
├── .github/
│   └── workflows/
│       ├── ansible-test.yml  # Legacy CI/CD pipeline
│       └── ci.yml            # Bats test CI/CD pipeline
├── INSTALL.md                 # Installation guide
├── LICENSE                    # MIT License
└── README.md                  # This file
```

## Configured Servers

### svlazext (Debian)

Primary Docker host configured with:
- ✅ Docker Engine (geerlingguy.docker)
- ✅ UFW Firewall (HTTP, HTTPS, SSH)
- ✅ Chezmoi dotfiles management
- ✅ Automated ansible-pull updates
- ✅ Automated maintenance (daily and weekly patches)

### svlazextpub (Debian)

DMZ/public-facing Docker host configured with:
- ✅ Docker Engine (geerlingguy.docker)
- ✅ UFW Firewall (HTTP, HTTPS, SSH)
- ✅ Chezmoi dotfiles management
- ✅ Automated ansible-pull updates
- ✅ Automated maintenance (daily and weekly patches)

**Compose Modules**: None (configure as needed)

### svlazdev (Debian)

Development/management server configured with:
- ✅ Automated system setup (ansible user, sudo, SSH)
- ✅ Docker Engine with user group management (geerlingguy.docker)
- ✅ UFW Firewall (SSH)
- ✅ Chezmoi dotfiles management
- ✅ Automated ansible-pull updates
- ✅ Automated maintenance (daily and weekly patches)
- ✅ VS Code Remote Development via SSH
- ✅ Docker support for Remote Devcontainers

**Compose Modules**: None (development server)

## Task Runner

This repository uses [Task](https://taskfile.dev) as a modern task runner / build tool. Task provides a simple way to run common development, testing, and deployment workflows.

### Installation

Install Task using one of these methods:

```bash
# macOS
brew install go-task

# Linux (using snap)
snap install task --classic

# Linux (script install)
sh -c "$(curl --location https://taskfile.dev/install.sh)" -- -d -b /usr/local/bin

# Go
go install github.com/go-task/task/v3/cmd/task@latest

# npm
npm install -g @go-task/cli
```

For more installation options, see the [official documentation](https://taskfile.dev/installation).

### Quick Start with Task

```bash
# Show all available tasks
task --list

# Install all dependencies
task install

# Run all tests
task test

# Run linting only
task lint

# Run full CI pipeline locally
task ci:local

# Show detailed help
task help
```

### Common Task Commands

| Command | Description |
|---------|-------------|
| `task install` | Install all dependencies (Python, Ansible, Bats) |
| `task test` | Run all tests |
| `task test:lint` | Run linting tests only |
| `task test:syntax` | Run syntax validation tests |
| `task lint` | Run yamllint and ansible-lint |
| `task ansible:check` | Dry-run ansible-pull (no changes) |
| `task ansible:pull` | Run ansible-pull (apply configuration) |
| `task ci:local` | Run full CI pipeline locally |
| `task info` | Display environment information |
| `task help` | Show detailed help and examples |

See [Taskfile.yml](Taskfile.yml) for all available tasks.

## Testing

The repository includes comprehensive testing using the [Bats testing framework](https://github.com/bats-core/bats-core):

### Running Tests Locally

With Task (recommended):
```bash
# Run all tests
task test

# Run specific test suite
task test:lint
task test:syntax
task test:docker
```

Without Task:
```bash
# Run all tests
./tests/bash/run-tests.sh

# Run specific test file
./tests/bash/run-tests.sh --test lint-test.bats

# Run in CI mode (installs dependencies, generates JUnit XML)
./tests/bash/run-tests.sh --ci
```

### Test Suite

Tests include:
- **Linting**: yamllint and ansible-lint checks
- **Syntax validation**: Ansible playbooks and shell scripts
- **Docker provisioning**: Installation and configuration
- **ansible-pull functionality**: Script validation and execution
- **GitHub SSH keys**: Role testing with check mode validation

See [tests/bash/README.md](tests/bash/README.md) for detailed testing documentation.

### CI/CD Pipeline

Tests are automatically run via GitHub Actions on:
- Push to `main` or `copilot/**` branches
- Pull requests
- Manual workflow dispatch

Test results are published as GitHub check runs with detailed failure information.

## Usage

### One-line Setup

```bash
curl -fsSL https://raw.githubusercontent.com/DevSecNinja/docker/main/ansible/scripts/ansible-pull.sh | sudo bash
```

### Manual Setup

```bash
# Install Ansible
sudo apt-get update
sudo apt-get install -y ansible git

# Run ansible-pull
sudo ansible-pull \
    --url https://github.com/DevSecNinja/docker.git \
    --checkout main \
    --directory /var/lib/ansible/local \
    --inventory ansible/inventory/hosts.yml \
    --extra-vars "target_host=$(hostname)" \
    --only-if-changed \
    ansible/playbooks/main.yml
```

See [INSTALL.md](INSTALL.md) for detailed instructions.

## Development

### Development Workflow with Task

```bash
# Install dependencies
task install

# Run quick checks before committing
task ci:quick

# Run full CI pipeline locally
task ci:local

# Check what would change on the system
task ansible:check

# Clean temporary files
task dev:clean

# View inventory and variables
task dev:inventory
task dev:vars -- HOST=svlazext
```

### Adding a New Server

1. Add to `ansible/inventory/hosts.yml`:
   ```yaml
   NEWSERVER:
     ansible_host: newserver.local
     ansible_user: ansible
     server_features:
       - docker
       - traefik
   ```

2. (Optional) Add host-specific vars in `ansible/inventory/host_vars/NEWSERVER.yml`

3. Run the installation on the new server

### Adding a New Role

1. Create role structure:
   ```bash
   cd ansible/roles
   mkdir -p newrole/{tasks,defaults,meta,templates,handlers}
   ```

2. Add role to `ansible/playbooks/main.yml`

3. Test with the CI pipeline or locally:
   ```bash
   task lint
   task test
   ```

## CI/CD Pipeline

The GitHub Actions workflow (`ansible-test.yml`) runs on every push and PR:

1. **Lint**: YAML and Ansible linting
2. **Syntax Check**: Validates playbook syntax
3. **Test svlazext**: Tests server provisioning
4. **Test Ansible Pull**: Validates the pull script

## Requirements

- **Ansible**: 2.20 or higher
- **Python**: 3.6 or higher
- **Target OS**: Debian 13 (Trixy) or Ubuntu 24.04+
- **Git**: For ansible-pull functionality

## Contributing

1. Create a feature branch
2. Make your changes
3. Ensure tests pass
4. Submit a pull request

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Author

Jean-Paul van Ravensberg (DevSecNinja)

## Support

For issues or questions, please open an issue in this repository.
