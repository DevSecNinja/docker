# Docker Infrastructure

Automated infrastructure management using Ansible Pull for Docker-based services.

## Overview

This repository contains Ansible configurations for automated server provisioning and management. It uses **Ansible Pull** approach, where servers pull their configuration from this repository and apply changes automatically when Git commits are detected.

## Features

- 🔄 **Ansible Pull Configuration**: Servers automatically pull and apply configurations
- 🐳 **Docker Management**: Automated Docker installation and configuration
- 🐙 **Modular Docker Compose**: Easily add/remove compose modules per server
- 🔥 **UFW Firewall**: Automated firewall configuration with sensible defaults
- 🌐 **Traefik Module**: Reverse proxy as a compose module
- 📦 **Chezmoi Integration**: Dotfiles management support
- ⚙️ **Automated Updates**: Self-configuring ansible-pull with cron or systemd
- 🧪 **CI/CD Testing**: GitHub Actions with reusable test scripts
- 📈 **Scalable Structure**: Easy to add new servers and modules

## Quick Start

For new servers, see the [Installation Guide](INSTALL.md).

For Ansible documentation and structure, see [ansible/README.md](ansible/README.md).

## Repository Structure

```
.
├── ansible/                    # Ansible configuration directory
│   ├── ansible.cfg            # Ansible configuration
│   ├── requirements.yml       # External roles and collections
│   ├── playbooks/             # Ansible playbooks
│   │   └── main.yml          # Main playbook for ansible-pull
│   ├── inventory/             # Inventory and host variables
│   │   ├── hosts.yml         # Server inventory
│   │   └── host_vars/        # Host-specific variables
│   ├── roles/                 # Custom Ansible roles
│   │   ├── chezmoi/          # Chezmoi dotfiles management
│   │   └── traefik/          # Traefik reverse proxy
│   └── scripts/               # Helper scripts
│       └── ansible-pull.sh   # Ansible-pull wrapper
├── .github/
│   └── workflows/
│       └── ansible-test.yml  # CI/CD testing pipeline
├── INSTALL.md                 # Installation guide
├── LICENSE                    # MIT License
└── README.md                  # This file
```

## Configured Servers

### SVLAZDOCK1 (Debian)

Primary Docker host configured with:
- ✅ Docker Engine (geerlingguy.docker)
- ✅ UFW Firewall (HTTP, HTTPS, SSH, Traefik dashboard)
- ✅ Traefik (via compose module)
- ✅ Chezmoi dotfiles management
- ✅ Automated ansible-pull updates

**Compose Modules**: `traefik`

## Testing

The repository includes comprehensive testing via GitHub Actions:

```bash
# Tests are automatically run on:
# - Push to main or copilot/** branches
# - Pull requests
# - Manual workflow dispatch
```

Tests include:
- YAML and Ansible linting
- Syntax checking
- Docker role installation
- Ansible-pull functionality

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

3. Test with the CI pipeline

## CI/CD Pipeline

The GitHub Actions workflow (`ansible-test.yml`) runs on every push and PR:

1. **Lint**: YAML and Ansible linting
2. **Syntax Check**: Validates playbook syntax
3. **Test SVLAZDOCK1**: Tests server provisioning
4. **Test Ansible Pull**: Validates the pull script

## Requirements

- **Ansible**: 2.9 or higher
- **Python**: 3.6 or higher
- **Target OS**: Debian 13 (Trixy) or Ubuntu 24.04+
- **Git**: For ansible-pull functionality

## Roadmap

- [ ] Secrets management (Ansible Vault)
- [ ] SSL/TLS certificate automation (Let's Encrypt)
- [ ] Traefik authentication
- [ ] Monitoring and logging setup
- [ ] Additional service containers
- [ ] Backup and recovery procedures

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
