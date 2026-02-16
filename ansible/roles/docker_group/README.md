# Docker Group Role

## Overview

This role ensures the Docker group is created with a static GID before Docker installation. This is important for consistency across multiple servers, especially when sharing files or using NFS mounts with Docker containers.

## Purpose

The `geerlingguy.docker` role installs Docker packages which automatically create the `docker` group, but without a predictable GID. This role pre-creates the group with a specific GID to ensure consistency across your infrastructure.

## Variables

### Defaults

```yaml
docker_group_gid: 780
docker_group_name: docker
```

- `docker_group_gid`: The static GID for the Docker group (default: 780)
- `docker_group_name`: The name of the Docker group (default: docker)

### Customization

You can override the default GID in your inventory or host_vars:

```yaml
# In ansible/inventory/host_vars/YOURSERVER.yml
docker_group_gid: 998
```

Or globally in group_vars:

```yaml
# In ansible/inventory/group_vars/application_servers.yml
docker_group_gid: 780
```

## Usage

This role is automatically included in the main playbook before `geerlingguy.docker` when the `docker` feature is enabled:

```yaml
server_features:
  - docker
```

## Dependencies

None. This role should be run before the `geerlingguy.docker` role.

## Order in Playbook

This role must be executed **before** `geerlingguy.docker` to ensure the group exists with the correct GID before Docker installation.

## Tags

- `docker`
- `docker_group`

## Example

Run only this role:

```bash
ansible-pull \
  --url https://github.com/DevSecNinja/docker.git \
  --checkout main \
  --directory /var/lib/ansible/local \
  --inventory ansible/inventory/hosts.yml \
  --extra-vars "target_host=$(hostname)" \
  --tags "docker_group" \
  ansible/playbooks/main.yml
```
