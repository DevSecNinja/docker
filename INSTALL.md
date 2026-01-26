# Installation Guide for New Servers

This guide provides step-by-step instructions for setting up a new server with Ansible Pull configuration.

## Prerequisites

- A fresh Debian 13 (Trixy) or Ubuntu 24.04+ server
- Root or sudo access
- Internet connectivity
- Git installed (if not, will be installed automatically)

## Quick Start

For a quick setup, run the following one-liner on your new server:

```bash
curl -fsSL https://raw.githubusercontent.com/DevSecNinja/docker/main/ansible/scripts/ansible-pull.sh | sudo bash
```

## Manual Installation

### Step 1: Install Dependencies

```bash
# Update package lists
sudo apt-get update

# Install Ansible and Git
sudo apt-get install -y ansible git python3-pip

# Install required Ansible collections
ansible-galaxy collection install community.general ansible.posix community.docker
```

### Step 2: Install External Roles

```bash
# Clone this repository temporarily or install roles directly
ansible-galaxy role install geerlingguy.docker
```

### Step 3: Run Ansible Pull

```bash
# Run ansible-pull to configure the server
sudo ansible-pull \
    --url https://github.com/DevSecNinja/docker.git \
    --checkout main \
    --directory /var/lib/ansible/local \
    --inventory ansible/inventory/hosts.yml \
    --extra-vars "target_host=$(hostname)" \
    --only-if-changed \
    ansible/playbooks/main.yml
```

## Server-Specific Configuration

### SVLAZDOCK1 Configuration

For SVLAZDOCK1, ensure the following:

1. Hostname is set correctly:
   ```bash
   sudo hostnamectl set-hostname SVLAZDOCK1
   ```

2. Create an `ansible` user (recommended):
   ```bash
   sudo adduser ansible
   sudo usermod -aG sudo ansible
   echo "ansible ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/ansible
   ```

3. (Optional) Set up Chezmoi dotfiles repository URL in host variables:
   ```bash
   # Create host_vars file
   sudo mkdir -p /var/lib/ansible/local/ansible/inventory/host_vars
   sudo tee /var/lib/ansible/local/ansible/inventory/host_vars/SVLAZDOCK1.yml <<EOF
   ---
   chezmoi_repo_url: "https://github.com/YourUsername/dotfiles.git"
   EOF
   ```

### SVLAZDEV1 Configuration

For SVLAZDEV1 (Development/Management Server), ensure the following:

1. Hostname is set correctly:
   ```bash
   sudo hostnamectl set-hostname SVLAZDEV1
   ```

2. Create an `ansible` user (recommended):
   ```bash
   sudo adduser ansible
   sudo usermod -aG sudo ansible
   echo "ansible ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/ansible
   ```

3. Add your user to the docker group for VS Code Remote Devcontainers:
   ```bash
   sudo usermod -aG docker $USER
   newgrp docker
   ```

4. (Optional) Set up Chezmoi dotfiles repository URL in host variables:
   ```bash
   # Create host_vars file
   sudo mkdir -p /var/lib/ansible/local/ansible/inventory/host_vars
   sudo tee /var/lib/ansible/local/ansible/inventory/host_vars/SVLAZDEV1.yml <<EOF
   ---
   chezmoi_repo_url: "https://github.com/YourUsername/dotfiles.git"
   EOF
   ```

5. Ensure SSH access is properly configured for VS Code Remote Development:
   ```bash
   # Verify SSH service is running
   sudo systemctl status ssh
   
   # Test SSH access from your local machine
   ssh ansible@svlazdev1.local
   ```

## Automated Runs with Cron

To automatically check for configuration updates, set up a cron job:

```bash
# Create a cron job to run every hour
sudo tee /etc/cron.d/ansible-pull <<EOF
# Run ansible-pull every hour to check for configuration updates
0 * * * * root /var/lib/ansible/local/ansible/scripts/ansible-pull.sh
EOF
```

Or use systemd timer (recommended for better logging):

