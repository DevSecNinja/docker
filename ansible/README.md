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
- ✅ Automated maintenance with scheduled updates
- ✅ Well-structured for future growth

### Architecture

```
../ansible.cfg               # Ansible configuration (for ansible-pull from repo root)
ansible/
├── ansible.cfg              # Ansible configuration (for local development)
├── requirements.yml         # External roles and collections
├── playbooks/
│   ├── main.yml            # Main playbook for ansible-pull
│   ├── maintenance-update.yml   # Update config & Docker images
│   ├── maintenance-daily.yml    # Daily OS patches
│   └── maintenance-weekly.yml   # Weekly full patches with reboot
├── inventory/
│   ├── hosts.yml           # Inventory with server definitions
│   └── host_vars/          # Host-specific variables
├── roles/
│   ├── chezmoi/            # Chezmoi dotfiles role
│   ├── maintenance/        # Maintenance automation role
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
- Automated maintenance with daily and weekly patch schedules

## Getting Started

See [INSTALL.md](INSTALL.md) for detailed installation instructions.

## Maintenance Automation

The maintenance role provides automated server maintenance with three types of tasks:

### 1. Configuration and Docker Image Updates
**Playbook**: `maintenance-update.yml`

Pulls the latest Ansible configuration and updates Docker images:
- Pulls latest changes from Git repository
- Updates chezmoi dotfiles
- Pulls and restarts Docker Compose services with updated images

### 2. Daily OS Patches (Non-disturbing)
**Playbook**: `maintenance-daily.yml`  
**Schedule**: Daily at 8 PM

Applies safe OS updates without disrupting services:
- Updates packages except Docker Engine and kernel
- Excludes updates requiring reboot
- Safe to run on production systems

### 3. Weekly Full Patches
**Playbook**: `maintenance-weekly.yml`  
**Schedule**: Saturday at 8 AM

Performs comprehensive system updates:
- Applies all available OS updates
- Includes Docker Engine and kernel updates
- Automatically reboots if required

### Managing Maintenance

```bash
# Check timer status
systemctl list-timers maintenance-*

# View maintenance logs from systemd journal
journalctl -u maintenance-daily.service -f
journalctl -u maintenance-weekly.service -f

# View recent logs
journalctl -u maintenance-daily.service --since today
journalctl -u maintenance-weekly.service --since "1 week ago"

# Manually run maintenance playbooks
ansible-playbook playbooks/maintenance-daily.yml \
  --inventory inventory/hosts.yml \
  --extra-vars "target_host=$(hostname)"
```

### Configuration

Enable maintenance in your host configuration:

```yaml
server_features:
  - maintenance
```

Customize maintenance settings in `host_vars/`:

```yaml
maintenance_timezone: "Europe/Amsterdam"
maintenance_daily_enabled: true
maintenance_daily_schedule: "20:00"  # 8 PM
maintenance_weekly_enabled: true
maintenance_weekly_schedule: "Sat *-*-* 08:00:00"  # Saturday 8 AM
maintenance_weekly_reboot_enabled: true
```

## Testing

The repository includes a GitHub Actions workflow that tests the Ansible setup in a containerized environment.

## Requirements

- Ansible 2.20+
- Git
- Python 3.6+
- Target systems: Debian 13 (Trixy) or Ubuntu 24.04+

## License

MIT License - see [LICENSE](../LICENSE) file for details.
