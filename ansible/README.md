# Ansible Infrastructure Setup

This repository contains Ansible configurations for automated server provisioning using Ansible Pull.

## Overview

This setup uses **Ansible Pull** for automated configuration management, allowing servers to pull their configuration from this Git repository and apply changes automatically.

### Features

- ✅ Ansible Pull configuration with Git commit checking
- ✅ Support for multiple roles and servers
- ✅ Docker installation (using geerlingguy.docker role)
- ✅ Traefik reverse proxy deployment
- ✅ Chezmoi dotfiles management
- ✅ UFW firewall configuration
- ✅ Automated ansible-pull setup (cron or systemd)
- ✅ Well-structured for future growth

### Architecture

```
ansible/
├── ansible.cfg              # Ansible configuration
├── requirements.yml         # External roles and collections
├── playbooks/
│   └── main.yml            # Main playbook for ansible-pull
├── inventory/
│   ├── hosts.yml           # Inventory with server definitions
│   └── host_vars/          # Host-specific variables
├── roles/
│   ├── chezmoi/            # Chezmoi dotfiles role
│   └── traefik/            # Traefik reverse proxy role
└── scripts/
    └── ansible-pull.sh     # Ansible-pull wrapper script
```

## Configured Servers

### SVLAZDOCK1 (Debian)

Primary Docker host with the following features:
- Docker Engine (via geerlingguy.docker role)
- UFW firewall with HTTP/HTTPS/SSH access
- Traefik reverse proxy (deployed via Docker Compose)
- Chezmoi dotfiles management
- Automated ansible-pull updates

## Getting Started

See [INSTALL.md](INSTALL.md) for detailed installation instructions.

## Testing

The repository includes a GitHub Actions workflow that tests the Ansible setup in a containerized environment.

## Requirements

- Ansible 2.9+
- Git
- Python 3.6+
- Target systems: Debian 11+ or Ubuntu 20.04+

## License

MIT License - see [LICENSE](../LICENSE) file for details.