```bash
# Create systemd service
sudo tee /etc/systemd/system/ansible-pull.service <<EOF
[Unit]
Description=Ansible Pull Service
After=network-online.target

[Service]
Type=oneshot
ExecStart=/var/lib/ansible/local/ansible/scripts/ansible-pull.sh
User=root
StandardOutput=journal
StandardError=journal
EOF

# Create systemd timer
sudo tee /etc/systemd/system/ansible-pull.timer <<EOF
[Unit]
Description=Run Ansible Pull Hourly
Requires=ansible-pull.service

[Timer]
OnBootSec=5min
OnUnitActiveSec=1h
Unit=ansible-pull.service

[Install]
WantedBy=timers.target
EOF

# Enable and start the timer
sudo systemctl daemon-reload
sudo systemctl enable ansible-pull.timer
sudo systemctl start ansible-pull.timer
```

## Verification

### Check Ansible Pull Status

```bash
# Check the last run log
sudo tail -f /var/log/ansible-pull.log

# For systemd timer setup
sudo journalctl -u ansible-pull.service -f
```

### Verify Docker Installation

```bash
# Check Docker version
docker --version

# Check Docker service status
sudo systemctl status docker

# Test Docker
sudo docker run hello-world
```

### Verify Traefik Deployment

```bash
# Check if Traefik container is running
sudo docker ps | grep traefik

# Access Traefik dashboard (if enabled)
# Open browser to http://<server-ip>:8080
```

### Verify Chezmoi Installation

```bash
# Check Chezmoi version
chezmoi --version

# Check Chezmoi status
chezmoi status
```

## Troubleshooting

### Ansible Pull Fails

1. Check the log file:
   ```bash
   sudo tail -100 /var/log/ansible-pull.log
   ```

2. Run ansible-pull manually with verbose output:
   ```bash
   sudo ansible-pull -vvv \
       --url https://github.com/DevSecNinja/docker.git \
       --checkout main \
       --directory /var/lib/ansible/local \
       --inventory ansible/inventory/hosts.yml \
       --extra-vars "target_host=$(hostname)" \
       ansible/playbooks/main.yml
   ```

### Docker Installation Issues

1. Check Docker service:
   ```bash
   sudo systemctl status docker
   sudo journalctl -u docker -n 50
   ```

2. Verify Docker group membership:
   ```bash
   groups
   # If you're not in the docker group:
   sudo usermod -aG docker $USER
   newgrp docker
   ```

### Traefik Issues

1. Check container logs:
   ```bash
   sudo docker logs traefik
   ```

2. Verify configuration:
   ```bash
   sudo cat /etc/traefik/traefik.yml
   ```

### Network Connectivity Issues

1. Ensure firewall allows required ports:
   ```bash
   # For UFW
   sudo ufw allow 80/tcp
   sudo ufw allow 443/tcp
   sudo ufw allow 8080/tcp
   ```

## Adding New Servers

To add a new server to the infrastructure:

1. Add the server to `ansible/inventory/hosts.yml`:
   ```yaml
   all:
     children:
       docker_servers:
         hosts:
           SVLAZDOCK1:
             ansible_host: svlazdock1.local
             # ... existing config ...
           NEWSERVER:
             ansible_host: newserver.local
             ansible_user: ansible
             ansible_become: true
             server_features:
               - docker
               # Add other features as needed
   ```

2. (Optional) Create host-specific variables in `ansible/inventory/host_vars/NEWSERVER.yml`

3. Run the installation steps on the new server

## Security Notes

- This setup currently has no secrets management configured
- Traefik dashboard is accessible without authentication in the default setup
- For production use, implement:
  - Secrets management (Ansible Vault, HashiCorp Vault, etc.)
  - Authentication for Traefik dashboard
  - SSL/TLS certificates (Let's Encrypt integration)
  - Firewall rules
  - SSH key-based authentication

## Next Steps

- Configure Chezmoi with your dotfiles repository
- Set up SSL certificates for Traefik
- Add more services and containers
- Implement secrets management
- Configure monitoring and logging

## Support

For issues or questions, please open an issue in the repository.
