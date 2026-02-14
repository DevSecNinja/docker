# Architecture: Docker Compose Module System

**Status**: Draft — February 14, 2026

**Author**: Jean-Paul van Ravensberg (DevSecNinja) with AI assistance

**Repository**: <https://github.com/DevSecNinja/docker> (public)

---

## Table of Contents

- [1. Overview](#1-overview)
- [2. Goals & Requirements](#2-goals--requirements)
- [3. Design Decisions](#3-design-decisions)
- [4. Server Classification & Environments](#4-server-classification--environments)
- [5. Module System](#5-module-system)
- [6. Network Isolation](#6-network-isolation)
- [7. Secret Management (SOPS)](#7-secret-management-sops)
- [8. Traefik Integration](#8-traefik-integration)
- [9. Traefik Forward Auth](#9-traefik-forward-auth)
- [10. Gatus Healthcheck Generation](#10-gatus-healthcheck-generation)
- [11. Image Pinning & Renovate](#11-image-pinning--renovate)
- [12. Configuration Layering](#12-configuration-layering)
- [13. Docker Compose Validation & Best Practices](#13-docker-compose-validation--best-practices)
- [14. DNS Management (AdGuard + Unbound)](#14-dns-management-adguard--unbound)
- [15. Cleanup & Lifecycle](#15-cleanup--lifecycle)
- [16. Validation & Post-Deployment Checks](#16-validation--post-deployment-checks)
- [17. Dry-Run Support](#17-dry-run-support)
- [18. Testing Strategy](#18-testing-strategy)
- [19. Backup Strategy (Roadmap)](#19-backup-strategy-roadmap)
- [20. Auto-Generated Service Inventory (Roadmap)](#20-auto-generated-service-inventory-roadmap)
- [21. Auto-Merge & Update Strategy (Roadmap)](#21-auto-merge--update-strategy-roadmap)
- [22. AI Authoring & Module Templates](#22-ai-authoring--module-templates)
- [23. Implementation Order](#23-implementation-order)
- [24. Open Questions](#24-open-questions)

---

## 1. Overview

This repository uses **Ansible Pull** to manage Docker-based infrastructure. Servers pull
their configuration from Git and apply changes automatically when new commits are detected.

The **Docker Compose Module System** extends this by allowing declarative, per-server
selection of containerised applications. Each application is a self-contained "module" that
carries its own Compose file, configuration templates, network definitions, healthcheck
config, and secret references.

### High-Level Flow

```
Git push → ansible-pull detects change → plays main.yml
  → server_features gates which roles run
  → compose_modules list selects which modules deploy
  → validate secrets (pre-flight — abort if missing)
  → validate Compose files (lint + best-practice checks)
  → each module:
      1. create networks
      2. decrypt secrets (SOPS)
      3. deploy generic + host-specific configs
      4. render & validate docker-compose.yml
      5. docker compose up
      6. generate Gatus healthcheck
      7. generate DNS records for Unbound
      8. run post-deploy validation
  → orphan cleanup removes modules no longer listed
  → validation report written
```

---

## 2. Goals & Requirements

### Functional Requirements

| ID    | Requirement | Priority |
|-------|-------------|----------|
| FR-1  | Select which applications land on which server / server group | Must |
| FR-2  | Generic configs shared across servers + host/group-specific overrides | Must |
| FR-3  | Automatic cleanup when an application is removed from a server | Must |
| FR-4  | All web frontends routed through Traefik — no direct port exposure | Must |
| FR-5  | Per-application network isolation (frontend + backend networks) | Must |
| FR-6  | Encrypted secrets stored in the public repo using SOPS + Age | Must |
| FR-7  | Generic secrets (per server group) and host-specific secrets | Must |
| FR-8  | Automatic Gatus healthcheck generation per deployed module | Must |
| FR-9  | Post-deployment validation (container health, HTTP, routing) | Must |
| FR-10 | Dev / Production environment support (single branch, host-level flag) | Must |
| FR-11 | Dev server deploys all modules from `main` branch | Must |
| FR-12 | Docker images pinned by version AND SHA digest for Renovate | Must |
| FR-13 | Module template folder for AI and human authoring | Must |
| FR-14 | Secrets must be writable by AI agents without manual copy/paste | Must |
| FR-15 | Ports must not be exposed unless absolutely necessary (e.g., DNS 53, HTTP 80/443) | Must |
| FR-16 | Dry-run support to preview changes without applying | Must |
| FR-17 | Pre-deployment secret validation — abort if secrets are empty or undecryptable | Must |
| FR-18 | Docker Compose validation with enforced best practices | Must |
| FR-19 | Traefik forward auth on all protected services | Must |
| FR-20 | DNS management via AdGuard + Unbound with auto-generated records | Must |
| FR-21 | Automated tests for all roles, modules, and Compose files (Bats) | Must |
| FR-22 | Backup to Azure Blob Storage | Roadmap |
| FR-23 | Auto-generated service inventory / documentation | Roadmap |
| FR-24 | Auto-merge / update strategy for Renovate PRs | Roadmap |
| FR-25 | Secrets delivered to containers via templated `.env` files (no cleartext in Git) | Must |
| FR-26 | DNS runs on one or more infrastructure server(s); resolver config via DHCP, not Ansible | Must |
| FR-27 | Gatus must be able to monitor services behind forward auth (health bypass route) | Must |
| FR-28 | Compose validation must run in CI pipeline before deployment, not only at deploy time | Must |

### Non-Functional Requirements

| ID    | Requirement | Target |
|-------|-------------|--------|
| NFR-1 | Full sync time (ansible-pull) | < 2 minutes |
| NFR-2 | Incremental sync (no changes) | < 30 seconds |
| NFR-3 | Public repository — no plaintext secrets | Always |
| NFR-4 | Offline-capable deployment (no cloud dependency at runtime) | Always |
| NFR-5 | Testable in CI (GitHub Actions) | Always |

---

## 3. Design Decisions

| ID    | Decision | Choice | Rationale |
|-------|----------|--------|-----------|
| DD-1  | Orchestration | Ansible Pull (this repo) | Single source of truth; no management-server SPOF; already proven |
| DD-2  | Alternative rejected | Komodo | Extra layer, separate repo, network dependency, more operational overhead |
| DD-3  | Secrets | SOPS + Age | Git-native, offline, simple key model, CI-friendly, AI-writable |
| DD-4  | Secret backend rejected | Azure Key Vault | Network dependency at deploy time; costly for small fleet |
| DD-5  | Secret key distribution | Age private key injected via `ansible-pull.sh` at onboarding | One-time manual step; key stored at `/root/.config/sops/age/keys.txt` |
| DD-6  | Shared group keys | One Age key pair per server group; private key distributed to all group members at onboarding | Enables group-level secrets without listing every server key; see §7 |
| DD-7  | Secret validation | Pre-flight assertion that all required vars are non-empty before deployment | Prevents deploying containers with missing secrets causing broken state |
| DD-8  | Healthchecks | Auto-generated Gatus YAML per module; internal Docker DNS for validation | Self-documenting; automatic cleanup; no exposed ports needed for checks |
| DD-9  | Network model | Per-app `<app>-frontend` + `<app>-backend`; Traefik joins every frontend | Maximum isolation; no god network; Traefik only sees what it needs |
| DD-10 | Port exposure | No host ports exposed except Traefik (80/443) and essential services (DNS 53) | Minimise attack surface; all web traffic through Traefik |
| DD-11 | Volumes | Hybrid — bind mounts for Ansible-managed configs; named volumes for app data | Best of both worlds; Ansible controls configs, Docker manages data |
| DD-12 | Image tags | Version + SHA digest (`image:tag@sha256:...`) | Deterministic builds; Renovate can auto-bump both |
| DD-13 | Config layering | Generic (all) → group (server type) → host-specific | Flexible; minimal duplication |
| DD-14 | Environments | Single branch (`main`); dev server uses `deploy_all_modules: true` | No branch drift; dev simply deploys every module; auto-merge strategy on roadmap |
| DD-15 | Module templates | Maintained in `ansible/roles/docker_compose_modules/templates/_template/` | Enables AI agents and humans to scaffold new modules quickly |
| DD-16 | Cleanup | Orphan detection + `docker compose down` for removed modules | Prevents stale containers, networks, and optionally volumes |
| DD-17 | Compose validation | Automated linting with enforced best practices (registry prefix, SHA, no-new-privileges, etc.) | Catches misconfigurations before deployment; consistent security posture |
| DD-18 | DNS management | AdGuard (filtering + local DNS) + Unbound (recursive resolver); records auto-generated | Eliminates manual DNS entry; self-healing when modules change |
| DD-19 | Forward auth | `traefik-forward-auth` on all protected services | Centralised authentication; deployed before any application modules |
| DD-20 | Dry-run | `ansible-pull --check` + `docker compose config` | Safe preview of all changes; no side effects |
| DD-21 | Backup tools | `offen/docker-volume-backup` for volumes; `tiredofit/docker-db-backup` for databases | Purpose-built; lightweight; container-native |
| DD-22 | Testing | Bats tests for roles, modules, Compose validation, and integration | Comprehensive coverage; same framework as existing tests |
| DD-23 | Database migrations | Roadmap — label major/minor DB packages as critical in Renovate | Filter manually for now; automate later |
| DD-24 | Resource limits | Optional per module; recommended but not enforced | Prevents runaway containers without adding mandatory complexity |
| DD-25 | Private registry | Not needed — public registries sufficient | No rate-limit concerns for current fleet size |
| DD-26 | Secrets → containers | SOPS → Ansible vars → templated `.env` file → `env_file:` in Compose | Keeps compose templates free of Jinja secret refs; `.env` is `0600` root-only; see §7 |
| DD-27 | DNS deployment | AdGuard + Unbound on **one or more infrastructure server(s)**; other hosts use it as resolver | Centralised DNS; records generated from module vars across all hosts; see §14 |
| DD-28 | Gatus behind auth | Traefik bypass route for health path — only created when `healthcheck.path` is defined in module vars | Not every image has a health endpoint; bypass route is opt-in per module; see §10 |
| DD-29 | Compose validation timing | Shift-left: CI (Bats + `docker compose config` with mock vars) **and** deploy-time (defense in depth) | Catch errors before merge; deploy-time catches real-variable issues; see §13 |
| DD-30 | DNS record generation | Static from inventory + module vars (not cross-host facts) | ansible-pull has no cross-host fact gathering; static approach is deterministic; see §14 |
| DD-31 | Multi-host module DNS | Single-host: `app.example.com`; multi-host: `app-hostname.example.com` | Avoid ambiguous DNS; host-qualified names only when module runs on multiple hosts; see §14 |

---

## 4. Server Classification & Environments

### Inventory Structure

```yaml
# ansible/inventory/hosts.yml
---
all:
  children:
    # ── Role-based groups (servers can appear in multiple) ──
    infrastructure_servers:
      hosts:
        svlazinfra1:
      vars:
        server_type: infrastructure

    application_servers:
      hosts:
        svlazdock1:
      vars:
        server_type: application

    development_servers:
      hosts:
        svlazdev1:
      vars:
        server_type: development

    dmz_servers:
      vars:
        server_type: dmz
```

### Environment Behaviour

All servers track the `main` branch. The dev server simply deploys every available module.
An auto-merge / update strategy for Renovate PRs is on the roadmap (see §21).

| Environment | Branch | Module selection | Secrets |
|-------------|--------|------------------|---------|
| Production  | `main` | Explicit per-host `compose_modules` list | Production secrets (group + host) |
| Dev / Test  | `main` | All modules (`deploy_all_modules: true`) | Dev/test secrets (group + host) |

### Host Variables Example

```yaml
# ansible/inventory/host_vars/svlazdock1.yml
---
server_type: application
environment: production

compose_modules:
  - traefik
  - forward_auth
  - portainer
  - homepage
  - vaultwarden
```

```yaml
# ansible/inventory/host_vars/svlazdev1.yml
---
server_type: development
environment: development
deploy_all_modules: true       # deploys every module found in vars/modules/

compose_modules: []            # ignored when deploy_all_modules is true
```

---

## 5. Module System

### Directory Layout

```
ansible/roles/docker_compose_modules/
├── defaults/
│   └── main.yml                          # Default variables
├── meta/
│   └── main.yml                          # Role metadata
├── tasks/
│   ├── main.yml                          # Entrypoint
│   ├── resolve_modules.yml               # Build effective module list
│   ├── create_networks.yml               # Pre-create Docker networks
│   ├── deploy_module.yml                 # Deploy a single module
│   ├── validate_module.yml               # Post-deploy checks
│   ├── cleanup_orphans.yml               # Remove unlisted modules
│   └── generate_gatus.yml               # Write Gatus endpoint config
├── templates/
│   ├── _template/                        # ★ Module scaffold template
│   │   ├── docker-compose.yml.j2
│   │   ├── module.yml.j2                # Module vars template
│   │   └── README.md                    # How to create a module
│   ├── gatus-endpoint.yml.j2            # Shared Gatus template
│   └── modules/
│       ├── traefik/
│       │   ├── docker-compose.yml.j2
│       │   └── config/
│       │       ├── generic/
│       │       │   └── traefik.yml.j2
│       │       └── specific/
│       │           └── svlazdock1-dynamic.yml.j2
│       ├── adguard/
│       │   ├── docker-compose.yml.j2
│       │   └── config/
│       │       ├── generic/
│       │       │   └── AdGuardHome.yaml.j2
│       │       └── specific/
│       └── portainer/
│           └── docker-compose.yml.j2
└── vars/
    └── modules/
        ├── traefik.yml
        ├── adguard.yml
        └── portainer.yml
```

### Module Definition Schema

Every module has a variables file in `vars/modules/<name>.yml`:

```yaml
# vars/modules/adguard.yml
---
# ── Targeting ──
target_server_types:                # deploy only on these server types
  - infrastructure
# target_hosts:                     # OR pin to specific hosts
#   - svlazinfra1

# ── Service type (enforces Traefik policy) ──
service_type: web                   # web | internal | backend

# ── Image (pinned for Renovate — MUST include registry + SHA) ──
adguard_image: docker.io/adguard/adguardhome:v0.107.52@sha256:abc123...

# ── Required secrets (pre-flight validation — deployment aborts if any are empty) ──
required_secrets:
  - adguard_admin_password

# ── Extra env vars (non-secret, written to .env alongside secrets) ──
# env_extra:
#   - name: SOME_VAR
#     value: "some_value"

# ── Directories to create on the host ──
config_dirs:
  - "{{ compose_modules_base_dir }}/adguard/data"

# ── Generic configs (deployed to ALL servers running this module) ──
config_files_generic:
  - src: generic/AdGuardHome.yaml.j2
    dest: "{{ compose_modules_base_dir }}/adguard/config/AdGuardHome.yaml"
    mode: "0644"

# ── Host-specific configs (auto-detected by inventory_hostname) ──
# Place files at: templates/modules/adguard/config/specific/<hostname>-<name>.yml.j2
# They are discovered automatically; no listing needed.

# ── Volumes ──
volumes:
  named:
    - adguard_data:/opt/adguardhome/work
  bind:
    - "{{ compose_modules_base_dir }}/adguard/config:/opt/adguardhome/conf:ro"

# ── Networks ──
networks:
  frontend: true                    # creates adguard-frontend; Traefik joins
  backend: false                    # no backend network needed

# ── Exposed host ports (ONLY when absolutely necessary — must be justified) ──
# Most modules should NOT expose ports. Traffic goes through Traefik.
exposed_ports:
  - host: 53
    container: 53
    protocol: udp
    reason: "DNS must be directly accessible on the network"
  - host: 53
    container: 53
    protocol: tcp
    reason: "DNS over TCP for large responses"

# ── Traefik routing ──
traefik:
  enabled: true
  host: "adguard.{{ domain }}"
  port: 3000
  middlewares:
    - secure-headers
    - forward-auth                  # require auth (omit for public-facing services)
  network: "adguard-frontend"

# ── Gatus healthcheck ──
healthcheck:
  enabled: true
  name: "AdGuard Home"
  group: "Infrastructure"
  url: "https://adguard.{{ domain }}"
  path: "/healthz"                          # health bypass route (skips forward auth); optional
  interval: 5m
  conditions:
    - "[STATUS] == 200"
    - "[RESPONSE_TIME] < 1000"
    - "[CERTIFICATE_EXPIRATION] > 48h"
  alerts:
    - type: discord

# ── DNS record (auto-generated for Unbound) ──
dns:
  enabled: true                     # auto-creates local DNS entry based on traefik.host

# ── Resource limits (optional) ──
resources:
  limits:
    cpus: "1.0"
    memory: 512M
  reservations:
    cpus: "0.25"
    memory: 128M

# ── Validation ──
validation:
  critical: true
```

### Module Resolution Logic

```yaml
# tasks/resolve_modules.yml
---
# If deploy_all_modules is true (dev server), discover every module definition
- name: Discover all available modules
  ansible.builtin.find:
    paths: "{{ role_path }}/vars/modules"
    patterns: "*.yml"
    file_type: file
  register: all_module_files
  delegate_to: localhost
  when: deploy_all_modules | default(false)

- name: Build effective module list (dev — all modules)
  ansible.builtin.set_fact:
    effective_modules: >-
      {{ all_module_files.files | map(attribute='path') | map('basename') |
         map('regex_replace', '\.yml$', '') | list }}
  when: deploy_all_modules | default(false)

- name: Build effective module list (normal — from compose_modules)
  ansible.builtin.set_fact:
    effective_modules: "{{ compose_modules | default([]) }}"
  when: not (deploy_all_modules | default(false))
```

---

## 6. Network Isolation

### Model

Every module with `networks.frontend: true` gets a dedicated `<module>-frontend` bridge
network. Traefik joins **all** frontend networks. Modules that also need a private
backend network get `<module>-backend` with `internal: true` (no internet access).

```
┌─────────────────────────────────────────────────────────────────────┐
│ Host                                                                │
│                                                                     │
│  ┌─────────┐                                                        │
│  │ Traefik │──┬── app1-frontend ──── app1-web                       │
│  │         │  │                        │                             │
│  │         │  │                    app1-backend ──── app1-db         │
│  │         │  │                                                     │
│  │         │  ├── app2-frontend ──── app2-web                       │
│  │         │  │                        │                             │
│  │         │  │                    app2-backend ──── app2-redis      │
│  │         │  │                                                     │
│  │         │  └── adguard-frontend ── adguard                       │
│  └─────────┘                                                        │
└─────────────────────────────────────────────────────────────────────┘
```

### Rules

1. **No single shared Traefik network.**
2. Traefik's Compose file is rendered dynamically to include every `*-frontend` network
   as external.
3. Backend networks are `internal: true` — containers on them cannot reach the internet.
4. Each module's web-facing service sets `traefik.docker.network=<module>-frontend` in its
   labels so Traefik knows which network to route through.
5. Database / cache / worker containers connect **only** to the backend network.

### Network Pre-Creation

Networks are created before any Compose stack starts, so they exist as `external: true`
references in both the module's and Traefik's Compose file.

---

## 7. Secret Management (SOPS)

### Architecture

```
SOPS + Age
│
├── Age key pair per server (generated at onboarding)
├── Age key pair per server group (shared among group members)
├── Admin key (used by AI agents and administrators for encryption)
│
├── Encrypted files live in Git:
│   ansible/
│   ├── inventory/
│   │   ├── group_vars/
│   │   │   ├── all/
│   │   │   │   └── secrets.sops.yml          # Generic secrets (all servers)
│   │   │   ├── infrastructure_servers/
│   │   │   │   └── secrets.sops.yml          # Infra group secrets
│   │   │   ├── application_servers/
│   │   │   │   └── secrets.sops.yml          # App group secrets
│   │   │   ├── dmz_servers/
│   │   │   │   └── secrets.sops.yml          # DMZ group secrets
│   │   │   └── development_servers/
│   │   │       └── secrets.sops.yml          # Dev/test secrets
│   │   └── host_vars/
│   │       ├── svlazdock1/
│   │       │   └── secrets.sops.yml          # Host-specific secrets
│   │       └── svlazdev1/
│   │           └── secrets.sops.yml          # Host-specific secrets
│   └── .sops.yaml                            # SOPS config — maps paths → Age keys
```

### Shared Group Keys — How It Works

Instead of listing every individual server key in group-level secret files, each server
group has **one shared Age key pair**:

1. **Generate** one Age key pair per group (e.g., `infrastructure_servers`, `application_servers`).
2. **Distribute** the group's private key to all servers in that group during onboarding.
3. **Encrypt** group-level secrets to the group's public key (+ admin key).
4. **Any member** of the group can decrypt its group's secrets.

```bash
# Generate a group key
age-keygen -o infrastructure_servers.key
# Public key: age1infra...  (goes into .sops.yaml)
# Private key: AGE-SECRET-KEY-1...  (distributed to all infra servers)
```

Each server receives **two keys** at onboarding:
- Its own host-specific private key (decrypts `host_vars/<hostname>/secrets.sops.yml`)
- Its group's shared private key (decrypts `group_vars/<group>/secrets.sops.yml`)

Both keys are stored in `/root/.config/sops/age/keys.txt` (one per line — Age supports
multiple keys in a single file).

### SOPS Configuration

```yaml
# ansible/.sops.yaml
---
creation_rules:
  # Host-specific secrets — encrypted to the host's own key + admin key
  - path_regex: host_vars/svlazdock1/secrets\.sops\.yml$
    age: >-
      age1svlazdock1...,
      age1admin...

  - path_regex: host_vars/svlazdev1/secrets\.sops\.yml$
    age: >-
      age1svlazdev1...,
      age1admin...

  # Group secrets — encrypted to the GROUP key + admin key
  - path_regex: group_vars/infrastructure_servers/secrets\.sops\.yml$
    age: >-
      age1infra...,
      age1admin...

  - path_regex: group_vars/application_servers/secrets\.sops\.yml$
    age: >-
      age1app...,
      age1admin...

  - path_regex: group_vars/development_servers/secrets\.sops\.yml$
    age: >-
      age1dev...,
      age1admin...

  # Generic secrets (all servers) — encrypted to ALL group keys + admin key
  - path_regex: group_vars/all/secrets\.sops\.yml$
    age: >-
      age1infra...,
      age1app...,
      age1dev...,
      age1admin...

  # Fallback
  - age: age1admin...
```

### Key Distribution (Onboarding)

During server onboarding via `ansible-pull.sh`:

```bash
#!/usr/bin/env bash
# ansible/scripts/ansible-pull.sh  (onboarding excerpt)

# ── Require Age keys ──
if [ -z "$SOPS_AGE_KEY" ]; then
  echo "ERROR: SOPS_AGE_KEY environment variable is required."
  echo "Provide the host key AND the group key (newline-separated)."
  echo ""
  echo "Usage:"
  echo "  export SOPS_AGE_KEY=\$(cat <<EOF"
  echo "AGE-SECRET-KEY-1hostkey..."
  echo "AGE-SECRET-KEY-1groupkey..."
  echo "EOF"
  echo ")"
  echo "  sudo -E bash ansible-pull.sh"
  exit 1
fi

# ── Store keys securely ──
mkdir -p /root/.config/sops/age
echo "$SOPS_AGE_KEY" > /root/.config/sops/age/keys.txt
chmod 600 /root/.config/sops/age/keys.txt
chown root:root /root/.config/sops/age/keys.txt

# ... rest of ansible-pull setup ...
```

### Ensuring Servers Can Decrypt New Secrets

**Scenario**: You push a new secret to Git. Can existing servers decrypt it?

- **Host-specific secret** (`host_vars/<hostname>/secrets.sops.yml`):
  Encrypted to the host's public key → the server already has the matching private key →
  **yes, automatic**.

- **Group secret** (`group_vars/<group>/secrets.sops.yml`):
  Encrypted to the group's public key → all group members already have the group private
  key → **yes, automatic**.

- **Generic secret** (`group_vars/all/secrets.sops.yml`):
  Encrypted to all group public keys → all servers have their group key →
  **yes, automatic**.

- **Adding a NEW server to an existing group**:
  The new server receives the group private key at onboarding → it can immediately
  decrypt all existing group secrets → **no re-encryption needed**.

- **Adding a NEW group**:
  Generate a new group key pair → add the public key to `.sops.yaml` → re-encrypt
  `group_vars/all/secrets.sops.yml` to include the new group key.

> **Key insight**: Because group secrets are encrypted to the **group key** (not individual
> server keys), adding a new server to a group requires no re-encryption. The new server
> simply receives the group's private key.

### Secret Validation (Pre-Flight)

Before deploying any module, a validation task asserts that all `required_secrets` are
present and non-empty:

```yaml
# tasks/validate_secrets.yml
---
- name: "Validate secrets for {{ module_name }}"
  ansible.builtin.assert:
    that:
      - "{{ item }} is defined"
      - "{{ item }} | length > 0"
      - "{{ item }} is not match('ENC\\[AES256_GCM')"
    fail_msg: >-
      Secret '{{ item }}' for module '{{ module_name }}' is missing, empty,
      or still encrypted. Ensure SOPS decryption is working and the secret
      is defined in the appropriate secrets.sops.yml file.
    quiet: true
  loop: "{{ module_config.required_secrets | default([]) }}"

- name: "All secrets validated for {{ module_name }}"
  ansible.builtin.debug:
    msg: "✓ All {{ module_config.required_secrets | default([]) | length }} required secrets present"
```

This runs **before** any containers are started. If a secret is missing or still shows as
SOPS ciphertext (decryption failed), the entire module deployment is aborted.

### AI Agent Compatibility

SOPS files are standard YAML with encrypted values. AI agents can:

1. **Read** the `.sops.yaml` config to determine which keys to encrypt to.
2. **Generate** a cleartext YAML with the desired secrets.
3. **Encrypt** it using `sops --encrypt --in-place` (requires the admin Age private key in
   the agent's environment, or the relevant public keys only for encryption).
4. **Commit** the encrypted file to Git.

Because SOPS encrypts values (not the whole file), the YAML structure remains visible and
diffable:

```yaml
# After encryption — structure visible, values encrypted
traefik_cf_api_token: ENC[AES256_GCM,data:...,iv:...,tag:...,type:str]
db_password: ENC[AES256_GCM,data:...,iv:...,tag:...,type:str]
sops:
  age:
    - recipient: age1admin...
      enc: |
        -----BEGIN AGE ENCRYPTED FILE-----
        ...
```

> **Key point**: SOPS encryption requires only the **public** Age keys. Only decryption
> requires the private key. AI agents can encrypt secrets using public keys without
> ever seeing private keys.

### Ansible Integration

```yaml
# ansible/requirements.yml  (addition)
collections:
  - name: community.sops
    version: ">=1.9.0"
```

The `community.sops.sops_vars` plugin auto-decrypts `*.sops.yml` files when loading
variables. Add to `ansible.cfg`:

```ini
[defaults]
vars_plugins_enabled = host_group_vars,community.sops.sops_vars
```

### Environment Variables → Docker Compose (DD-26)

Secrets stored in SOPS must reach running containers as environment variables. The flow:

```
Git (encrypted)                Ansible (decrypted in memory)           Container runtime
─────────────                  ──────────────────────────────          ─────────────────
secrets.sops.yml  ──decrypt──▶ Ansible vars (e.g. db_password)  ──▶  .env file on disk
                               via community.sops.sops_vars           via template task
                                                                        │
                               docker-compose.yml.j2 ─────────────────▶ env_file: [.env]
                               (references ${DB_PASSWORD})               └─▶ container env
```

**Step 1 — SOPS auto-decryption**: `community.sops.sops_vars` decrypts `*.sops.yml`
files at variable-loading time. Decrypted values exist **only in Ansible's memory** — they
are never written to disk in cleartext except into the `.env` file (step 2).

**Step 2 — Render `.env` file per module**: If a module defines `required_secrets`, a
`.env` file is templated into the module's directory:

```yaml
# tasks/deploy_module.yml  (secrets section)
- name: "Deploy {{ module_name }} .env file"
  ansible.builtin.template:
    src: "env.j2"
    dest: "{{ compose_modules_base_dir }}/{{ module_name }}/.env"
    owner: root
    group: root
    mode: "0600"                  # only root can read
  when: module_config.required_secrets | default([]) | length > 0
  no_log: true                    # prevent secrets appearing in Ansible output
```

The shared `.env` template iterates over the module's `required_secrets`:

```jinja2
# templates/env.j2
# Auto-generated by Ansible — do not edit manually
{% for secret_name in module_config.required_secrets %}
{{ secret_name | upper }}={{ lookup('vars', secret_name) }}
{% endfor %}
{% for extra in module_config.env_extra | default([]) %}
{{ extra.name }}={{ extra.value }}
{% endfor %}
```

**Step 3 — Compose references `.env`**: The module's `docker-compose.yml.j2` uses
variable substitution (not Jinja — Docker Compose's own `${VAR}` syntax):

```yaml
# templates/modules/vaultwarden/docker-compose.yml.j2
services:
  vaultwarden:
    image: {{ vaultwarden_image }}
    env_file:
      - .env                     # Docker Compose reads .env from project dir
    # OR explicit mapping:
    # environment:
    #   - ADMIN_TOKEN=${VAULTWARDEN_ADMIN_TOKEN}
```

**Security measures**:
- `.env` file is `mode: 0600` (root-only read).
- `no_log: true` on the template task prevents Ansible from printing values.
- `.env` files are **never committed to Git** — they exist only on the target host.
- The `.env` approach keeps the Compose template free of Jinja secret references, making
  it statically parseable for validation.

**Module vars addition** — modules can define extra (non-secret) env vars:

```yaml
# vars/modules/vaultwarden.yml
env_extra:
  - name: DOMAIN
    value: "https://vault.{{ domain }}"
  - name: SIGNUPS_ALLOWED
    value: "false"
```

---

## 8. Traefik Integration

### Policy

- **All services with `service_type: web` MUST have `traefik.enabled: true`.**
- An assertion task validates this at deploy time and fails loudly if violated.
- Services of type `internal` or `backend` are exempt.
- **No host ports are exposed** for web services. All HTTP/HTTPS traffic flows through
  Traefik on ports 80/443.
- Exceptions (e.g., DNS port 53) must be explicitly justified in `exposed_ports`.

### Traefik Compose Rendering

```yaml
# templates/modules/traefik/docker-compose.yml.j2
---
services:
  traefik:
    image: {{ traefik_image }}
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - {{ compose_modules_base_dir }}/traefik/config/traefik.yml:/traefik.yml:ro
      - {{ compose_modules_base_dir }}/traefik/config/dynamic:/etc/traefik/dynamic:ro
      - traefik_certs:/letsencrypt
    networks:
{% for mod in effective_modules %}
{%   set mod_config = lookup('vars', mod + '_config', default={}) %}
{%   if mod_config.traefik.enabled | default(false) and mod != 'traefik' %}
      - {{ mod }}-frontend
{%   endif %}
{% endfor %}
    labels:
      - "traefik.enable=true"

networks:
{% for mod in effective_modules %}
{%   set mod_config = lookup('vars', mod + '_config', default={}) %}
{%   if mod_config.traefik.enabled | default(false) and mod != 'traefik' %}
  {{ mod }}-frontend:
    external: true
{%   endif %}
{% endfor %}

volumes:
  traefik_certs:
```

### Standard Traefik Labels (generated per module)

```yaml
labels:
  - "traefik.enable=true"
  - "traefik.docker.network={{ module_name }}-frontend"
  - "traefik.http.routers.{{ module_name }}.rule=Host(`{{ traefik.host }}`)"
  - "traefik.http.routers.{{ module_name }}.entrypoints=websecure"
  - "traefik.http.routers.{{ module_name }}.tls=true"
  - "traefik.http.routers.{{ module_name }}.tls.certresolver=letsencrypt"
  - "traefik.http.services.{{ module_name }}.loadbalancer.server.port={{ traefik.port }}"
{% if 'forward-auth' in traefik.middlewares | default([]) %}
  - "traefik.http.routers.{{ module_name }}.middlewares=forward-auth@docker"
{% endif %}
```

---

## 9. Traefik Forward Auth

### Overview

Before deploying any application modules in production, **Traefik forward auth** must be
in place using `ghcr.io/italypaleale/traefik-forward-auth`.

Forward auth is deployed as its own module (`forward_auth`) and provides a middleware
that other modules reference in their `traefik.middlewares` list.

### Module Structure

```yaml
# vars/modules/forward_auth.yml
---
service_type: internal              # no direct web access needed
forward_auth_image: ghcr.io/italypaleale/traefik-forward-auth:v3.1.0@sha256:...

required_secrets:
  - forward_auth_client_id
  - forward_auth_client_secret
  - forward_auth_secret

networks:
  frontend: true                    # Traefik must reach it

traefik:
  enabled: true                     # registers the middleware via labels
  host: "auth.{{ domain }}"
  port: 4181
  middlewares: []                   # auth itself is not behind auth

healthcheck:
  enabled: true
  name: "Forward Auth"
  group: "Infrastructure"
  url: "https://auth.{{ domain }}"
  interval: 5m
  conditions:
    - "[STATUS] == 200"

dns:
  enabled: true
```

### Middleware Registration

The forward auth container registers itself as a Traefik middleware via Docker labels:

```yaml
labels:
  - "traefik.http.middlewares.forward-auth.forwardauth.address=http://forward-auth:4181"
  - "traefik.http.middlewares.forward-auth.forwardauth.trustForwardHeader=true"
```

Other modules reference it by adding `forward-auth` to their `traefik.middlewares` list.

### Deployment Order

Forward auth is deployed alongside Traefik, before any application module.
The `compose_modules` list ordering ensures Traefik → forward_auth → applications.

---

## 10. Gatus Healthcheck Generation

### How It Works

1. Each module's `healthcheck` block in its vars file defines the check.
2. After deploying a module, Ansible renders a Gatus YAML fragment into
   `/opt/docker-compose/gatus/config/endpoints.d/<module>.yml`.
3. Gatus is configured to load all files from `endpoints.d/`.
4. When a module is removed, its Gatus fragment is deleted and Gatus restarted.

### No Exposed Ports Needed

Healthchecks use the **Traefik-routed URL** (e.g., `https://app.example.com`), not
`localhost:<port>`. This means:
- No ports need to be exposed for healthchecking.
- Checks validate the full routing chain (DNS → Traefik → app).
- Certificate validation is included automatically.

For internal post-deployment validation (not Gatus), use `docker exec` or
`docker inspect` to check container health status without exposing ports.

### Monitoring Services Behind Forward Auth (DD-28)

Services protected by `traefik-forward-auth` will return `401/302` to unauthenticated
requests. When a module defines `healthcheck.path`, a Traefik bypass route is created
that skips the `forward-auth` middleware for that specific path.

**When `healthcheck.path` IS defined** — a bypass route is created:

```yaml
# vars/modules/vaultwarden.yml
healthcheck:
  enabled: true
  name: "Vaultwarden"
  group: "Applications"
  url: "https://vault.{{ domain }}/alive"     # dedicated health endpoint
  path: "/alive"                               # creates unauthenticated bypass route
  interval: 5m
  conditions:
    - "[STATUS] == 200"
```

The Compose template generates an additional Traefik router that skips auth:

```yaml
# Standard Traefik labels (generated per module) — health bypass
{% if healthcheck.path is defined and 'forward-auth' in traefik.middlewares | default([]) %}
  - "traefik.http.routers.{{ module_name }}-health.rule=Host(`{{ traefik.host }}`) && Path(`{{ healthcheck.path }}`)"
  - "traefik.http.routers.{{ module_name }}-health.entrypoints=websecure"
  - "traefik.http.routers.{{ module_name }}-health.tls=true"
  - "traefik.http.routers.{{ module_name }}-health.tls.certresolver=letsencrypt"
  - "traefik.http.routers.{{ module_name }}-health.service={{ module_name }}"
  # No middlewares — intentionally unauthenticated for Gatus
{% endif %}
```

The health endpoint should return minimal information (e.g., `200 OK`) to avoid
leaking data.

**When `healthcheck.path` is NOT defined** — no bypass route is created:

Not every container image ships with a health endpoint. When `healthcheck.path` is
omitted, the Gatus healthcheck URL (`healthcheck.url`) is still monitored, but:

- If the service is behind forward auth, Gatus will see `401/302` responses.
- The Gatus condition should account for this (e.g., `[STATUS] == any(200, 302)`).
- Alternatively, the module can set `healthcheck.enabled: false` and rely solely
  on Docker's built-in `HEALTHCHECK` + post-deployment validation.

`healthcheck.path` is **optional** — not all modules can or need to provide one.

### Gatus Endpoint Template

```yaml
# templates/gatus-endpoint.yml.j2
---
{% set hc = module_config.healthcheck %}
endpoints:
  - name: "{{ hc.name }}"
    group: "{{ hc.group | default('Services') }}"
    url: "{{ hc.url }}"
    interval: {{ hc.interval | default('5m') }}
    conditions:
{% for condition in hc.conditions %}
      - "{{ condition }}"
{% endfor %}
{% if hc.alerts is defined %}
    alerts:
{% for alert in hc.alerts %}
      - type: {{ alert.type }}
{% endfor %}
{% endif %}
```

### Lifecycle

| Event | Gatus action |
|-------|-------------|
| Module deployed | Endpoint YAML written → Gatus reloaded |
| Module removed (cleanup) | Endpoint YAML deleted → Gatus reloaded |
| Module healthcheck disabled | Endpoint YAML deleted → Gatus reloaded |

---

## 11. Image Pinning & Renovate

### Format

All Docker images are pinned by **tag + SHA digest** and must include the **registry
prefix** (no implicit `docker.io`):

```yaml
# In module vars
app_image: "docker.io/library/nginx:1.27.0@sha256:a8b123..."
```

In Compose templates:

```yaml
services:
  app:
    image: "{{ app_image }}"
```

### Renovate Configuration

Renovate already watches this repo (`renovate.json`). It will:

1. Detect image references in `vars/modules/*.yml` files.
2. Open PRs to bump both the tag and digest.
3. PRs are validated by CI before merge.
4. Major/minor database package updates are labelled as **critical** for manual review.

Ensure `renovate.json` includes the custom manager for YAML variable files:

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "customManagers": [
    {
      "customType": "regex",
      "fileMatch": ["ansible/roles/docker_compose_modules/vars/modules/.+\\.yml$"],
      "matchStrings": [
        "\\w+_image:\\s*[\"']?(?<depName>[^:@\"'\\s]+):(?<currentValue>[^@\"'\\s]+)(?:@(?<currentDigest>sha256:[a-f0-9]+))?[\"']?"
      ],
      "datasourceTemplate": "docker"
    }
  ],
  "packageRules": [
    {
      "matchDatasources": ["docker"],
      "matchPackagePatterns": ["postgres", "mysql", "mariadb", "mongo", "redis"],
      "matchUpdateTypes": ["major", "minor"],
      "labels": ["critical", "database"],
      "automerge": false
    }
  ]
}
```

---

## 12. Configuration Layering

### Layer Hierarchy (most specific wins)

```
1. Generic config    templates/modules/<app>/config/generic/       → all servers
2. Group config      group_vars/<server_type>/                     → per server type
3. Host config       templates/modules/<app>/config/specific/<hostname>-*  → per host
```

### Secret Layering (same hierarchy)

```
1. group_vars/all/secrets.sops.yml                   → shared across all servers
2. group_vars/<server_type>/secrets.sops.yml          → per server group (D/T/A/P/DMZ)
3. host_vars/<hostname>/secrets.sops.yml              → per host
```

Ansible's native variable precedence ensures host-specific values override group values
which override `all`.

### Config Deployment Logic

```yaml
# deploy_module.yml (config section)

# 1. Deploy generic configs
- name: "Deploy {{ module_name }} generic configs"
  ansible.builtin.template:
    src: "modules/{{ module_name }}/config/generic/{{ item.src }}"
    dest: "{{ item.dest }}"
    mode: "{{ item.mode | default('0644') }}"
  loop: "{{ module_config.config_files_generic | default([]) }}"

# 2. Discover host-specific configs
- name: "Find host-specific configs for {{ module_name }}"
  ansible.builtin.find:
    paths: "{{ role_path }}/templates/modules/{{ module_name }}/config/specific"
    patterns: "{{ inventory_hostname }}-*"
    file_type: file
  register: specific_configs
  delegate_to: localhost

# 3. Deploy host-specific configs
- name: "Deploy {{ module_name }} host-specific configs"
  ansible.builtin.template:
    src: "{{ item.path }}"
    dest: "{{ compose_modules_base_dir }}/{{ module_name }}/config/{{ item.path | basename | regex_replace('\\.j2$', '') }}"
    mode: "0644"
  loop: "{{ specific_configs.files }}"
```

---

## 13. Docker Compose Validation & Best Practices (DD-29)

### Shift-Left Validation

Compose file validation happens **before deployment** — in CI (GitHub Actions), Bats
tests, and optionally as a pre-commit hook. This catches errors at the earliest possible
point, not on the target server.

```
Developer commit ──▶ CI Pipeline ──▶ Deploy (ansible-pull)
                         │
                    ┌────┴────────────────────┐
                    │ 1. yamllint             │
                    │ 2. ansible-lint         │
                    │ 3. Render templates     │
                    │    (mock variables)     │
                    │ 4. docker compose config│
                    │ 5. Best-practice checks │
                    └─────────────────────────┘
                    All pass ──▶ merge allowed
```

**How templates are validated in CI** (no real secrets or target hosts needed):

1. A Bats test loads each module's `vars/modules/<name>.yml`.
2. It renders the Jinja2 compose template using **mock variables** (a set of dummy values
   that satisfy all `required_secrets` and Ansible variables like `domain`, `compose_modules_base_dir`).
3. The rendered file is validated with `docker compose config --quiet`.
4. The rendered file is parsed for best-practice compliance.

```bash
# tests/bash/compose-validation-test.bats

setup() {
  # Mock variables for Jinja2 rendering
  export MOCK_VARS_FILE="tests/fixtures/mock_module_vars.yml"
}

@test "all compose templates render and pass docker compose config" {
  for module_dir in ansible/roles/docker_compose_modules/templates/modules/*/; do
    module_name=$(basename "$module_dir")
    [ "$module_name" = "_template" ] && continue

    compose_template="$module_dir/docker-compose.yml.j2"
    [ -f "$compose_template" ] || continue

    # Render template with mock variables
    rendered=$(python3 tests/helpers/render_template.py \
      "$compose_template" \
      "$MOCK_VARS_FILE" \
      "$module_name")

    # Write to temp file for docker compose config
    tmpfile=$(mktemp /tmp/compose-XXXXXX.yml)
    echo "$rendered" > "$tmpfile"

    docker compose -f "$tmpfile" config --quiet || \
      fail "Module $module_name compose template fails validation"

    rm -f "$tmpfile"
  done
}
```

A small Python helper renders the Jinja2 template with mock values:

```python
# tests/helpers/render_template.py
"""Render a Jinja2 compose template with mock variables for CI validation."""
import sys
import yaml
from jinja2 import Environment, FileSystemLoader

template_path, mock_vars_path, module_name = sys.argv[1:4]

with open(mock_vars_path) as f:
    mock_vars = yaml.safe_load(f)

mock_vars["module_name"] = module_name
mock_vars.setdefault("compose_modules_base_dir", "/opt/docker-compose")
mock_vars.setdefault("domain", "example.com")
mock_vars.setdefault("inventory_hostname", "testhost")

env = Environment(loader=FileSystemLoader("."))
template = env.get_template(template_path)
print(template.render(**mock_vars))
```

Mock variables fixture:

```yaml
# tests/fixtures/mock_module_vars.yml
---
domain: "example.com"
compose_modules_base_dir: "/opt/docker-compose"
inventory_hostname: "testhost"
# Dummy image values (valid format for best-practice checks)
traefik_image: "docker.io/library/traefik:v3.1.0@sha256:0000000000000000000000000000000000000000000000000000000000000000"
# Add one entry per module image variable as modules are created
```

### Enforced Rules

Every rendered Compose file is validated. The following best
practices are **enforced** (CI fails / deployment fails if violated):

| Rule | Check | Rationale |
|------|-------|-----------|
| Registry prefix | Image name must include registry (e.g., `docker.io/`, `ghcr.io/`) | Explicit source; avoids supply-chain confusion |
| SHA256 digest | Image must include `@sha256:...` | Deterministic; prevents tag mutation attacks |
| `security_opt` | `no-new-privileges:true` must be set on every service | Prevents privilege escalation inside container |
| No `privileged` | `privileged: true` is forbidden unless `allow_privileged: true` in module vars | Minimise blast radius |
| No exposed ports | `ports:` section only allowed if `exposed_ports` is defined in module vars | All traffic through Traefik; explicit exceptions only |
| Read-only root | `read_only: true` recommended (warning if not set, not a failure) | Reduce attack surface |
| Resource limits | Warning if `deploy.resources.limits` not set | Prevent runaway containers |
| Restart policy | `restart: unless-stopped` must be set | Ensure services survive reboots |

### Deploy-Time Validation (Defense in Depth)

In addition to CI validation, the same checks run on the target server before
`docker compose up`. This catches any issues from variable interpolation differences
between mock values (CI) and real values (deploy):

```yaml
# tasks/validate_compose.yml
---
- name: "Validate {{ module_name }} compose file syntax"
  ansible.builtin.command:
    cmd: "docker compose -f docker-compose.yml config --quiet"
    chdir: "{{ compose_modules_base_dir }}/{{ module_name }}"
  changed_when: false

- name: "Read {{ module_name }} compose file for best-practice checks"
  ansible.builtin.slurp:
    src: "{{ compose_modules_base_dir }}/{{ module_name }}/docker-compose.yml"
  register: compose_content

- name: "Parse {{ module_name }} compose file"
  ansible.builtin.set_fact:
    compose_parsed: "{{ compose_content.content | b64decode | from_yaml }}"

- name: "Validate {{ module_name }} best practices"
  ansible.builtin.assert:
    that:
      # All images must include registry prefix
      - >-
        compose_parsed.services | dict2items | map(attribute='value.image') |
        select('match', '^(docker\\.io|ghcr\\.io|quay\\.io|mcr\\.microsoft\\.com|registry\\.)') |
        list | length == compose_parsed.services | length
      # All images must include SHA256 digest
      - >-
        compose_parsed.services | dict2items | map(attribute='value.image') |
        select('search', '@sha256:') |
        list | length == compose_parsed.services | length
      # All services must have security_opt no-new-privileges
      - >-
        compose_parsed.services | dict2items |
        selectattr('value.security_opt', 'defined') |
        list | length == compose_parsed.services | length
    fail_msg: >-
      Compose file for {{ module_name }} fails best-practice validation.
      Check registry prefix, SHA256 digest, and security_opt settings.
```

### Compose Template Best Practices

The `_template/docker-compose.yml.j2` includes all required fields by default:

```yaml
# templates/_template/docker-compose.yml.j2
---
services:
  {{ module_name }}:
    image: "{{ '{{' }} {{ module_name }}_image {{ '}}' }}"
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    # read_only: true               # Enable if application supports it
    networks:
{% if networks.frontend | default(false) %}
      - {{ module_name }}-frontend
{% endif %}
{% if networks.backend | default(false) %}
      - {{ module_name }}-backend
{% endif %}
    labels:
{% if traefik.enabled | default(false) %}
      - "traefik.enable=true"
      - "traefik.docker.network={{ module_name }}-frontend"
      # ... standard Traefik labels
{% endif %}

networks:
{% if networks.frontend | default(false) %}
  {{ module_name }}-frontend:
    external: true
{% endif %}
{% if networks.backend | default(false) %}
  {{ module_name }}-backend:
    external: true
{% endif %}
```

---

## 14. DNS Management (AdGuard + Unbound)

### Architecture (DD-27)

AdGuard Home and Unbound are deployed on **one or more infrastructure server(s)** (e.g.,
`svlazinfra1`), **not** on every Docker host. All other servers and clients point their
DNS resolver to these infrastructure servers.

DNS resolver configuration on clients and Docker hosts is **not managed by Ansible**.
It is typically set by the **DHCP server** on the network (pointing clients to the
infrastructure server's IP). Servers that need a static DNS config can set it manually
or via their OS-level network configuration.

```
                          ┌──────────────────────────────────────┐
                          │  Infrastructure server (svlazinfra1) │
                          │                                      │
Clients / Docker hosts ──▶│  AdGuard Home (DNS filtering + UI)   │
(DNS set by DHCP or       │       │                              │
 manual config)           │       ├── Local zones → Unbound      │
                          │       └── External    → Unbound ──▶ Internet
                          └──────────────────────────────────────┘
```

### Components

| Component | Role | Module | Deployed on |
|-----------|------|--------|-------------|
| **AdGuard Home** | DNS filtering, ad blocking, local DNS UI | `adguard` | Infrastructure server(s) only |
| **Unbound** | Recursive DNS resolver + authoritative for internal zones | `unbound` | Infrastructure server(s) only |

### DNS Record Generation — Static from Inventory (DD-30)

Because DNS runs on the infra server(s) but modules are deployed on **other** servers,
DNS record generation must derive which modules run where. Since **ansible-pull runs
independently per host** with no cross-host fact gathering, the only viable approach is
**static generation from inventory + module vars** (no delegated plays or shared facts).

The infra server's ansible-pull run reads all `vars/modules/*.yml` files, inspects
`target_server_types` / `target_hosts` and the inventory's `compose_modules` lists, and
generates Unbound records accordingly.

```yaml
# tasks/generate_dns.yml (runs on infrastructure server during ansible-pull)
---
- name: Load all module definitions
  ansible.builtin.include_vars:
    file: "{{ item }}"
    name: "{{ item | basename | regex_replace('\\.yml$', '') }}_config"
  loop: "{{ lookup('fileglob', role_path + '/vars/modules/*.yml', wantlist=True) }}"

- name: Build DNS entries from inventory + module vars
  ansible.builtin.set_fact:
    dns_entries: "{{ dns_entries | default([]) + _entries }}"
  vars:
    _mod: "{{ item | basename | regex_replace('\\.yml$', '') }}"
    _cfg: "{{ lookup('vars', _mod + '_config') }}"
    # Determine which hosts deploy this module
    _hosts: >-
      {{ groups['all']
         | select('in',
             (hostvars | dict2items
              | selectattr('value.compose_modules', 'defined')
              | selectattr('value.compose_modules', 'contains', _mod)
              | map(attribute='key') | list)
           ) | list }}
    _entries: >-
      {{ _hosts | map('extract', hostvars)
         | map(attribute='ansible_host')
         | map('community.general.dict_kw', name=_cfg.traefik.host, target_ip=item)
         | list }}
  loop: "{{ lookup('fileglob', role_path + '/vars/modules/*.yml', wantlist=True) }}"
  when:
    - _cfg.dns.enabled | default(false)
    - _cfg.traefik.host is defined
```

> **Why not Option A (delegated facts)?** ansible-pull runs independently per host.
> There is no central orchestrator to collect facts from all hosts and render them on
> the infra server. A static approach from inventory + module vars is deterministic
> and works without cross-host communication.

### Multi-Server Module DNS Records (DD-31)

When a module is deployed on **multiple servers** (e.g., via `target_server_types` matching
several hosts, or multiple hosts listing it in `compose_modules`), a single DNS name
cannot point to all of them. The strategy:

1. **Default**: If a module is deployed on exactly **one** host, the DNS record uses the
   module's `traefik.host` as-is (e.g., `app.example.com → 10.0.0.5`).
2. **Multi-host**: If a module is deployed on **multiple** hosts, generate
   **host-qualified** DNS records: `<app>-<hostname>.<domain>` (e.g.,
   `adguard-svlazinfra1.example.com`, `adguard-svlazinfra2.example.com`).
   The unqualified name (`adguard.example.com`) is **not** created to avoid ambiguity.
3. This is an **exception, not the norm**. Most modules target a single server type /
   host. The naming convention `<app>-<hostname>` is only used when strictly necessary.

```jinja2
# templates/modules/unbound/config/generic/local-zone.conf.j2
# Auto-generated by Ansible — do not edit manually
{% for entry in dns_entries %}
{% if entry.multi_host | default(false) %}
{# Multi-host: qualified name #}
local-zone: "{{ entry.qualified_name }}." static
local-data: "{{ entry.qualified_name }}. IN A {{ entry.target_ip }}"
{% else %}
{# Single-host: standard name #}
local-zone: "{{ entry.name }}." static
local-data: "{{ entry.name }}. IN A {{ entry.target_ip }}"
{% endif %}
{% endfor %}
```

### Client / Server DNS Resolution

DNS resolver settings on Docker hosts and other clients are managed **outside this
repository** — typically via the **DHCP server** on the network, which hands out the
infrastructure server's IP as the DNS resolver. No Ansible task sets
`/etc/resolv.conf` or `systemd-resolved` on non-infra hosts.

### Infrastructure Server DNS (Loop Prevention)

The infrastructure server(s) running AdGuard + Unbound must **not** point their own DNS
resolver at themselves, as this creates a circular dependency during startup (AdGuard
isn't running yet but the OS needs DNS to pull the Git repo).

Solution: An Ansible task in the `docker_compose_modules` role sets the infra server's
system DNS resolver to **Quad9** external upstreams. This runs **before** the
AdGuard/Unbound containers start, ensuring the host always has working DNS.

```yaml
# tasks/configure_infra_dns.yml
---
- name: Configure infrastructure server DNS to external upstream (loop prevention)
  ansible.builtin.template:
    src: modules/unbound/resolved.conf.j2
    dest: /etc/systemd/resolved.conf.d/upstream-dns.conf
    owner: root
    group: root
    mode: "0644"
  when:
    - "'adguard' in effective_modules or 'unbound' in effective_modules"
  notify: restart systemd-resolved
```

```ini
# templates/modules/unbound/resolved.conf.j2
# Managed by Ansible — prevents DNS loop on infrastructure servers
# running AdGuard/Unbound. Host OS resolves via Quad9, not itself.
[Resolve]
DNS=9.9.9.9 149.112.112.112 2620:fe::fe 2620:fe::9
DNSStubListener=no
```

This task is **conditional** — it only applies to hosts that deploy the `adguard` or
`unbound` module. Non-infra hosts are unaffected (their DNS is set by DHCP).

AdGuard/Unbound handle local resolution for all other clients on the network, but the
infra host OS itself does not depend on them.

### Lifecycle

- **Module added** → DNS entry created → Unbound reloaded → AdGuard resolves via Unbound.
- **Module removed** → DNS entry removed → Unbound reloaded → name stops resolving.
- **No manual DNS management required.**

---

## 15. Cleanup & Lifecycle

### Orphan Detection

After all modules are deployed, a cleanup pass detects directories under
`{{ compose_modules_base_dir }}` that are **not** in `effective_modules`:

```yaml
# tasks/cleanup_orphans.yml
---
- name: Find deployed module directories
  ansible.builtin.find:
    paths: "{{ compose_modules_base_dir }}"
    file_type: directory
    recurse: false
  register: deployed_dirs

- name: Identify orphaned modules
  ansible.builtin.set_fact:
    orphaned_modules: >-
      {{ deployed_dirs.files
         | map(attribute='path')
         | map('basename')
         | reject('in', effective_modules)
         | reject('equalto', '_shared')
         | list }}

- name: Remove orphaned modules
  ansible.builtin.include_tasks: remove_module.yml
  loop: "{{ orphaned_modules }}"
  loop_control:
    loop_var: orphan_name
```

### Module Removal Steps

```yaml
# tasks/remove_module.yml
---
- name: "Stop {{ orphan_name }} containers"
  community.docker.docker_compose_v2:
    project_src: "{{ compose_modules_base_dir }}/{{ orphan_name }}"
    state: absent
    remove_orphans: true
    remove_volumes: "{{ cleanup_remove_volumes | default(false) }}"
  ignore_errors: true

- name: "Remove {{ orphan_name }} Gatus healthcheck"
  ansible.builtin.file:
    path: "/opt/docker-compose/gatus/config/endpoints.d/{{ orphan_name }}.yml"
    state: absent
  notify: restart gatus

- name: "Remove {{ orphan_name }} DNS entry"
  ansible.builtin.file:
    path: "{{ compose_modules_base_dir }}/unbound/config/local-zone.d/{{ orphan_name }}.conf"
    state: absent
  notify: restart unbound

- name: "Remove {{ orphan_name }} networks"
  community.docker.docker_network:
    name: "{{ item }}"
    state: absent
    force: true
  loop:
    - "{{ orphan_name }}-frontend"
    - "{{ orphan_name }}-backend"
  ignore_errors: true

- name: "Remove {{ orphan_name }} directory"
  ansible.builtin.file:
    path: "{{ compose_modules_base_dir }}/{{ orphan_name }}"
    state: absent
```

### Volume Cleanup Policy

- **Dev servers** (`cleanup_remove_volumes: true`): Volumes removed on cleanup for a clean
  environment.
- **Production servers** (`cleanup_remove_volumes: false`, default): Volumes preserved to
  prevent accidental data loss.

---

## 16. Validation & Post-Deployment Checks

### Validation Checks Per Module

Since ports are not exposed, validation uses Docker's internal mechanisms and
Traefik-routed URLs:

| Check | When | How |
|-------|------|-----|
| Container running | Always | `docker compose ps` — all services show `running` |
| Container health | Always | `docker inspect` — check `.State.Health.Status` |
| Traefik routing | When `traefik.enabled` | `curl` to `https://<traefik.host>` via internal DNS |
| Network exists | When `networks.frontend` | `docker network inspect <module>-frontend` |
| Log errors | When `validation.check_logs` | `docker logs --tail 20` — scan for ERROR/FATAL |
| DNS resolution | When `dns.enabled` | `dig <traefik.host> @localhost` |

**Note**: No `wait_for` on localhost ports — ports are not exposed. Instead, use
`docker exec` for internal checks or the Traefik URL for end-to-end validation.

### Validation Levels

- `validation.critical: true` — fail the entire playbook run if this module fails validation.
- `validation.critical: false` — log a warning and continue.

### Post-Playbook Validation Report

A summary JSON file is written to `/var/log/ansible/` with:

- Timestamp
- List of deployed modules and their validation status
- List of removed modules
- Any warnings or errors

---

## 17. Dry-Run Support

### Overview

Dry-run mode previews all changes without applying them. This is essential for
understanding what ansible-pull will do before it happens.

### Usage

```bash
# Via Task runner (recommended)
task ansible:check

# Via ansible-pull directly
sudo ansible-pull \
    --url https://github.com/DevSecNinja/docker.git \
    --checkout main \
    --directory /var/lib/ansible/local \
    --inventory ansible/inventory/hosts.yml \
    --extra-vars "target_host=$(hostname)" \
    --check --diff \
    ansible/playbooks/main.yml
```

### What Dry-Run Shows

| Component | Dry-run behaviour |
|-----------|-------------------|
| Config files | Shows diff of template changes |
| Compose files | Shows diff of rendered Compose YAML |
| Docker networks | Reports which networks would be created/removed |
| Secrets | Reports if secrets would be deployed (values masked) |
| Docker Compose | Reports `docker compose config` validation (no start/stop) |
| Cleanup | Reports which orphan modules would be removed |
| DNS records | Shows which Unbound records would change |
| Gatus config | Shows which healthcheck configs would change |

### Implementation

All tasks must be compatible with `--check` mode:

```yaml
# Example: check-mode compatible task
- name: "Deploy {{ module_name }} compose file"
  ansible.builtin.template:
    src: "modules/{{ module_name }}/docker-compose.yml.j2"
    dest: "{{ compose_modules_base_dir }}/{{ module_name }}/docker-compose.yml"
    mode: "0644"
  # Template module natively supports check mode — shows diff without writing

- name: "Validate compose file (even in check mode)"
  ansible.builtin.command:
    cmd: "docker compose -f docker-compose.yml config --quiet"
    chdir: "{{ compose_modules_base_dir }}/{{ module_name }}"
  check_mode: false               # always run, even in check mode
  changed_when: false

- name: "Start {{ module_name }}"
  community.docker.docker_compose_v2:
    project_src: "{{ compose_modules_base_dir }}/{{ module_name }}"
    state: present
  # docker_compose_v2 natively supports check mode — reports what would change
```

---

## 18. Testing Strategy

### Test Categories

| Category | Framework | When | What |
|----------|-----------|------|------|
| Linting | yamllint, ansible-lint | CI + pre-commit | YAML syntax, Ansible best practices |
| Syntax | ansible-playbook --syntax-check | CI | Playbook validity |
| Module schema | Bats | CI | Module vars files have all required fields |
| Compose validation | Bats + docker compose config | CI | Rendered Compose files are valid |
| Compose best practices | Bats | CI | Registry prefix, SHA, security_opt, etc. |
| Secret structure | Bats | CI | SOPS files exist, structure is correct (not decryption) |
| Role tests | Bats | CI | Role tasks, defaults, meta files present |
| Integration | Bats + Docker | CI (with Docker) | Full deploy cycle on test host |
| Dry-run | Bats | CI | `--check` mode produces expected output |

### New Test Files

```
tests/
├── bash/
│   ├── lint-test.bats                 # Existing — yamllint, ansible-lint
│   ├── syntax-test.bats               # Existing — playbook syntax
│   ├── docker-test.bats               # Existing — Docker provisioning
│   ├── ansible-pull-test.bats         # Existing — ansible-pull script
│   ├── github-ssh-keys-test.bats     # Existing — SSH keys role
│   ├── roles-test.bats                # Existing — role structure
│   ├── module-schema-test.bats        # NEW — validate module vars schema
│   ├── compose-validation-test.bats   # NEW — Compose render + best practices (CI)
│   ├── secret-structure-test.bats     # NEW — SOPS file structure
│   ├── network-test.bats              # NEW — network isolation rules
│   └── dry-run-test.bats              # NEW — check mode compatibility
├── fixtures/
│   └── mock_module_vars.yml           # NEW — mock variables for template rendering
└── helpers/
    └── render_template.py             # NEW — Jinja2 → rendered YAML for CI validation
```

### Module Schema Test (Example)

```bash
# tests/bash/module-schema-test.bats

@test "all modules have required fields" {
  for module_file in ansible/roles/docker_compose_modules/vars/modules/*.yml; do
    module_name=$(basename "$module_file" .yml)

    # Must have service_type
    grep -q "service_type:" "$module_file" || \
      fail "Module $module_name missing service_type"

    # Must have image with SHA256
    grep -qE "_image:.*@sha256:" "$module_file" || \
      fail "Module $module_name missing pinned image with SHA256"

    # Must have image with registry prefix
    grep -qE "_image:.*\b(docker\.io|ghcr\.io|quay\.io|mcr\.microsoft\.com)" "$module_file" || \
      fail "Module $module_name missing registry prefix in image"

    # Web services must have traefik.enabled
    if grep -q "service_type: web" "$module_file"; then
      grep -qA5 "traefik:" "$module_file" | grep -q "enabled: true" || \
        fail "Web module $module_name missing traefik.enabled: true"
    fi

    # Must have networks block
    grep -q "networks:" "$module_file" || \
      fail "Module $module_name missing networks block"

    # Must have healthcheck block
    grep -q "healthcheck:" "$module_file" || \
      fail "Module $module_name missing healthcheck block"
  done
}

@test "all modules have a compose template" {
  for module_file in ansible/roles/docker_compose_modules/vars/modules/*.yml; do
    module_name=$(basename "$module_file" .yml)
    template_dir="ansible/roles/docker_compose_modules/templates/modules/$module_name"

    [ -f "$template_dir/docker-compose.yml.j2" ] || \
      fail "Module $module_name missing docker-compose.yml.j2 template"
  done
}
```

### Compose Best Practices Test (Example)

```bash
# tests/bash/compose-validation-test.bats

@test "compose templates enforce security_opt no-new-privileges" {
  for compose_file in ansible/roles/docker_compose_modules/templates/modules/*/docker-compose.yml.j2; do
    module_name=$(basename "$(dirname "$compose_file")")
    [ "$module_name" = "_template" ] && continue

    grep -q "no-new-privileges" "$compose_file" || \
      fail "Module $module_name compose missing security_opt no-new-privileges"
  done
}

@test "compose templates do not expose ports unless allowed" {
  for compose_file in ansible/roles/docker_compose_modules/templates/modules/*/docker-compose.yml.j2; do
    module_name=$(basename "$(dirname "$compose_file")")
    [ "$module_name" = "_template" ] && continue
    [ "$module_name" = "traefik" ] && continue   # Traefik is allowed 80/443

    module_vars="ansible/roles/docker_compose_modules/vars/modules/${module_name}.yml"
    if grep -q "ports:" "$compose_file"; then
      grep -q "exposed_ports:" "$module_vars" || \
        fail "Module $module_name exposes ports without exposed_ports justification"
    fi
  done
}
```

---

## 19. Backup Strategy (Roadmap)

> **Status**: Roadmap — not yet implemented.

### Planned Architecture

| Component | Tool | Destination |
|-----------|------|-------------|
| Docker volumes | `offen/docker-volume-backup` | Azure Blob Storage |
| Database dumps | `tiredofit/docker-db-backup` | Azure Blob Storage |

### Design Sketch

- **Volume backups**: `offen/docker-volume-backup` runs as a sidecar container, mounts
  target volumes, and pushes compressed/encrypted archives to Azure Blob.
- **Database backups**: `tiredofit/docker-db-backup` connects to database containers on
  the backend network and exports dumps to Azure Blob.
- Per-module `backup` block in vars defines what to back up and the schedule.
- Credentials (Azure storage account key) stored in SOPS.
- Restore playbook for disaster recovery.
- Integrated into the `maintenance` role with dedicated timers.

### Module Integration

```yaml
# vars/modules/vaultwarden.yml (future)
backup:
  volumes:
    - vaultwarden_data
  schedule: "0 2 * * *"          # Daily at 2 AM
  retention_days: 30
```

---

## 20. Auto-Generated Service Inventory (Roadmap)

> **Status**: Roadmap — not yet implemented.

### Planned Features

- Post-deployment task collects all deployed modules across all hosts.
- Generates a Markdown or JSON inventory:
  - Service name, URL, server, status, version
  - Network topology diagram (Mermaid)
  - Secret references (obfuscated)
- Output committed to `docs/SERVICE_INVENTORY.md` or served via a dashboard.
- Could integrate with Gatus data for live status.

---

## 21. Auto-Merge & Update Strategy (Roadmap)

> **Status**: Roadmap — not yet implemented.

### Planned Features

- Renovate PRs for non-critical patch updates auto-merge after CI passes.
- Major/minor database packages (postgres, mysql, mariadb, mongo, redis) labelled as
  **critical** and require manual review.
- Post-merge, ansible-pull on dev server picks up changes first.
- Production servers follow after dev validation (manual approval or time delay).
- Consider GitHub Actions workflow that deploys to dev → runs integration tests →
  auto-approves for prod.

---

## 22. AI Authoring & Module Templates

### Module Template

A scaffold template lives at
`ansible/roles/docker_compose_modules/templates/_template/`:

```
_template/
├── README.md                     # Instructions for AI and humans
├── docker-compose.yml.j2         # Compose template with all best practices
├── module.yml.j2                 # Module vars template
└── config/
    └── generic/
        └── .gitkeep
```

#### Template README

```markdown
# How to Create a New Module

1. Copy this `_template/` folder to `templates/modules/<module_name>/`.
2. Create `vars/modules/<module_name>.yml` using the schema documented in
   ARCHITECTURE.md § Module Definition Schema.
3. Edit `docker-compose.yml.j2` with the service definition.
4. Add generic configs under `config/generic/`.
5. Add host-specific configs under `config/specific/<hostname>-<name>.yml.j2`.
6. Add the module name to the relevant host's `compose_modules` list.
7. Run tests: `task test`

## Image Format

Always pin images with registry, version AND SHA digest:
```
app_image: "docker.io/library/nginx:1.27.0@sha256:digest"
```

## Required Fields in Module Vars

- `service_type`: web | internal | backend
- `<name>_image`: pinned image reference with registry + SHA
- `required_secrets`: list of secret variable names (pre-flight validation)
- `traefik` block (if `service_type: web`)
- `healthcheck` block
- `networks` block
- `dns` block

## Compose File Requirements

- `security_opt: [no-new-privileges:true]` on every service
- `restart: unless-stopped`
- No `ports:` unless `exposed_ports` is defined in module vars
- No `privileged: true` unless `allow_privileged: true` in module vars
```

### AI Agent Workflow

AI agents (like Copilot) follow this process to add a new module:

1. **Read** `templates/_template/README.md` for the schema.
2. **Copy** template to `templates/modules/<name>/`.
3. **Create** `vars/modules/<name>.yml` with all required fields.
4. **Generate** secrets in `group_vars/` or `host_vars/` using `sops --encrypt`.
5. **Add** module to relevant `compose_modules` lists.
6. **Run** `task test` to validate.
7. **Commit** all files.

Because the module schema is rigid and self-documenting, AI agents can reliably generate
complete modules without human intervention.

---

## 23. Implementation Order

### Phase 1 — Foundation

| Task | Description |
|------|-------------|
| 1.1 | Restructure inventory with server groups and environments |
| 1.2 | Implement SOPS + Age integration (ansible.cfg, requirements, .sops.yaml) |
| 1.3 | Implement shared group keys for SOPS |
| 1.4 | Update `ansible-pull.sh` for Age key injection (host key + group key) |
| 1.5 | Create module template scaffold (`_template/`) with all best practices |
| 1.6 | Implement module resolution logic (`resolve_modules.yml`) |
| 1.7 | Update `deploy_module.yml` with targeting + config layering |
| 1.8 | Implement `.env` file templating for secrets → containers |
| 1.9 | Add image pinning convention + Renovate custom manager with critical DB labels |
| 1.10 | Implement secret validation pre-flight (`validate_secrets.yml`) |
| 1.11 | Implement Docker Compose validation task (`validate_compose.yml`) |
| 1.12 | Create CI compose validation tooling (mock vars, render helper, Bats test) |
| 1.13 | Write Bats tests: module-schema-test, compose-validation-test, secret-structure-test |

### Phase 2 — Network, Traefik & First Module

| Task | Description |
|------|-------------|
| 2.1 | Implement per-module network creation tasks (frontend + backend isolation) |
| 2.2 | Render Traefik Compose dynamically to join all frontend networks |
| 2.3 | Add Traefik enforcement assertion for `service_type: web` |
| 2.4 | Migrate existing Traefik module to new structure |
| 2.5 | Deploy `traefik-forward-auth` module |
| 2.6 | Deploy `mendhak/http-https-echo` as validation/test module behind Traefik |
| 2.7 | Verify end-to-end: Traefik → forward-auth → echo container |
| 2.8 | Implement dry-run support (`--check --diff` compatibility on all tasks) |
| 2.9 | Write Bats tests: network-test, dry-run-test |

### Phase 3 — Gatus & Lifecycle

| Task | Description |
|------|-------------|
| 3.1 | Implement orphan detection and cleanup (`cleanup_orphans.yml`) |
| 3.2 | Implement module removal with network/volume cleanup |
| 3.3 | Deploy Gatus module |
| 3.4 | Implement Gatus healthcheck generation + cleanup |
| 3.5 | Implement Gatus health bypass routes for modules with `healthcheck.path` |
| 3.6 | Add post-deployment validation tasks (container health, Traefik routing) |
| 3.7 | Write additional Bats tests for Gatus and cleanup |

### Phase 3b — DNS

| Task | Description |
|------|-------------|
| 3b.1 | Deploy AdGuard + Unbound module on infrastructure server(s) |
| 3b.2 | Configure infra server DNS to use external upstream (loop prevention) |
| 3b.3 | Verify DHCP hands out infra server IP as DNS resolver to clients |
| 3b.4 | Implement static DNS record generation from inventory + module vars |
| 3b.5 | Handle multi-host module DNS naming (`<app>-<hostname>` when needed) |
| 3b.6 | Add DNS cleanup to module removal tasks |
| 3b.7 | Write Bats tests for DNS record generation |

### Phase 4 — Dev Server & Full Lifecycle

| Task | Description |
|------|-------------|
| 4.1 | Configure dev server with `deploy_all_modules: true` |
| 4.2 | Set up group-level and host-level SOPS secret files |
| 4.3 | Test full lifecycle: deploy, update, remove, dry-run on dev server |
| 4.4 | Validate cleanup removes everything (volumes on dev) |
| 4.5 | Run full Bats test suite, fix any issues |

### Phase 5 — Migration & Modules

| Task | Description |
|------|-------------|
| 5.1 | Migrate existing Compose stacks from old repo into module format |
| 5.2 | Create modules one by one, validating each (secrets, Compose, healthcheck, DNS) |
| 5.3 | Cut over production servers |

### Phase 6 — Observability & Robustness (Roadmap)

| Task | Description |
|------|-------------|
| 6.1 | Implement backup module (`offen/docker-volume-backup` + `tiredofit/docker-db-backup`) |
| 6.2 | Implement auto-generated service inventory |
| 6.3 | Implement auto-merge / update strategy for Renovate |
| 6.4 | Add monitoring stack module (Prometheus/Grafana) |
| 6.5 | Add centralized logging module (Loki) |
| 6.6 | Configuration drift detection |

---

## 24. Resolved Decisions

Decisions made during the design phase that are no longer open:

| # | Original Question | Decision |
|---|-------------------|----------|
| 1 | Separate DNS zone for dev? | **Yes** — dev server uses `*.dev.example.com` |
| 2 | Database migration handling? | **Roadmap** — label major/minor DB packages as critical in Renovate; manual review for now |
| 3 | Enforce resource limits? | **Optional** — recommended but not mandatory per module |
| 4 | Alerting channels for Gatus? | **Open** — to be decided per environment |
| 5 | `cleanup_remove_volumes` defaults? | **Yes** — `true` on dev, `false` on prod |
| 6 | Multi-server services? | **Out of scope** |
| 7 | Separate develop branch? | **No** — single `main` branch; auto-merge strategy on roadmap |
| 8 | Private Docker registry? | **Not needed** — public registries sufficient |
| 9 | DNS record generation approach? | **Option B (static)** — ansible-pull has no cross-host facts; static from inventory + module vars |
| 10 | Standardise health endpoint paths? | **No** — `healthcheck.path` is optional per module; not every image has a health endpoint |
| 11 | DNS resolver config on Docker hosts? | **Via DHCP** — not managed by Ansible; infra servers get Quad9 upstream via Ansible task (loop prevention) |

---

## 25. Open Questions

| # | Question | Context |
|---|----------|---------|
| 1 | What alerting channels for Gatus? Discord, email, PagerDuty? | Needs to be decided per environment |
| 2 | Which services should be exempt from forward auth? | Public-facing services (e.g., Gatus dashboard?) |
| 3 | Should the echo test container remain deployed in production? | Useful for debugging vs. minimal surface |
| 4 | What Azure Blob retention policy for backups? | Cost vs. recovery window trade-off |
| 5 | Should ansible-pull timer frequency differ between dev and prod? | More frequent on dev for faster iteration |
