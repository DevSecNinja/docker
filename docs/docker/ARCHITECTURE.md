# Architecture: Docker Compose Module System

**Status**: Draft — February 14, 2026

**Author**: Jean-Paul van Ravensberg (DevSecNinja) with AI assistance

**Repository**: <https://github.com/DevSecNinja/docker> (public)

---

## Table of Contents

- [1. Overview](#1-overview)
- [2. Goals & Requirements](#2-goals--requirements)
  - [Security Trust Model & Threat Landscape](#security-trust-model--threat-landscape)
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
- [19. Concurrency & Locking](#19-concurrency--locking)
- [20. Rollback Strategy](#20-rollback-strategy)
- [21. Traefik Middleware Chains](#21-traefik-middleware-chains)
- [22. Container Logging](#22-container-logging)
- [23. Docker Network Address Pools](#23-docker-network-address-pools)
- [24. Disk Space Management](#24-disk-space-management)
- [25. TLS Certificate Strategy](#25-tls-certificate-strategy)
- [26. Backup Strategy (Roadmap)](#26-backup-strategy-roadmap)
- [27. Auto-Generated Service Inventory (Roadmap)](#27-auto-generated-service-inventory-roadmap)
- [28. Auto-Merge & Update Strategy (Roadmap)](#28-auto-merge--update-strategy-roadmap)
- [29. AI Authoring & Module Templates](#29-ai-authoring--module-templates)
- [30. Implementation Order](#30-implementation-order)
- [31. Resolved Decisions](#31-resolved-decisions)
- [32. Open Questions](#32-open-questions)
- [33. Roadmap Items](#33-roadmap-items)

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
Git push → ansible-pull detects change (with flock — single instance only)
  → plays main.yml
  → server_features gates which roles run
  → pre-load ALL module vars into scope
  → resolve effective module list (with targeting filter)
  → sort modules by deploy_priority (infra first, apps last)
  → validate secrets (pre-flight — abort if missing)
  → validate Compose files (lint + best-practice checks)
  → each module (in priority order):
      1. create networks
      2. decrypt secrets (SOPS)
      3. deploy generic + host-specific configs
      4. back up existing docker-compose.yml → .bak
      5. render & validate new docker-compose.yml
      6. docker compose up
      7. run post-deploy validation
         → on critical failure: rollback to .bak
      8. clean up .bak on success
      9. generate Gatus healthcheck
      10. generate DNS records for Unbound
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

### Security Trust Model & Threat Landscape

This repository is **public**. Every committed byte is visible to adversaries. The
security architecture must assume an attacker has full read access to all non-encrypted
content, including playbooks, templates, Compose files, and role logic.

#### Trust Chain

```
Git push to main → ansible-pull on each server (as root via become)
  → executes all playbooks/roles from main
  → deploys containers, writes configs, manages secrets
```

**Pushing code to `main` is equivalent to having root access on every server.** This is
the foundational trust relationship of ansible-pull. All contributor vetting, branch
protection, and CI checks exist to protect this boundary.

#### Assets Under Protection

| Asset | Location | Protection |
|-------|----------|------------|
| Server root access | All hosts | Branch protection on `main`; CODEOWNERS |
| Secrets (API keys, passwords) | SOPS-encrypted in Git | Age encryption; key distribution; `.env` mode `0600` |
| Container workloads | Docker on each host | Image pinning; network isolation; `no-new-privileges` |
| DNS resolution | Infrastructure server(s) | AdGuard + Unbound; Traefik routing |
| TLS certificates | Traefik cert volume | Let's Encrypt; Cloudflare API token in SOPS |
| Application data | Docker volumes | Backup strategy (roadmap); volume cleanup policy |

#### Adversary Model

| Adversary | Capability | Primary Defense |
|-----------|------------|------------------|
| External attacker (internet) | Port scanning, exploit public services | UFW deny-by-default; Traefik as single ingress; forward auth |
| Compromised LAN device | Access internal network; probe services | Per-app network isolation; IP-restricted health bypass; forward auth |
| Compromised dependency (supply chain) | Malicious image tag/digest | SHA digest pinning; Renovate PRs validated by CI; dev-first staging |
| Compromised contributor | Push malicious code to `main` | Branch protection; required reviews; CODEOWNERS; signed commits (DD-45) |
| Compromised server | Access local keys, Docker socket, network | Group key blast radius containment; per-host key scoping; socket proxy (DD-46) |

#### Trust Boundaries

```
┌─────────────────────────────────────────────────────────────────┐
│ TRUST BOUNDARY 1: Git repository (main branch)                 │
│   Who/what crosses it: contributors, CI, Renovate              │
│   Controls: branch protection, required reviews, CODEOWNERS,   │
│             CI checks, signed commits                          │
└───────────────────────────┬─────────────────────────────────────┘
                            │ ansible-pull (as root)
┌───────────────────────────▼─────────────────────────────────────┐
│ TRUST BOUNDARY 2: Server OS (Ansible execution)                │
│   Who/what crosses it: Ansible tasks, SOPS decryption          │
│   Controls: flock concurrency, secret validation, Age keys     │
└───────────────────────────┬─────────────────────────────────────┘
                            │ docker compose up
┌───────────────────────────▼─────────────────────────────────────┐
│ TRUST BOUNDARY 3: Container runtime                            │
│   Who/what crosses it: container images, .env files, volumes   │
│   Controls: no-new-privileges, cap_drop ALL, read-only rootfs, │
│             network isolation, socket proxy, image pinning      │
└───────────────────────────┬─────────────────────────────────────┘
                            │ Traefik reverse proxy
┌───────────────────────────▼─────────────────────────────────────┐
│ TRUST BOUNDARY 4: Network ingress                              │
│   Who/what crosses it: HTTP/HTTPS clients                      │
│   Controls: TLS termination, forward auth, rate limiting,      │
│             secure headers, IP allowlists                       │
└─────────────────────────────────────────────────────────────────┘
```

#### Accepted Risks

| Risk | Severity | Rationale |
|------|----------|------------|
| Group key compromise exposes all group secrets | Medium | Trade-off for operational simplicity; mitigated by minimizing group-level secrets and preferring host-level secrets |
| Admin Age key can decrypt all SOPS files | Medium | Required for AI agent encryption workflow; private key held offline by repository owner only |
| Docker socket access by Traefik (via proxy) | Low | Mitigated by socket proxy (DD-46) restricting API surface to read-only container/network endpoints |
| Frontend networks allow outbound internet | Low | Required for containers making external API calls; backend networks are `internal: true` for databases |
| First deployment has no rollback target | Low | Inherent limitation; manual intervention required; subsequent deploys have `.bak` protection |

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
| DD-32 | Deploy ordering | Explicit `deploy_priority` integer per module; sorted ascending before deploy loop | Ensures Traefik + forward_auth deploy before apps; deterministic on dev (glob order is random); see §5 |
| DD-33 | Module vars pre-loading | All `vars/modules/*.yml` loaded into scope **before** any module deploys | Traefik Compose rendering requires knowledge of all modules' network/Traefik config; see §5 |
| DD-34 | Module targeting precedence | `target_server_types`/`target_hosts` filter applied after module discovery; mismatch with `compose_modules` list is a fatal error | Prevents silent deployment to wrong server; explicit over implicit; see §5 |
| DD-35 | Concurrency locking | `flock --nonblock` on ansible-pull systemd unit | Prevents overlapping runs causing race conditions; non-blocking so stale locks are never an issue; see §19 |
| DD-36 | Rollback on failure | Back up `docker-compose.yml` → `.bak` before deploy; restore on critical validation failure; `.bak` cleaned up after success | Prevents broken state persisting; no automatic data restore; see §20 |
| DD-37 | Server type source | `server_type` derived from group membership (`group_names`), **not** from host_vars | Single source of truth; prevents group/host_vars divergence; see §4 |
| DD-38 | Docker network address pools | `geerlingguy.docker` configured with single `172.17.0.0/12` pool using /20 subnets | Avoids 192.168.x.x LAN conflict; ~256 networks per host; see §23 |
| DD-39 | Middleware chains | Traefik file-based middleware definitions (rate-limit, secure-headers, IP allowlists); modules reference chains, not individual middlewares | Composable; health bypass uses rate-limit + IP-restrict; see §21 |
| DD-40 | Container logging | `json-file` log driver with `max-size` and `max-file` enforced in Compose template | Prevents disk exhaustion from unrotated container logs; see §22 |
| DD-41 | Gatus reload | Gatus watches config directory via built-in file watcher — no container restart needed | Zero-downtime config updates; avoids monitoring gaps during reload; see §10 |
| DD-42 | `.env` naming | Secrets uppercased in `.env` (`secret_name` → `SECRET_NAME`); Compose uses `${SECRET_NAME}` syntax | Documented convention; CI test validates Compose `${VAR}` refs match module secrets; see §7 |
| DD-43 | Secret scope | Group-specific + host-specific secrets only; no `group_vars/all/secrets.sops.yml` | Avoids N-key encryption problem when adding groups; secrets belong to their scope; see §7 |
| DD-44 | TLS certificates | Let's Encrypt with DNS-01 challenge via Cloudflare API | Supports wildcard certs; no inbound port 80 dependency for validation; see §25 |
| DD-45 | Branch protection & supply chain | `main` branch requires: ≥1 review, passing CI, no force-push, no deletion; `CODEOWNERS` for `ansible/` and `.github/` | Push to `main` = root on all servers; this is the single most critical security control; see §2 Trust Model |
| DD-46 | Docker socket proxy | Traefik accesses Docker API via `tecnativa/docker-socket-proxy` — not the raw socket | Limits Traefik's Docker API access to read-only container/network endpoints; blocks exec, create, and other dangerous operations; see §8 |
| DD-47 | Container capabilities | `cap_drop: [ALL]` enforced on every service; `cap_add` for specific capabilities with justification | Least privilege; default Linux capabilities are excessive for most containers; see §13 |
| DD-48 | Read-only rootfs | `read_only: true` is the default; modules opt out with `allow_writable_rootfs: true` and a documented reason | Reduces attack surface; prevents in-container persistence; see §13 |
| DD-49 | Forward auth default | Forward auth (`forward-auth` middleware) is applied to **all** `service_type: web` modules by default; modules opt out with `forward_auth: false` and justification | Default-deny authentication; public services are the exception, not the rule; see §9 |
| DD-50 | SOPS environment pre-flight | Early playbook task validates Age key file exists, is `mode 0600`, and a canary secret decrypts successfully — before any module processing | Fail-fast on broken SOPS setup; prevents cascading failures across all modules; see §7 |
| DD-51 | Ansible collection pinning | External Ansible collections pinned to exact versions in `requirements.yml` | Same supply-chain rigor as Docker images; prevents silent breaking changes or compromised collection versions |
| DD-52 | Rollback includes secrets | `.env` files are backed up alongside `docker-compose.yml` during rollback; restored atomically | Prevents Compose/secret version mismatch after rollback; see §20 |

---

## 4. Server Classification & Environments

### Inventory Structure

```yaml
# ansible/inventory/hosts.yml
---
all:
  children:
    # ── Role-based groups (servers can appear in multiple) ──
    # server_type is derived from group membership via group_names (DD-37).
    # Do NOT set server_type in host_vars — it is implicit from the group.
    infrastructure_servers:
      hosts:
        svlazinfra1:
          ansible_host: 10.0.1.10     # mandatory — used for DNS, IP allowlists

    application_servers:
      hosts:
        svlazdock1:
          ansible_host: 10.0.1.20     # mandatory

    development_servers:
      hosts:
        svlazdev1:
          ansible_host: 10.0.1.30     # mandatory

    dmz_servers:
      # Reserved for future use — hosts added here when DMZ segment is created
      hosts: {}
```

> **`ansible_host` is mandatory** for every host in the inventory. It is used by:
> - Traefik dynamic config to resolve backend IPs
> - UFW firewall rules
> - Middleware IP allowlists (`whitelist-infra` in §21)
> - DNS record generation (Phase 3b)
```

### Environment Behaviour

All servers track the `main` branch. The dev server simply deploys every available module.
An auto-merge / update strategy for Renovate PRs is on the roadmap (see §28).

| Environment | Branch | Module selection | Secrets |
|-------------|--------|------------------|---------|
| Production  | `main` | Explicit per-host `compose_modules` list | Production secrets (group + host) |
| Dev / Test  | `main` | All modules (`deploy_all_modules: true`) | Dev/test secrets (group + host) |

### Host Variables Example

```yaml
# ansible/inventory/host_vars/svlazdock1.yml
---
# server_type is NOT set here — derived from group membership (DD-37).
# svlazdock1 is in the application_servers group.
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
# server_type is NOT set here — derived from group membership (DD-37).
# svlazdev1 is in the development_servers group.
environment: development
deploy_all_modules: true       # deploys every module found in vars/modules/

compose_modules: []            # ignored when deploy_all_modules is true
```

### Server Type Resolution

Instead of explicit `server_type` variables, use Ansible's `group_names` fact:

```yaml
# Example: check server type in a task
- name: "Check if this is an infrastructure server"
  ansible.builtin.debug:
    msg: "This is an infrastructure server"
  when: "'infrastructure_servers' in group_names"
```

For module targeting, the resolve logic maps group names to server types:

```yaml
# In resolve_modules.yml — derive server_type from group membership
- name: Determine server type from group membership
  ansible.builtin.set_fact:
    _server_type: >-
      {{ 'infrastructure' if 'infrastructure_servers' in group_names
         else 'application' if 'application_servers' in group_names
         else 'development' if 'development_servers' in group_names
         else 'dmz' if 'dmz_servers' in group_names
         else 'unknown' }}
```

### Multi-Group Membership Validation

A host must belong to **exactly one** server type group. The `if/elif` chain above
silently resolves ambiguity by taking the first match, which can lead to wrong modules
deployed on a server with security implications. An assertion task prevents this:

```yaml
# In resolve_modules.yml — validate single group membership
- name: Assert host belongs to exactly one server type group
  ansible.builtin.assert:
    that:
      - >-
        (['infrastructure_servers', 'application_servers',
          'development_servers', 'dmz_servers']
         | select('in', group_names) | list | length) == 1
    fail_msg: >-
      Host {{ inventory_hostname }} belongs to multiple (or zero) server type
      groups: {{ ['infrastructure_servers', 'application_servers',
      'development_servers', 'dmz_servers']
      | select('in', group_names) | list }}.
      Each host must belong to exactly one server type group.
```

This assertion runs **before** module resolution and fails the playbook immediately
if the inventory is misconfigured.

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
# ── Deploy priority (DD-32) ──
# Lower numbers deploy first. Infrastructure modules (traefik, forward_auth,
# gatus, adguard, unbound) use 10-30. Application modules default to 100.
deploy_priority: 20                 # deploy early — infrastructure service

# ── Targeting ──
target_server_types:                # deploy only on these server types
  - infrastructure
# target_hosts:                     # OR pin to specific hosts
#   - svlazinfra1

# ── Service type (enforces Traefik policy) ──
service_type: web                   # web | internal | backend

# ── Forward auth (DD-49 — default-on for web services) ──
# Omit or set to true for default behaviour. Set to false + provide reason to opt out.
# forward_auth: false
# forward_auth_exempt_reason: "Public API; app handles its own authentication"

# ── Rootfs writability (DD-48 — read-only by default) ──
# Omit for default read-only rootfs. Set to true + provide reason to opt out.
# allow_writable_rootfs: true
# writable_rootfs_reason: "Application writes to /app/data at runtime"

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
    - forward-auth                  # require auth (applied by default for web services; see DD-49)
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

### Deploy Priority Convention

| Priority | Category | Examples |
|----------|----------|----------|
| 10 | Core infrastructure | `traefik` |
| 15 | Auth infrastructure | `forward_auth` |
| 20 | Infrastructure services | `adguard`, `unbound` |
| 30 | Monitoring | `gatus`, `prometheus`, `grafana` |
| 100 | Applications (default) | `vaultwarden`, `portainer`, `homepage` |

Modules that omit `deploy_priority` default to **100**. The deploy loop iterates in
ascending priority order, ensuring infrastructure is always ready before applications
that depend on it.

### Module Variable Pre-Loading (DD-33)

**All module variable files are loaded into scope before any module deploys.** This is
a hard prerequisite — Traefik's Compose template (and other cross-module references)
requires knowledge of all modules' network and Traefik configuration at render time.

```yaml
# tasks/main.yml (pre-load step — runs before the deploy loop)
---
- name: Pre-load all module variable files
  ansible.builtin.include_vars:
    file: "{{ item }}"
    name: "{{ item | basename | regex_replace('\\.yml$', '') }}_config"
  loop: "{{ lookup('fileglob', role_path + '/vars/modules/*.yml', wantlist=True) }}"

# Variable naming convention: <module_name>_config
# e.g., vars/modules/traefik.yml → traefik_config
# e.g., vars/modules/adguard.yml → adguard_config
# Access via: lookup('vars', module_name + '_config')
```

### Module Resolution Logic

```yaml
# tasks/resolve_modules.yml
---
# ── Step 1: Determine server type from group membership (DD-37) ──
- name: Determine server type from group membership
  ansible.builtin.set_fact:
    _server_type: >-
      {{ 'infrastructure' if 'infrastructure_servers' in group_names
         else 'application' if 'application_servers' in group_names
         else 'development' if 'development_servers' in group_names
         else 'dmz' if 'dmz_servers' in group_names
         else 'unknown' }}

# ── Step 2: Build candidate module list ──
# If deploy_all_modules is true (dev server), discover every module definition
- name: Discover all available modules
  ansible.builtin.find:
    paths: "{{ role_path }}/vars/modules"
    patterns: "*.yml"
    file_type: file
  register: all_module_files
  delegate_to: localhost
  when: deploy_all_modules | default(false)

- name: Build candidate module list (dev — all modules)
  ansible.builtin.set_fact:
    _candidate_modules: >-
      {{ all_module_files.files | map(attribute='path') | map('basename') |
         map('regex_replace', '\.yml$', '') | list }}
  when: deploy_all_modules | default(false)

- name: Build candidate module list (normal — from compose_modules)
  ansible.builtin.set_fact:
    _candidate_modules: "{{ compose_modules | default([]) }}"
  when: not (deploy_all_modules | default(false))

# ── Step 3: Apply targeting filter (DD-34) ──
# Filter out modules whose target_server_types / target_hosts exclude this host.
- name: Filter modules by targeting rules
  ansible.builtin.set_fact:
    _filtered_modules: >-
      {{ _candidate_modules | select('in',
           _candidate_modules | map('regex_replace', '^(.*)$', '\\1_config')
           | map('extract', vars)
           | zip(_candidate_modules)
           | selectattr('0.target_server_types', 'defined')
           | selectattr('0.target_server_types', 'contains', _server_type)
           | map(attribute='1')
           | list
         ) | list }}

# For modules from compose_modules that fail targeting, fail loudly:
- name: Validate compose_modules entries match targeting
  ansible.builtin.assert:
    that:
      - >-
        (lookup('vars', item + '_config').target_server_types is not defined)
        or (_server_type in lookup('vars', item + '_config').target_server_types)
      - >-
        (lookup('vars', item + '_config').target_hosts is not defined)
        or (inventory_hostname in lookup('vars', item + '_config').target_hosts)
    fail_msg: >-
      Module '{{ item }}' is in compose_modules but this host
      ({{ inventory_hostname }}, type={{ _server_type }}) does not match
      the module's targeting rules. Remove it from compose_modules or
      update the module's target_server_types / target_hosts.
  loop: "{{ compose_modules | default([]) }}"
  when: not (deploy_all_modules | default(false))

# ── Step 4: Sort by deploy_priority (DD-32) ──
- name: Sort effective modules by deploy_priority
  ansible.builtin.set_fact:
    effective_modules: >-
      {{ _filtered_modules
         | sort(attribute='none',
                key=lookup('vars', item + '_config', default={}).deploy_priority | default(100))
         | list }}
  # Note: actual Jinja2 sort uses a custom approach since Ansible's sort
  # doesn't support key= directly. Implementation will use a registered
  # variable with a Python-style sorted() via a small filter plugin or
  # a set_fact loop that builds a priority-keyed list.
```

> **Implementation note**: Ansible's Jinja2 `sort` filter does not natively support
> `key=` for dict lookups. The actual implementation should build a list of
> `[priority, module_name]` tuples, sort that list, and extract the module names.
> Example approach:
>
> ```yaml
> - name: Build priority list
>   ansible.builtin.set_fact:
>     _priority_list: >-
>       {{ _filtered_modules | map('regex_replace', '^(.*)$',
>            '{"name": "\\1", "priority": ' +
>            (lookup('vars', '\\1_config', default={}).deploy_priority | default(100) | string) +
>            '}') | map('from_json') | sort(attribute='priority') | list }}
>
> - name: Set effective modules (sorted)
>   ansible.builtin.set_fact:
>     effective_modules: "{{ _priority_list | map(attribute='name') | list }}"
> ```

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

### Egress Policy

Frontend networks are **not** `internal: true` — containers on them can make outbound
internet connections. This is intentional: some web services need to call external APIs,
fetch updates, or validate licenses.

Backend networks (`internal: true`) provide the critical isolation for databases, caches,
and workers that have no legitimate need for internet access.

> **Accepted risk**: A compromised container on a frontend network can exfiltrate data
> outbound. The defense-in-depth layers (image pinning, `no-new-privileges`, `cap_drop`,
> read-only rootfs, network segmentation from other apps) limit the attacker's capability
> even if egress is available. Outbound filtering via a forward proxy is deferred as a
> future hardening consideration.

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
├── Encrypted files live in Git (DD-43 — no group_vars/all secrets):
│   ansible/
│   ├── inventory/
│   │   ├── group_vars/
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

> **Design decision (DD-43)**: There is no `group_vars/all/secrets.sops.yml`. Secrets
> belong to their group or host scope. A "shared across all servers" secret file would
> require encryption to **all** group keys, creating an N-key maintenance burden when
> adding new groups. If a secret is truly needed everywhere, place it in each group's
> `secrets.sops.yml` — the duplication is minimal and the encryption scope stays clean.

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

- **Adding a NEW server to an existing group**:
  The new server receives the group private key at onboarding → it can immediately
  decrypt all existing group secrets → **no re-encryption needed**.

- **Adding a NEW group**:
  Generate a new group key pair → add the public key to `.sops.yaml` →
  create the group's `secrets.sops.yml`. No re-encryption of other files needed (DD-43).

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
      - "lookup('vars', item) is defined"
      - "lookup('vars', item) | string | length > 0"
      - "lookup('vars', item) | string is not search('ENC\\[AES256_GCM')"
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

### SOPS Environment Pre-Flight Check (DD-50)

Before the module deploy loop begins, an early pre-flight task validates that the
SOPS/Age decryption environment is functional. This catches systemic issues (missing
key file, wrong permissions, corrupted keys) before they cascade across every module's
secret validation.

```yaml
# tasks/main.yml (runs before module resolution)
---
- name: Verify Age key file exists and has correct permissions
  ansible.builtin.stat:
    path: /root/.config/sops/age/keys.txt
  register: _age_keyfile

- name: Assert Age key file is present and secure
  ansible.builtin.assert:
    that:
      - _age_keyfile.stat.exists
      - _age_keyfile.stat.mode == '0600'
      - _age_keyfile.stat.pw_name == 'root'
      - _age_keyfile.stat.size > 0
    fail_msg: >-
      SOPS Age key file is missing, has wrong permissions, or is empty.
      Expected: /root/.config/sops/age/keys.txt, mode 0600, owned by root.
      Run the onboarding script (ansible-pull.sh) to inject keys.

- name: Validate SOPS decryption with canary secret
  ansible.builtin.assert:
    that:
      - sops_canary is defined
      - sops_canary | string | length > 0
      - sops_canary | string is not search('ENC\\[AES256_GCM')
    fail_msg: >-
      SOPS canary secret failed to decrypt. The Age key file may contain
      the wrong keys or the community.sops.sops_vars plugin is not working.
      Verify the key file at /root/.config/sops/age/keys.txt contains
      both the host key and the group key.
```

Each group's `secrets.sops.yml` must include a `sops_canary` variable — a non-sensitive
test value (e.g., `sops_canary: "decryption-ok"`) that proves the decryption pipeline
works. The canary is checked before any module processing begins.

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
    version: "1.9.1"              # pinned — same supply-chain rigor as Docker images (DD-51)
```

> **Version pinning (DD-51)**: External Ansible collections are pinned to exact versions,
> not ranges like `>=1.9.0`. A compromised or breaking collection update could affect
> every server on the next ansible-pull run. Update deliberately via PR with CI validation.

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

> **Naming convention (DD-42)**: Secret variable names are **uppercased** in the `.env` file.
> A secret named `adguard_admin_password` in Ansible becomes `ADGUARD_ADMIN_PASSWORD` in
> the `.env` file. Compose templates must use `${ADGUARD_ADMIN_PASSWORD}` (uppercase) to
> reference it. A CI test validates that all `${VAR}` references in Compose templates
> have a matching entry in the module's `required_secrets` or `env_extra` (uppercased).
> Non-secret env vars from `env_extra` are written as-is (the `name` field controls the
> exact casing).

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
- **Port 80** is exposed alongside port 443 solely for the HTTP→HTTPS redirect
  middleware (`redirect-to-https`). No plaintext HTTP traffic reaches application
  containers — all requests are redirected to HTTPS before routing.
- Exceptions (e.g., DNS port 53) must be explicitly justified in `exposed_ports`.

### Docker Socket Proxy (DD-46)

Traefik requires access to the Docker API for service autodiscovery. Instead of
mounting the raw Docker socket (`/var/run/docker.sock`), which grants root-equivalent
access to the host, Traefik connects through a **Docker socket proxy**
(`tecnativa/docker-socket-proxy`).

The socket proxy exposes a restricted, read-only subset of the Docker API:

| Endpoint | Allowed | Rationale |
|----------|---------|------------|
| `GET /containers` | Yes | Traefik needs to discover running services |
| `GET /networks` | Yes | Traefik needs to know which networks to join |
| `GET /services` | Yes | Required for Docker Swarm mode (future-proof) |
| `POST /containers/*/exec` | **No** | Blocks arbitrary command execution in containers |
| `POST /containers/create` | **No** | Blocks creating new containers |
| `DELETE /containers/*` | **No** | Blocks removing containers |
| `POST /volumes` | **No** | Blocks volume manipulation |
| All other write operations | **No** | Default deny |

> **Threat mitigated**: A vulnerability in Traefik (or its image) that attempts to
> use the Docker API for privilege escalation is blocked by the proxy. The attacker
> can enumerate containers and networks (read-only) but cannot create, modify, or
> exec into containers.

The socket proxy runs as a dedicated service in the Traefik module's Compose file:

### Traefik Compose Rendering

```yaml
# templates/modules/traefik/docker-compose.yml.j2
---
services:
  # ── Docker Socket Proxy (DD-46) ──
  socket-proxy:
    image: {{ socket_proxy_image }}
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    read_only: true
    environment:
      - CONTAINERS=1              # allow read-only container listing
      - NETWORKS=1                # allow read-only network listing
      - SERVICES=1                # allow read-only service listing
      - POST=0                    # block all POST requests
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
    networks:
      - traefik-socket
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"

  traefik:
    image: {{ traefik_image }}
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    read_only: true
    depends_on:
      - socket-proxy
    ports:
      - "80:80"                   # HTTP→HTTPS redirect only (redirect-to-https middleware)
      - "443:443"
    environment:
      - DOCKER_HOST=tcp://socket-proxy:2375
    volumes:
      - {{ compose_modules_base_dir }}/traefik/config/traefik.yml:/traefik.yml:ro
      - {{ compose_modules_base_dir }}/traefik/config/dynamic:/etc/traefik/dynamic:ro
      - traefik_certs:/letsencrypt
    networks:
      - traefik-socket
{% for mod in effective_modules %}
{%   set mod_config = lookup('vars', mod + '_config', default={}) %}
{%   if mod_config.traefik.enabled | default(false) and mod != 'traefik' %}
      - {{ mod }}-frontend
{%   endif %}
{% endfor %}
    labels:
      - "traefik.enable=true"

networks:
  traefik-socket:
    internal: true                # socket proxy is never internet-accessible
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

> **Key changes from raw socket mount**: Traefik no longer mounts
> `/var/run/docker.sock` directly. Instead, it connects to the socket proxy via
> `DOCKER_HOST=tcp://socket-proxy:2375` over the internal `traefik-socket` network.
> The socket proxy is the only container with socket access, and it blocks all write
> operations.

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
that is **applied to all `service_type: web` modules by default** (DD-49). Modules must
explicitly opt out by setting `forward_auth: false` with a documented justification.

### Default-On Policy (DD-49)

The `forward-auth` middleware is automatically added to every `service_type: web` module
unless the module explicitly opts out:

```yaml
# Default behaviour — forward auth is applied automatically:
traefik:
  enabled: true
  host: "app.{{ domain }}"
  port: 8080
  middlewares:
    - secure-headers
  # forward-auth is added automatically by the deploy template
  # unless forward_auth: false is set

# Opting OUT of forward auth (explicit, with justification):
forward_auth: false
forward_auth_exempt_reason: "Public-facing API; authentication handled by the application"
```

The deploy template includes forward auth in the middleware chain unless opted out:

```yaml
# Standard Traefik labels (generated per module)
{% set module_middlewares = traefik.middlewares | default([]) %}
{% set needs_forward_auth = (service_type == 'web') and (forward_auth | default(true)) %}
{% if needs_forward_auth %}
{%   set module_middlewares = module_middlewares + ['forward-auth'] %}
{% endif %}
  - "traefik.http.routers.{{ module_name }}.middlewares={{ module_middlewares | map('regex_replace', '^forward-auth$', 'forward-auth@docker') | map('regex_replace', '^(?!.*@)', '\\0@file') | join(',') }}"
```

**CI validation** enforces that:
- Every `service_type: web` module either has forward auth (default) or explicitly sets
  `forward_auth: false` with a non-empty `forward_auth_exempt_reason`.
- The exempt reason is visible in the module vars for security review.

```bash
# tests/bash/module-schema-test.bats
@test "web modules without forward auth must document exemption reason" {
  for module_file in ansible/roles/docker_compose_modules/vars/modules/*.yml; do
    module_name=$(basename "$module_file" .yml)
    if grep -q "service_type: web" "$module_file" && \
       grep -q "forward_auth: false" "$module_file"; then
      grep -q "forward_auth_exempt_reason:" "$module_file" || \
        fail "Module $module_name opts out of forward auth without forward_auth_exempt_reason"
    fi
  done
}
```

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
The `deploy_priority` field (DD-32) ensures this ordering is deterministic:
Traefik has priority **10**, forward_auth has priority **15**, and application
modules default to **100**. This applies both to explicit `compose_modules`
lists and to `deploy_all_modules: true` discovery.

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

The Compose template generates an additional Traefik router that uses the
`health-bypass` middleware chain (rate-limit + local-network IP allowlist) instead
of forward-auth (see §21 for full middleware chain definitions):

```yaml
# Standard Traefik labels (generated per module) — health bypass
{% if healthcheck.path is defined and 'forward-auth' in traefik.middlewares | default([]) %}
  - "traefik.http.routers.{{ module_name }}-health.rule=Host(`{{ traefik.host }}`) && Path(`{{ healthcheck.path }}`)"
  - "traefik.http.routers.{{ module_name }}-health.entrypoints=websecure"
  - "traefik.http.routers.{{ module_name }}-health.tls=true"
  - "traefik.http.routers.{{ module_name }}-health.tls.certresolver=letsencrypt"
  - "traefik.http.routers.{{ module_name }}-health.service={{ module_name }}"
  - "traefik.http.routers.{{ module_name }}-health.middlewares=health-bypass@file"
{% endif %}
```

The `health-bypass` middleware chain (defined in Traefik's file provider) applies:
1. **Rate limiting** (10 req/min) to prevent abuse.
2. **IP allowlist** restricting access to internal networks only.

See §21 (Traefik Middleware Chains) for the full chain definition.

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

Gatus is configured with `GATUS_CONFIG_PATH=/config` which includes the
`endpoints.d/` directory (DD-41). Gatus has a built-in file watcher that
automatically reloads configuration when files in its config directory change.
No container restart is needed.

| Event | Gatus action |
|-------|-------------|
| Module deployed | Endpoint YAML written → Gatus auto-reloads (file watcher) |
| Module removed (cleanup) | Endpoint YAML deleted → Gatus auto-reloads (file watcher) |
| Module healthcheck disabled | Endpoint YAML deleted → Gatus auto-reloads (file watcher) |

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

### Secret Layering (DD-43)

```
1. group_vars/<server_type>/secrets.sops.yml          → per server group
2. host_vars/<hostname>/secrets.sops.yml              → per host (overrides group)
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

> **Jinja2 filter limitation**: `render_template.py` uses plain Jinja2, not Ansible's
> extended filter set. Ansible-specific filters (e.g., `ipaddr`, `regex_search`,
> `to_nice_yaml`) are **not available** in CI renders. If a Compose template uses
> Ansible-only filters, either:
> (a) add a shim filter in the Python helper, or
> (b) guard the filter with a mock fallback in the template.

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
    cap_drop:                       # DD-47 — drop all capabilities by default
      - ALL
    # cap_add:                      # Add back specific capabilities if needed
    #   - NET_BIND_SERVICE          # e.g., for binding to ports < 1024
    read_only: true                 # DD-48 — read-only rootfs by default
    # tmpfs:                        # Use tmpfs for writable directories if needed
    #   - /tmp
    #   - /run
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
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
      # ... standard Traefik labels (including forward-auth by default — DD-49)
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

# Note: The `_shared` directory is reserved for files shared across multiple
# modules (e.g., common scripts, shared TLS certificates). It is excluded
# from orphan detection because it is not a module directory.

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
- **Audit trail** (security-relevant events):
  - Which modules had secrets deployed (secret names only — never values)
  - Which `.env` files were written or updated
  - Rollback events (module name, reason, outcome)
  - Orphan modules removed during cleanup
  - Modules that skipped validation or had non-critical failures
  - SOPS pre-flight check result

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
# Note: These tests use grep for simplicity. For more robust YAML parsing,
# consider using yq (https://github.com/mikefarah/yq) which handles
# multi-line values, comments, and nested keys correctly.

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

@test "compose env var references match module secrets and env_extra (DD-42)" {
  # Validates that every ${VAR} reference in a compose template has a corresponding
  # entry in required_secrets (uppercased) or env_extra (exact name match).
  for compose_file in ansible/roles/docker_compose_modules/templates/modules/*/docker-compose.yml.j2; do
    module_name=$(basename "$(dirname "$compose_file")")
    [ "$module_name" = "_template" ] && continue

    module_vars="ansible/roles/docker_compose_modules/vars/modules/${module_name}.yml"
    [ -f "$module_vars" ] || continue

    # Extract ${VAR} references from compose template (skip Jinja2 {{ }} refs)
    env_refs=$(grep -oP '\$\{([A-Z_][A-Z0-9_]*)\}' "$compose_file" | sort -u || true)
    [ -z "$env_refs" ] && continue

    for ref in $env_refs; do
      var_name=$(echo "$ref" | sed 's/\${\(.*\)}/\1/')

      # Check if it matches an uppercased required_secret
      secret_lower=$(echo "$var_name" | tr '[:upper:]' '[:lower:]')
      if grep -q "- ${secret_lower}$" "$module_vars" 2>/dev/null; then
        continue
      fi

      # Check if it matches an env_extra name (exact case)
      if grep -q "name: ${var_name}$" "$module_vars" 2>/dev/null; then
        continue
      fi

      fail "Module $module_name: compose references \${$var_name} but no matching required_secret or env_extra found"
    done
  done
}
```

---

## 19. Concurrency & Locking (DD-35)

### Problem

ansible-pull runs on a systemd timer. If a deployment takes longer than the timer
interval, or multiple commits happen in quick succession, a second ansible-pull instance
can start while the first is still running. This causes race conditions: two instances
running `docker compose up` simultaneously, conflicting file writes, partial network
creation.

### Solution: `flock --nonblock`

The ansible-pull systemd service unit uses `flock` with `--nonblock` to acquire an
exclusive lock. If another instance is already running, the new invocation exits
immediately (exit code 1) without blocking.

```ini
# ansible-pull.service (excerpt)
[Service]
ExecStart=/usr/bin/flock --nonblock /var/lock/ansible-pull.lock \
  /usr/bin/ansible-pull \
    --url https://github.com/DevSecNinja/docker.git \
    --checkout main \
    --directory /var/lib/ansible/local \
    --inventory ansible/inventory/hosts.yml \
    --extra-vars "target_host=%H" \
    --only-if-changed \
    ansible/playbooks/main.yml
```

### Why `--nonblock` (Not `--wait`)

| Mode | Behaviour | Risk |
|------|-----------|------|
| `--wait` (blocking) | Second instance waits for the first to finish, then runs | Queue builds up; deployments stack; potential for very long runs |
| `--nonblock` (chosen) | Second instance exits immediately if lock held | Clean skip; next timer cycle will pick up changes |

### Lock File Lifecycle

- **Created**: Automatically by `flock` on first invocation.
- **Held**: While ansible-pull is running (kernel-level file lock).
- **Released**: Automatically when the ansible-pull process exits — **even if it crashes,
  is killed, or the system reboots**. `flock` uses POSIX advisory locks which are tied
  to the process, not the file. There is **no risk of a stale lock** requiring manual
  cleanup.
- **File on disk**: `/var/lock/ansible-pull.lock` persists as an empty file. This is
  harmless — `flock` only cares about the kernel lock state, not the file's contents.

> **Key point**: Unlike PID-file based locking, `flock` locks are automatically released
> on process exit. You will **never** need to manually delete the lock file.

### Timer Configuration

The systemd timer interval should be longer than the maximum expected deployment time:

```ini
# ansible-pull.timer (excerpt)
[Timer]
OnCalendar=*:0/15        # every 15 minutes
Persistent=false          # don't catch up on missed runs
```

- `NFR-1` targets < 2 minutes for a full sync, so a 15-minute timer provides ample margin.
- `Persistent=false` prevents a burst of catchup runs after a reboot.

---

## 20. Rollback Strategy (DD-36)

### Problem

When a `docker compose up` or post-deployment validation fails, the system is left in
a broken state: the new Compose file is on disk, containers may be partially started or
in a crash loop, and the previous working state is lost.

### Solution: `.bak` Backup with Conditional Restore

Before rendering a new Compose file, the existing one is backed up. The `.env` file
is also backed up alongside the Compose file (DD-52) to prevent version mismatch
between secrets and Compose configuration after a rollback. On critical validation
failure, both backups are restored. On success, both backups are cleaned up.

### Deployment Flow (Per Module)

```
1. If docker-compose.yml exists AND docker-compose.yml.bak does NOT exist:
     → copy docker-compose.yml → docker-compose.yml.bak
     → copy .env → .env.bak (mode 0600, if .env exists)
   (If .bak already exists, skip — a previous run may have failed and we
    don't want to overwrite the last-known-good backup)
2. Render new docker-compose.yml from template
3. Render new .env from secrets
4. Validate new Compose file (docker compose config)
5. docker compose up -d
6. Run post-deployment validation
7. If validation passes:
     → delete docker-compose.yml.bak and .env.bak (cleanup)
8. If validation fails AND validation.critical is true:
     → docker compose down
     → restore docker-compose.yml.bak → docker-compose.yml
     → restore .env.bak → .env (mode 0600)
     → docker compose up -d (restore previous state)
     → fail the playbook run
9. If validation fails AND validation.critical is false:
     → log warning
     → delete docker-compose.yml.bak and .env.bak (don't block next run)
     → continue with remaining modules
```

### Implementation

```yaml
# tasks/deploy_module.yml (rollback section)
---
# Step 1: Back up existing Compose file and .env (only if .bak doesn't already exist)
- name: "Back up {{ module_name }} compose file"
  ansible.builtin.copy:
    src: "{{ compose_modules_base_dir }}/{{ module_name }}/docker-compose.yml"
    dest: "{{ compose_modules_base_dir }}/{{ module_name }}/docker-compose.yml.bak"
    remote_src: true
    force: false                  # do NOT overwrite existing .bak
    mode: "0644"
  when:
    - _compose_file.stat.exists | default(false)

- name: "Back up {{ module_name }} .env file (DD-52)"
  ansible.builtin.copy:
    src: "{{ compose_modules_base_dir }}/{{ module_name }}/.env"
    dest: "{{ compose_modules_base_dir }}/{{ module_name }}/.env.bak"
    remote_src: true
    force: false                  # do NOT overwrite existing .bak
    mode: "0600"                  # secrets — root-only
  when:
    - _env_file.stat.exists | default(false)
  no_log: true

# ... (render new compose file + .env, docker compose up, validation) ...

# Step 7: Clean up .bak files on success
- name: "Clean up {{ module_name }} compose backup"
  ansible.builtin.file:
    path: "{{ compose_modules_base_dir }}/{{ module_name }}/{{ item }}"
    state: absent
  loop:
    - docker-compose.yml.bak
    - .env.bak
  when: _validation_passed

# Step 8: Rollback on critical failure
- name: "Rollback {{ module_name }} to previous state"
  when:
    - not _validation_passed
    - module_config.validation.critical | default(false)
  block:
    - name: "Stop failed {{ module_name }} containers"
      community.docker.docker_compose_v2:
        project_src: "{{ compose_modules_base_dir }}/{{ module_name }}"
        state: absent
      ignore_errors: true

    - name: "Restore {{ module_name }} compose backup"
      ansible.builtin.copy:
        src: "{{ compose_modules_base_dir }}/{{ module_name }}/docker-compose.yml.bak"
        dest: "{{ compose_modules_base_dir }}/{{ module_name }}/docker-compose.yml"
        remote_src: true
        mode: "0644"

    - name: "Restore {{ module_name }} .env backup (DD-52)"
      ansible.builtin.copy:
        src: "{{ compose_modules_base_dir }}/{{ module_name }}/.env.bak"
        dest: "{{ compose_modules_base_dir }}/{{ module_name }}/.env"
        remote_src: true
        mode: "0600"
      when: _env_bak_file.stat.exists | default(false)
      no_log: true

    - name: "Restart {{ module_name }} with previous compose file"
      community.docker.docker_compose_v2:
        project_src: "{{ compose_modules_base_dir }}/{{ module_name }}"
        state: present

    - name: "Clean up {{ module_name }} backups after rollback"
      ansible.builtin.file:
        path: "{{ compose_modules_base_dir }}/{{ module_name }}/{{ item }}"
        state: absent
      loop:
        - docker-compose.yml.bak
        - .env.bak

    - name: "Fail playbook — {{ module_name }} critical validation failed"
      ansible.builtin.fail:
        msg: >-
          Module '{{ module_name }}' failed post-deployment validation and has been
          rolled back to the previous compose and .env files. Investigate and fix
          before retrying.
```

### Important Constraints

- **No automatic data restore**: The rollback only restores the Compose file, `.env`
  file, and restarts the previous containers. Database migrations, volume data changes,
  or destructive operations are **not** reversed. This is a Compose-level rollback, not
  a full disaster recovery.
- **Atomic rollback (DD-52)**: Both `docker-compose.yml` and `.env` are restored
  together to prevent version mismatch between secrets and Compose configuration.
- **`.bak` protection**: The `force: false` on the backup step ensures that if a
  previous run failed (leaving a `.bak` in place), the next run does NOT overwrite it.
  This preserves the last-known-good configuration.
- **`.env.bak` security**: The `.env.bak` file is created with `mode: 0600` and uses
  `no_log: true` to prevent secret values from appearing in Ansible output.
- **`.bak` cleanup**: On success, the `.bak` is deleted so the next run can create a
  fresh backup. On rollback, the `.bak` is also deleted after restoration to prevent
  stale backups.
- **First deployment**: If no `docker-compose.yml` exists yet (first deploy), there is
  nothing to back up. A failed first deployment leaves the broken file in place for
  debugging — manual intervention is required.

---

## 21. Traefik Middleware Chains (DD-39)

### Overview

Traefik middlewares are defined as **file-based middleware definitions** in Traefik's
dynamic configuration directory. Modules reference middleware **chains** (not individual
middlewares) in their `traefik.middlewares` list. This approach is composable, reusable,
and avoids duplicating middleware labels across every module.

### Middleware Definitions

```yaml
# templates/modules/traefik/config/generic/middlewares.yml.j2
# Auto-generated by Ansible — do not edit manually
http:
  middlewares:
    # ── Redirect HTTP → HTTPS ──
    redirect-to-https:
      redirectScheme:
        scheme: "https"
        permanent: true

    # ── Rate limiting ──
    rate-limit:
      rateLimit:
        average: 200
        burst: 100

    # ── Secure headers ──
    secure-headers:
      headers:
        accessControlAllowMethods:
          - "GET"
          - "OPTIONS"
          - "PUT"
        accessControlMaxAge: 100
        hostsProxyHeaders:
          - "X-Forwarded-Host"
        stsSeconds: 63072000
        stsIncludeSubdomains: true
        stsPreload: true
        forceSTSHeader: true
        customFrameOptionsValue: "DENY"
        contentTypeNosniff: true
        browserXssFilter: true
        referrerPolicy: "same-origin"
        permissionsPolicy: >-
          camera 'none'; geolocation 'none'; microphone 'none';
          payment 'none'; usb 'none'; vr 'none';
        customRequestHeaders:
          X-Forwarded-Proto: https
        customResponseHeaders:
          X-Robots-Tag: "none,noarchive,nosnippet,notranslate,noimageindex,"
          server: ""

    # ── Forward auth (registered via Docker labels by forward_auth module) ──
    # forward-auth is registered as a Docker provider middleware.
    # Referenced as: forward-auth@docker

    # ── Health bypass chain (for Gatus monitoring) ──
    health-bypass:
      chain:
        middlewares:
          - rate-limit-health
          - whitelist-localnetwork

    # ── Rate limit for health endpoints (strict) ──
    rate-limit-health:
      rateLimit:
        average: 10
        burst: 5
        period: "1m"

    # ── IP allowlists ──
    whitelist-localnetwork:
      ipAllowList:
        sourceRange:
          - "192.168.0.0/16"
          - "10.0.0.0/8"
          - "172.16.0.0/12"

    whitelist-infra:
      ipAllowList:
        sourceRange:
          - "127.0.0.1/32"
{%- for host in groups['infrastructure_servers'] | default([]) %}
          - "{{ hostvars[host].ansible_host }}"
{%- endfor %}

    # ── Big file upload (disable buffering limits) ──
    big-file-upload:
      buffering:
        maxRequestBodyBytes: 0
        maxResponseBodyBytes: 0
        memRequestBodyBytes: 20971520
        memResponseBodyBytes: 20971520
        retryExpression: "IsNetworkError() && Attempts() < 2"
```

### Module Usage

Modules reference middleware names in their `traefik.middlewares` list. The deploy
template translates these into Traefik router labels:

```yaml
# In a module's vars/modules/<name>.yml
traefik:
  enabled: true
  host: "app.{{ domain }}"
  port: 8080
  middlewares:
    - secure-headers                # file provider middleware
    - forward-auth                  # Docker provider middleware (@docker suffix added)
```

Generated labels:

```yaml
# Multiple middlewares are comma-separated in the router label
- "traefik.http.routers.{{ module_name }}.middlewares=secure-headers@file,forward-auth@docker"
```

### Provider Suffixes

Traefik middlewares require a `@<provider>` suffix to avoid ambiguity:

| Source | Suffix | Example |
|--------|--------|---------|
| File provider (dynamic config) | `@file` | `secure-headers@file` |
| Docker provider (container labels) | `@docker` | `forward-auth@docker` |

The Compose template automatically appends `@file` for file-based middlewares and
`@docker` for `forward-auth` (which is registered via Docker labels by the
`forward_auth` module).

---

## 22. Container Logging (DD-40)

### Problem

Docker's default `json-file` log driver with no rotation limits will eventually fill
the host's disk. Every container's stdout/stderr is written to
`/var/lib/docker/containers/<id>/<id>-json.log` with no size cap.

### Solution: Enforce Log Rotation in Compose Templates

The module template (`_template/docker-compose.yml.j2`) includes logging configuration
by default. All modules must set `logging` on every service.

```yaml
# In every service definition in docker-compose.yml.j2
services:
  {{ module_name }}:
    image: "{{ '{{' }} {{ module_name }}_image {{ '}}' }}"
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    cap_drop:                       # DD-47
      - ALL
    read_only: true                 # DD-48
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
    # ... rest of service definition
```

### Enforced Rules

| Setting | Value | Rationale |
|---------|-------|-----------|
| `driver` | `json-file` | Compatible with `docker logs`; no external dependency |
| `max-size` | `10m` | 10 MB per log file — sufficient for most apps |
| `max-file` | `3` | 3 rotated files — max 30 MB per container |

### CI Validation

The compose-validation-test checks that all services define `logging`:

```bash
@test "compose templates enforce logging configuration" {
  for compose_file in ansible/roles/docker_compose_modules/templates/modules/*/docker-compose.yml.j2; do
    module_name=$(basename "$(dirname "$compose_file")")
    [ "$module_name" = "_template" ] && continue

    grep -q "max-size" "$compose_file" || \
      fail "Module $module_name compose missing logging max-size configuration"
  done
}
```

### Docker Daemon Default (Belt and Suspenders)

As a fallback, the Docker daemon is also configured with default log options via the
`geerlingguy.docker` role. This catches any containers started outside of the module
system:

```yaml
# In the playbook or host_vars — passed to geerlingguy.docker
docker_daemon_options:
  log-driver: "json-file"
  log-opts:
    max-size: "10m"
    max-file: "3"
```

---

## 23. Docker Network Address Pools (DD-38)

### Problem

Docker's default bridge driver allocates /16 subnets from the `172.17.0.0/12` range.
With per-module frontend + optional backend networks, a server with 20+ modules can
create 30-40 bridge networks, exhausting the address space.

### Solution: Custom Address Pool via `geerlingguy.docker`

Configure Docker's `daemon.json` with a single pool using smaller subnet allocations
via the `geerlingguy.docker` role. Only the `172.17.0.0/12` range is used — the
`192.168.0.0/16` range is deliberately excluded because the home LAN uses it.

```yaml
# ansible/playbooks/main.yml or host_vars — passed to geerlingguy.docker
roles:
  - role: geerlingguy.docker
    docker_daemon_options:
      default-address-pools:
        - base: "172.17.0.0/12"
          size: 20
```

### Capacity Calculation

| Pool | Base range | Subnet size | Hosts per subnet | Available subnets |
|------|-----------|-------------|------------------|-------------------|
| Single | `172.17.0.0/12` | /20 | 4094 | ~256 |

A /20 subnet provides 4094 usable host addresses per network — more than sufficient for
any Docker Compose stack. With ~256 available /20 subnets, this supports well over 100
modules per host without ever touching the `192.168.x.x` or `10.x.x.x` ranges.

### Considerations

- **Why no secondary pool**: The home LAN uses `192.168.0.0/16`, so including it as a
  Docker pool would cause routing conflicts. A single `172.17.0.0/12` pool with /20
  subnets provides more than enough capacity.
- **Existing networks**: Changing address pools does not affect existing Docker networks.
  New networks will use the new pool; existing ones retain their addresses until
  recreated.
- **This change is applied once** via the `geerlingguy.docker` role and persists in
  `/etc/docker/daemon.json`.

---

## 24. Disk Space Management

### Docker Image Garbage Collection

Over time, unused Docker images accumulate on the host as modules are updated via
Renovate (new image digests). The maintenance role handles periodic cleanup.

```yaml
# In the maintenance role — docker maintenance tasks
- name: Remove unused Docker images
  ansible.builtin.command:
    cmd: docker image prune --all --force --filter "until=168h"
  changed_when: false
  # Removes images not used by any container and older than 7 days.
  # The --all flag includes dangling AND unreferenced images.
  # The 7-day filter protects recently-pulled images during rollbacks.
```

### Build Cache Cleanup

If Docker BuildKit is used (not typical for this repo since we pull pre-built images),
the build cache can also grow:

```yaml
- name: Remove Docker build cache
  ansible.builtin.command:
    cmd: docker builder prune --all --force --filter "until=168h"
  changed_when: false
```

### Volume Cleanup

Orphaned volumes (from removed modules) are handled by the cleanup tasks (§15).
The `cleanup_remove_volumes` flag controls whether volumes are deleted on module
removal:

- **Dev servers**: `cleanup_remove_volumes: true` — aggressive cleanup.
- **Production servers**: `cleanup_remove_volumes: false` — volumes preserved.

### Disk Space Monitoring

A Gatus endpoint can monitor disk usage on each host by checking a simple script
endpoint or using node-exporter metrics (when the monitoring stack is deployed in
Phase 6).

### Systemd Timer

Docker maintenance (image prune, build cache cleanup) runs on a weekly systemd timer
managed by the `maintenance` role. See the existing `maintenance-docker.timer`.

---

## 25. TLS Certificate Strategy (DD-44)

### Certificate Authority

All TLS certificates are issued by **Let's Encrypt** via Traefik's built-in ACME client.

### Challenge Type: DNS-01 via Cloudflare

DNS-01 challenges are used instead of HTTP-01 because:

1. **No inbound port 80 required**: HTTP-01 requires Let's Encrypt to reach port 80 on
   the server, which may be blocked by firewalls or NAT.
2. **Wildcard certificates**: DNS-01 supports `*.example.com` wildcards, reducing the
   number of certificates and certificate requests.
3. **Internal services**: Services not reachable from the internet can still get valid
   certificates via DNS validation.

### Traefik Configuration

```yaml
# templates/modules/traefik/config/generic/traefik.yml.j2 (excerpt)
certificatesResolvers:
  letsencrypt:
    acme:
      email: "{{ acme_email }}"
      storage: "/letsencrypt/acme.json"
      dnsChallenge:
        provider: cloudflare
        resolvers:
          - "1.1.1.1:53"
          - "1.0.0.1:53"
```

### Required Secrets

The Cloudflare API token is stored in SOPS and delivered to the Traefik container
via the `.env` file:

```yaml
# In the traefik module's required_secrets
required_secrets:
  - traefik_cf_api_token

# .env renders:
# TRAEFIK_CF_API_TOKEN=<decrypted value>
```

The Traefik Compose template passes the token as an environment variable:

```yaml
# templates/modules/traefik/docker-compose.yml.j2 (excerpt)
services:
  traefik:
    environment:
      - CF_API_EMAIL={{ acme_email }}
      - CF_DNS_API_TOKEN=${TRAEFIK_CF_API_TOKEN}
```

### Certificate Storage

Certificates are stored in a named Docker volume (`traefik_certs`) mounted at
`/letsencrypt`. This persists certificates across container restarts and avoids
hitting Let's Encrypt rate limits by re-requesting certificates on every restart.

### Rate Limits

Let's Encrypt enforces rate limits (50 certificates per registered domain per week).
With DNS-01 and wildcard certificates, this is unlikely to be an issue. The staging
environment (`acme.caServer: https://acme-staging-v02.api.letsencrypt.org/directory`)
should be used during development and testing.

---

## 26. Backup Strategy (Roadmap)

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

## 27. Auto-Generated Service Inventory (Roadmap)

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

## 28. Auto-Merge & Update Strategy (Roadmap)

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

## 29. AI Authoring & Module Templates

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
- `cap_drop: [ALL]` on every service (add back specific caps with `cap_add` if needed) (DD-47)
- `read_only: true` on every service (use `tmpfs` for writable dirs; opt out with `allow_writable_rootfs`) (DD-48)
- `restart: unless-stopped`
- `logging` with `max-size` and `max-file` on every service (DD-40)
- No `ports:` unless `exposed_ports` is defined in module vars
- No `privileged: true` unless `allow_privileged: true` in module vars
- Forward auth is applied automatically for `service_type: web` (DD-49); opt out with `forward_auth: false` + `forward_auth_exempt_reason`
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

## 30. Implementation Order

### Phase 1 — Foundation

| Task | Description |
|------|-------------|
| 1.1 | Restructure inventory with server groups and environments |
| 1.2 | Implement SOPS + Age integration (ansible.cfg, requirements, .sops.yaml) |
| 1.3 | Create initial secret files (group + host SOPS files with placeholder keys) |
| 1.4 | Implement shared group keys for SOPS |
| 1.5 | Update `ansible-pull.sh` for Age key injection (host key + group key) |
| 1.6 | Configure Docker address pools via `geerlingguy.docker` (§23) |
| 1.7 | Implement concurrency locking in ansible-pull.service (flock §19) |
| 1.8 | Create module template scaffold (`_template/`) with security defaults (§13, §22: cap_drop, read_only, logging) |
| 1.9 | Implement module resolution logic with pre-loading + priority sort + multi-group assertion (§4, §5) |
| 1.10 | Update `deploy_module.yml` with targeting + config layering |
| 1.11 | Implement `.env` file templating for secrets → containers |
| 1.12 | Add image pinning convention + Renovate custom manager with critical DB labels |
| 1.13 | Implement SOPS environment pre-flight check (DD-50: key file validation + canary secret) |
| 1.14 | Implement secret validation pre-flight (`validate_secrets.yml`) |
| 1.15 | Implement Docker Compose validation task (`validate_compose.yml`) with security rules (DD-47, DD-48, DD-49) |
| 1.16 | Create CI compose validation tooling (mock vars, render helper, Bats test) |
| 1.17 | Write Bats tests: module-schema-test, compose-validation-test, secret-structure-test, .env-naming-test |
| 1.18 | Configure branch protection on `main` + CODEOWNERS file (DD-45) |

### Phase 2 — Network, Traefik & First Module

| Task | Description |
|------|-------------|
| 2.1 | Implement per-module network creation tasks (frontend + backend isolation) |
| 2.2 | Render Traefik Compose dynamically with socket proxy (DD-46) and all frontend networks |
| 2.3 | Create Traefik middleware chain file (§21) |
| 2.4 | Add Traefik enforcement assertion for `service_type: web` |
| 2.5 | Implement TLS certificate strategy (Let's Encrypt DNS-01 via Cloudflare §25) |
| 2.6 | Migrate existing Traefik module to new structure |
| 2.7 | Deploy `traefik-forward-auth` module with default-on policy (DD-49) |
| 2.8 | Deploy `mendhak/http-https-echo` as validation/test module behind Traefik |
| 2.9 | Verify end-to-end: Traefik → socket-proxy → forward-auth → echo container |
| 2.10 | Implement rollback strategy with `.bak` backup/restore for both compose + .env (DD-52, §20) |
| 2.11 | Implement dry-run support (`--check --diff` compatibility on all tasks) |
| 2.12 | Write Bats tests: network-test, dry-run-test, .env-naming-validation-test, forward-auth-default-test |

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

## 31. Resolved Decisions

Decisions made during the design phase that are no longer open:

| # | Original Question | Decision |
|---|-------------------|----------|
| 1 | Separate DNS zone for dev? | **Yes** — dev server uses `*.dev.example.com` |
| 2 | Database migration handling? | **Roadmap** — label major/minor DB packages as critical in Renovate; manual review for now |
| 3 | Enforce resource limits? | **Optional** — recommended but not mandatory per module |
| 5 | `cleanup_remove_volumes` defaults? | **Yes** — `true` on dev, `false` on prod |
| 6 | Multi-server services? | **Out of scope** |
| 7 | Separate develop branch? | **No** — single `main` branch; auto-merge strategy on roadmap |
| 8 | Private Docker registry? | **Not needed** — public registries sufficient |
| 9 | DNS record generation approach? | **Option B (static)** — ansible-pull has no cross-host facts; static from inventory + module vars |
| 10 | Standardise health endpoint paths? | **No** — `healthcheck.path` is optional per module; not every image has a health endpoint |
| 11 | DNS resolver config on Docker hosts? | **Via DHCP** — not managed by Ansible; infra servers get Quad9 upstream via Ansible task (loop prevention) |
| 12 | Which services should be exempt from forward auth? | **Resolved by DD-49** — forward auth is default-on for all `service_type: web` modules; opt out with `forward_auth: false` + `forward_auth_exempt_reason` in module vars |

---

## 32. Open Questions

| # | Question | Context |
|---|----------|---------|
| 1 | What alerting channels for Gatus? Discord, email, PagerDuty? | Needs to be decided per environment |
| 2 | Should the echo test container remain deployed in production? | Useful for debugging vs. minimal surface |
| 3 | What Azure Blob retention policy for backups? | Cost vs. recovery window trade-off |
| 4 | Should ansible-pull timer frequency differ between dev and prod? | More frequent on dev for faster iteration |

---

## 33. Roadmap Items

Items acknowledged as valuable but explicitly deferred beyond Phase 6:

| # | Item | Notes |
|---|------|-------|
| 1 | **Failure notifications** | Ansible-pull failures are currently silent. Options: systemd `OnFailure=` handler posting to Discord/Slack webhook, email via `msmtp`, or a dedicated Ansible callback plugin. |
| 2 | **Schema evolution / migration strategy** | As the module schema evolves (new required fields, renamed keys), existing module definitions may break. Options: version field in module vars, migration script that transforms old → new, or strict backward compatibility with deprecation warnings. |
| 3 | **External monitoring** | Gatus monitors from inside the Docker host. An external monitor (e.g., Uptime Kuma on a separate server, or a SaaS like Uptime Robot) provides independent verification that the host itself is reachable and healthy. |
| 4 | **Centralized logging** | Replace per-host `json-file` log retention with a Loki + Promtail stack that aggregates logs across all hosts (Phase 6.5). |
| 5 | **Configuration drift detection** | Periodic comparison of running containers vs. declared module state. Detect manual `docker run` commands or `docker compose up` outside of ansible-pull. |
| 6 | **Secret rotation** | Automated secret rotation with zero-downtime container restarts. Requires SOPS re-encryption + Compose recreate in a single atomic operation. |
