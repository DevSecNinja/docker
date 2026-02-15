# Architecture: Komodo-Managed Docker Infrastructure

**Status**: Draft — February 2026

**Author**: Jean-Paul van Ravensberg (DevSecNinja) with AI assistance

**Repository**: <https://github.com/DevSecNinja/docker> (public)

**Previous Architecture**: [Ansible Pull Architecture](../ansible-pull/ARCHITECTURE.md) (superseded)

---

## Table of Contents

- [1. Overview](#1-overview)
- [2. Goals & Requirements](#2-goals--requirements)
- [3. Architecture Principles](#3-architecture-principles)
- [4. Design Decisions](#4-design-decisions)
- [5. Portability & Lock-in Assessment](#5-portability--lock-in-assessment)
- [6. AI Agent Interaction Model](#6-ai-agent-interaction-model)
- [7. Hybrid Architecture Model](#7-hybrid-architecture-model)
- [8. Komodo Core Deployment (Azure VM)](#8-komodo-core-deployment-azure-vm)
- [9. Komodo Periphery Deployment (On-Premises)](#9-komodo-periphery-deployment-on-premises)
- [10. Server Classification & Trust Tiers](#10-server-classification--trust-tiers)
- [11. Secure Connectivity](#11-secure-connectivity)
- [12. Stacks (Application Deployment)](#12-stacks-application-deployment)
- [13. ResourceSync (GitOps)](#13-resourcesync-gitops)
- [14. Secret Management](#14-secret-management)
- [15. Network Isolation](#15-network-isolation)
- [16. Traefik Integration](#16-traefik-integration)
- [17. Traefik Forward Auth](#17-traefik-forward-auth)
- [18. Container Hardening Standards](#18-container-hardening-standards)
- [19. Image Pinning & Renovate](#19-image-pinning--renovate)
- [20. DNS Management](#20-dns-management)
- [21. Monitoring & Healthchecks](#21-monitoring--healthchecks)
- [22. TLS Certificate Strategy](#22-tls-certificate-strategy)
- [23. Backup Strategy](#23-backup-strategy)
- [24. Testing Strategy](#24-testing-strategy)
- [25. Implementation Order](#25-implementation-order)
- [26. Migration from Ansible Pull](#26-migration-from-ansible-pull)
- [27. Open Questions](#27-open-questions)
- [28. Roadmap Items](#28-roadmap-items)

---

## 1. Overview

This repository manages Docker-based homelab infrastructure using a **hybrid model**:

- **Ansible** provisions servers at the system level (OS packages, users, SSH keys, firewall, Docker engine).
- **[Komodo](https://github.com/moghtech/komodo)** manages application-level orchestration (Docker Compose stacks, secrets, deployment lifecycle, monitoring).

Komodo follows a **Core + Periphery** architecture:

- **Core** runs on a small Azure VM and provides the web UI, API, database, and ResourceSync engine.
- **Periphery** agents run on each on-premises Docker server and execute stack deployments on behalf of Core.

### Why Komodo over Ansible Pull

The [previous architecture](../ansible-pull/ARCHITECTURE.md) designed a comprehensive Ansible Pull-based module system with custom Jinja2 templating, SOPS secret pipelines, Gatus generation, DNS automation, and rollback logic. None of this was built beyond basic roles.

Komodo provides most of these features **out of the box** — stack management, secrets, UI, monitoring, webhooks, and a REST API — eliminating months of custom platform engineering. The trade-off is a dependency on Komodo Core being reachable (accepted; see NFR-4).

### High-Level Flow

```
                    ┌────────────────────────────────────────────┐
                    │  Komodo Core (Azure VM, Debian Trixie)     │
                    │  ┌──────────┐  ┌──────────┐  ┌─────────┐  │
                    │  │ Core API │  │ Web UI   │  │ MongoDB │  │
                    │  └────┬─────┘  └──────────┘  └─────────┘  │
                    │       │                                    │
                    │  ┌────▼─────────────────────┐              │
                    │  │ ResourceSync Engine      │              │
                    │  │ (pulls from this Git repo│              │
                    │  │  on push / schedule)     │              │
                    │  └──────────────────────────┘              │
                    └──────────────┬─────────────────────────────┘
                                  │ Encrypted overlay network
                                  │ (no inbound ports on-prem)
                    ┌─────────────┼──────────────────┐
                    │             │                   │
            ┌───────▼──────┐ ┌───▼──────────┐ ┌──────▼───────┐
            │ Periphery    │ │ Periphery    │ │ Periphery    │
            │ svlazdock1   │ │ (future      │ │ (future      │
            │ (trusted)    │ │  trusted)    │ │  untrusted)  │
            └──────────────┘ └──────────────┘ └──────────────┘
```

### What Changed from Ansible Pull Architecture

| Concern | Ansible Pull (old) | Komodo (new) |
|---------|-------------------|--------------|
| Application deployment | Custom Ansible `docker_compose_modules` role with Jinja2 templates | Komodo Stacks (native Docker Compose) |
| Secret management | SOPS + Age with group/host key distribution | Komodo Variables & Secrets (stored in Core DB) |
| Deployment ordering | `deploy_priority` integers + Ansible task sorting | Komodo `after` dependency declarations |
| Healthchecks | Custom Gatus YAML generation per module | Komodo built-in server/container monitoring + optional Gatus Stack |
| Configuration as code | Jinja2 Compose templates in Ansible role | Plain Docker Compose files (engine-agnostic) + ResourceSync TOML |
| Rollback | Custom `.bak` backup/restore logic | Komodo one-click stack redeploy + Git history |
| Web UI | None | Komodo Web UI |
| API | None | Komodo REST API |
| DNS automation | Custom Jinja2 Unbound zone generation | Simpler: manual or scripted via Komodo Procedures |
| System provisioning | Ansible Pull (remains) | Ansible Pull (remains — unchanged) |

---

## 2. Goals & Requirements

### Functional Requirements

| ID | Requirement | Priority | Komodo Feature |
|----|-------------|----------|----------------|
| FR-1 | Select which applications deploy to which server | Must | Stacks bound to Servers |
| FR-2 | Web UI for deployment management | Must | Komodo Core UI |
| FR-3 | REST API for automation and AI agent integration | Must | Komodo API + API Keys |
| FR-4 | All web frontends routed through Traefik | Must | Traefik Stack with file-based routing |
| FR-5 | Per-application network isolation | Must | Per-stack Docker networks |
| FR-6 | Encrypted secret management without plaintext in Git | Must | Komodo Variables & Secrets |
| FR-7 | GitOps — declarative infrastructure from this repository | Must | ResourceSync |
| FR-8 | Container monitoring and alerting | Must | Komodo built-in monitoring |
| FR-9 | Docker images pinned by version and SHA digest | Must | Renovate + Compose files |
| FR-10 | Trusted / Untrusted server tiers with scoped secrets | Must | Server tags + secret scoping |
| FR-11 | Forward auth on all protected web services | Must | Traefik middleware |
| FR-12 | DNS management for internal services | Should | AdGuard + Unbound Stack |
| FR-13 | Deployment ordering (infrastructure before apps) | Should | Stack `after` dependencies |
| FR-14 | Automated cleanup of removed stacks | Should | Komodo Stack lifecycle |
| FR-15 | Backup to Azure Blob Storage | Could | Backup Stack (roadmap) |
| FR-16 | Auto-merge / update strategy for Renovate | Could | GitHub Actions + Komodo webhooks |
| FR-17 | Compose files portable to other engines (Dockge, Portainer, CLI) | Must | Docker Compose-native syntax preferred; Komodo-specific syntax minimized |
| FR-18 | AI agent-driven stack management via API and Git | Must | Komodo REST API + Git-based Compose files |
| FR-19 | Core accessible behind reverse proxy | Must | Reverse proxy on Core VM terminates TLS |

### Non-Functional Requirements

| ID | Requirement | Target |
|----|-------------|--------|
| NFR-1 | Stack deployment time | < 60 seconds per stack |
| NFR-2 | Public repository — no plaintext secrets | Always |
| NFR-3 | Testable in CI (GitHub Actions) | Always |
| NFR-4 | Offline tolerance — running stacks survive Core downtime | Always (accepted trade-off: new deployments require Core) |
| NFR-5 | System provisioning independent of Komodo | Always (Ansible handles OS-level) |
| NFR-6 | Engine portability — Compose files work with `docker compose up` standalone | Always |
| NFR-7 | No inbound ports opened on on-premises servers | Always (overlay network initiates outbound) |
| NFR-8 | Mono-repository for Ansible + Komodo configs | Always (single source of truth) |

### Security Trust Model

This repository is **public**. The security architecture assumes adversaries have full read access to all non-encrypted content.

#### Trust Chain

```
Git push → ResourceSync detects change → Komodo Core processes
  → Core instructs Periphery via encrypted overlay network
  → Periphery executes docker compose up on target server
```

**Pushing code to `main` controls what Komodo deploys.** Branch protection, CI checks, and CODEOWNERS protect this boundary.

Additionally, **Komodo Core credentials (API keys, admin password) control the deployment pipeline.** Core access is protected by authentication (local auth or OIDC), a reverse proxy, and network-level controls.

Core and Periphery communicate exclusively over an **encrypted overlay network** (see [Section 11](#11-secure-connectivity)). No inbound ports are opened on on-premises servers.

#### Trust Boundaries

```
┌─────────────────────────────────────────────────────────────────┐
│ TRUST BOUNDARY 1: Git repository (main branch)                 │
│   Who: contributors, CI, Renovate, AI agents                   │
│   Controls: branch protection, required reviews, CODEOWNERS,   │
│             CI checks                                          │
└───────────────────────────┬─────────────────────────────────────┘
                            │ ResourceSync pull
┌───────────────────────────▼─────────────────────────────────────┐
│ TRUST BOUNDARY 2: Komodo Core (Azure VM, behind reverse proxy) │
│   Who: authenticated users, API key holders, AI agents          │
│   Controls: OIDC/local auth, API keys, TLS, reverse proxy,     │
│             firewall, overlay network                           │
└───────────────────────────┬─────────────────────────────────────┘
                            │ Encrypted overlay + passkey
┌───────────────────────────▼─────────────────────────────────────┐
│ TRUST BOUNDARY 3: Periphery agent → Container runtime          │
│   Who: Komodo Core (authenticated)                             │
│   Controls: passkey auth, overlay encryption, unprivileged      │
│             komodo user, container hardening, trust tier         │
└───────────────────────────┬─────────────────────────────────────┘
                            │ Traefik reverse proxy
┌───────────────────────────▼─────────────────────────────────────┐
│ TRUST BOUNDARY 4: Network ingress                              │
│   Who: HTTP/HTTPS clients                                      │
│   Controls: TLS termination, forward auth, rate limiting,      │
│             secure headers, IP allowlists, trust tier policies  │
└─────────────────────────────────────────────────────────────────┘
```

#### Accepted Risks

| Risk | Severity | Rationale |
|------|----------|-----------|
| Komodo Core downtime blocks new deployments | Medium | Running stacks continue operating; Core is on Azure with SLA |
| Komodo Core compromise = control over all servers | High | Mitigated by strong auth, network restrictions, TLS, and limited Periphery user permissions |
| Secrets stored in Komodo DB, not Git-auditable | Low | Trade-off for operational simplicity; Core DB is on encrypted Azure disk |
| Public repo exposes Compose files and stack structure | Low | No secrets in Compose files; structure knowledge alone is not exploitable |
| Overlay network dependency for Core ↔ Periphery | Medium | If overlay goes down, running stacks continue but no new deployments; overlay is self-healing |
| Komodo engine lock-in | Low | Architecture principle AP-1 minimizes lock-in; Compose files are engine-agnostic (see [Section 5](#5-portability--lock-in-assessment)) |

---

## 3. Architecture Principles

These principles guide all technical decisions in this architecture. Every design decision and implementation choice must be traceable to one or more of these principles.

| ID | Principle | Statement | Rationale |
|----|-----------|-----------|-----------|
| AP-1 | **Compose-First Portability** | Prefer Docker Compose-native features over orchestration engine-specific syntax. Compose files must be deployable with `docker compose up` standalone using a `.env` file. | Prevents vendor lock-in to Komodo. If the orchestration engine changes (to Dockge, Portainer, or raw CLI), the Compose files remain valid without modification. Only the deployment glue (TOML sync files, variable injection) changes. |
| AP-2 | **Minimal Orchestration Coupling** | Use Komodo (or any engine) only for features that have no Docker Compose equivalent: GitOps sync, deployment orchestration, multi-server management, UI/API, and monitoring. Never encode business logic in engine-specific configuration. | Keeps the blast radius of an engine swap small. See [Section 5](#5-portability--lock-in-assessment) for the lock-in assessment. |
| AP-3 | **Infrastructure as Code** | All configuration — Ansible roles, Compose files, ResourceSync TOML, Traefik routes — must live in Git. Manual changes are temporary and must be codified before the next release. | Auditability, reproducibility, and rollback via Git history. |
| AP-4 | **Least Privilege** | Every component runs with the minimum permissions required. Containers drop all capabilities by default. Periphery runs as an unprivileged user. Secrets are scoped to the servers that need them. | Defense in depth. A compromised container or Periphery agent has limited blast radius. |
| AP-5 | **Trust Tier Isolation** | Servers are classified as **trusted** or **untrusted**. Sensitive stacks and secrets are restricted to trusted servers. Untrusted servers receive additional hardening and restricted secret scopes. | Supports DMZ and public-facing deployments without exposing internal secrets or services. |
| AP-6 | **Zero Inbound Ports** | On-premises servers must not open inbound ports to the internet or to the Azure VM. All Core ↔ Periphery communication flows over an encrypted overlay network initiated outbound from on-premises. | Eliminates the attack surface of open ports on the home network. |
| AP-7 | **Separation of Concerns** | Ansible manages the OS layer (packages, users, firewall, Docker engine). Komodo manages the application layer (stacks, secrets, deployment lifecycle). Neither crosses into the other's domain. | Clear ownership boundaries. Each tool is used for what it does best. |
| AP-8 | **Mono-Repository** | Ansible roles, Compose stacks, ResourceSync TOML, Traefik configuration, and CI tests all live in this single repository. | Single source of truth. Atomic commits span system and application layers. One CI pipeline validates everything. Simpler for a homelab with a single operator. |

### Compose-First Decision Framework

When implementing a feature, follow this decision tree:

```
Is there a Docker Compose-native way to do this?
    │
    ├── YES → Use Docker Compose syntax
    │         Examples: ${VAR} interpolation, depends_on,
    │                   healthcheck, networks, volumes,
    │                   secrets (file-based), profiles
    │
    └── NO → Is there a standard Docker ecosystem tool?
              │
              ├── YES → Use the standard tool
              │         Examples: .env files, docker-compose.override.yml
              │
              └── NO → Use Komodo-specific feature
                        Examples: ResourceSync TOML, [[SECRET]] for
                                  Komodo-managed secrets, Procedures,
                                  Stack-to-Server binding, monitoring
```

> **Key implication**: Compose files use `${VARIABLE}` (Docker Compose native interpolation) for all variables. Komodo injects these as environment variables at deployment time. For standalone deployment, a `.env` file provides the same values. The Komodo-specific `[[VARIABLE]]` syntax is reserved for cases where Komodo-managed secrets must be interpolated before the Compose file reaches Docker Compose (e.g., values that cannot be environment variables).

---

## 4. Design Decisions

| ID | Decision | Choice | Rationale |
|----|----------|--------|-----------|
| DD-1 | Application orchestration | Komodo (Core + Periphery) | Provides UI, API, secrets, monitoring, webhooks out of the box; eliminates custom Ansible module system. Compose files remain engine-agnostic per AP-1. |
| DD-2 | System provisioning | Ansible Pull (retained) | Proven for OS-level tasks; Komodo does not manage OS configuration |
| DD-3 | Periphery installation | `bpbradley/ansible-role-komodo` via Ansible | Automates Periphery agent deployment with proper user isolation and systemd integration |
| DD-4 | Core deployment | Azure VM with Docker Compose (Debian 13 Trixie) | Small VM (B2s); Core runs as Docker Compose stack with MongoDB behind a reverse proxy |
| DD-5 | Variable interpolation | Docker Compose `${VAR}` syntax (native) | Engine-agnostic per AP-1. Komodo injects variables as environment variables. Standalone deployment uses `.env` files. `[[VAR]]` syntax reserved for Komodo-managed secrets only. |
| DD-6 | GitOps | Komodo ResourceSync | Pulls TOML resource definitions from this Git repo; applies on push via webhook. Engine-specific glue (acceptable per AP-2). |
| DD-7 | Traefik routing model | File-based dynamic configuration | Decouples Traefik from needing to join every app's Docker network; explicit route definitions |
| DD-8 | Network isolation | Per-stack `<app>-frontend` + `<app>-backend` networks | Same isolation model as previous architecture; Traefik does NOT join per-app networks |
| DD-9 | Image pinning | Version + SHA digest in Compose files | Deterministic; Renovate auto-bumps via PRs |
| DD-10 | Container hardening | `cap_drop: [ALL]`, `read_only: true`, `no-new-privileges`, logging limits | Carried forward from previous architecture (DD-47, DD-48) |
| DD-11 | Forward auth | Default-on for all web-facing stacks | Centralized authentication via Traefik middleware |
| DD-12 | Docker network pools | `172.17.0.0/12` with /20 subnets | Avoids LAN conflict; ~256 networks per host |
| DD-13 | TLS certificates | Let's Encrypt DNS-01 via Cloudflare | Supports wildcard certs; no inbound port 80 dependency for validation |
| DD-14 | Periphery systemd scope | `user` scope (least privilege) | Recommended by `bpbradley/ansible-role-komodo`; cgroup isolation from system services |
| DD-15 | Core authentication | Local auth initially; OIDC later | Simple bootstrap; migrate to OIDC when identity provider is in place |
| DD-16 | Core database | MongoDB | Komodo's primary supported database. User already operates MongoDB containers, so no new engine is introduced. `mongodump`/`mongorestore` is proven for backups. `tiredofit/docker-db-backup` has explicit MongoDB support. FerretDB was considered but rejected — see DD-16a. |
| DD-16a | FerretDB rejected | MongoDB preferred over FerretDB | FerretDB adds an abstraction layer over PostgreSQL/SQLite that can introduce subtle MongoDB compatibility issues. Backup tooling (`tiredofit/docker-db-backup`) does not explicitly support FerretDB — it would require backing up the underlying PostgreSQL/SQLite, bypassing the MongoDB-compatible API. The user already runs MongoDB, Postgres, and MariaDB; FerretDB on Postgres avoids a new engine but adds an untested abstraction. MongoDB is Komodo's primary database and the path of least operational risk. "Set and forget" favors the battle-tested option. |
| DD-17 | Ansible Pull rejected for app layer | Custom Jinja2 module system was over-engineered | Months of custom platform engineering replaced by Komodo's built-in features |
| DD-18 | SOPS rejected for secrets | Komodo's built-in secret management is sufficient | Simpler operational model; no key distribution; trade-off: less Git-auditable |
| DD-19 | Docker socket proxy for Traefik | `tecnativa/docker-socket-proxy` | Limits Docker API access to read-only; blocks exec/create/delete operations |
| DD-20 | Komodo UI write protection | `ui_write_disabled = false` initially | Allow UI writes during setup; consider enabling after ResourceSync is stable |
| DD-21 | Core ↔ Periphery connectivity | Encrypted overlay network (no inbound ports on-prem) | Per AP-6. On-prem servers initiate outbound connections to form an encrypted mesh. No firewall ports opened on the home network. Options: Tailscale, Headscale, WireGuard, Nebula. See [Section 11](#11-secure-connectivity). |
| DD-22 | Server trust tiers | Trusted / Untrusted classification | Per AP-5. Servers in the trusted VLAN receive all secrets. Servers in DMZ/public IP (untrusted) receive only scoped secrets and run with additional hardening (e.g., `komodo_disable_terminals: true`, `komodo_disable_container_exec: true`). |
| DD-23 | Core OS | Debian 13 (Trixie) | Stable, minimal, long support cycle. Consistent with on-premises servers. Preferred over Ubuntu for server workloads due to smaller attack surface and no Snap/Canonical telemetry. |
| DD-24 | Repository strategy | Mono-repository | Per AP-8. One repo for Ansible roles + Komodo stacks + CI/CD. Simpler than multi-repo for a single-operator homelab. Cross-concern changes (e.g., new server + its stacks) are atomic. |
| DD-25 | Core reverse proxy | TBD (Caddy, Traefik, or Nginx on Core VM) | Core must be behind a reverse proxy for TLS termination, security headers, and rate limiting. Core port 9120 binds to `127.0.0.1` only. See [Open Questions](#27-open-questions). |
| DD-26 | Development server | Not needed | No separate dev server in the Komodo architecture. Testing is done via CI pipeline. New stacks can be validated on the production server with Komodo's redeploy/rollback capability. |

---

## 5. Portability & Lock-in Assessment

This section quantifies how much of the architecture is Komodo-specific vs. engine-agnostic, enabling informed decisions about future orchestration engine changes (e.g., migrating to Dockge, Portainer, or plain `docker compose` CLI).

### Lock-in Classification

| Component | Portable? | Lock-in Level | Migration Effort | Notes |
|-----------|-----------|---------------|------------------|-------|
| **Docker Compose files** (`komodo/stacks/*/docker-compose.yml`) | ✅ Yes | None | Zero | Standard Compose files with `${VAR}` interpolation. Work with any engine or `docker compose up` directly. |
| **`.env.example` files** | ✅ Yes | None | Zero | Standard Docker Compose `.env` format. |
| **Traefik configuration** (static + dynamic YAML) | ✅ Yes | None | Zero | Pure Traefik config, independent of Komodo. |
| **Traefik route files** (`config/dynamic/routers/*.yml`) | ✅ Yes | None | Zero | Standard Traefik file provider format. |
| **Docker networks** (per-stack isolation) | ✅ Yes | None | Zero | Standard Docker Compose networking. |
| **Container hardening** (security_opt, cap_drop, etc.) | ✅ Yes | None | Zero | Standard Compose service options. |
| **Image pinning** (registry + tag + SHA) | ✅ Yes | None | Zero | Standard Compose image format. |
| **Renovate image updates** | ✅ Yes | None | Zero | Operates on Compose files, not Komodo. |
| **Ansible system roles** | ✅ Yes | None | Zero | Independent of application orchestration. |
| **ResourceSync TOML files** (`komodo/sync/*.toml`) | ❌ No | **High** | Medium | Komodo-specific. Would need equivalent in new engine (e.g., Portainer stacks API, Dockge API). |
| **`[[SECRET]]` interpolation** (if used) | ❌ No | **High** | Medium | Komodo-specific syntax. Architecture minimizes usage per AP-1/DD-5. |
| **Komodo Procedures** (`procedures.toml`) | ❌ No | **Medium** | Low | Automation workflows. Replace with shell scripts, CI pipelines, or new engine's equivalent. |
| **Komodo Variables/Secrets store** | ❌ No | **Medium** | Medium | Secret values stored in Komodo DB. Would need export → re-import into new engine or vault. |
| **Stack-to-Server binding** | ❌ No | **Medium** | Low | Mapping of which stack deploys where. Trivially re-created in any engine. |
| **Komodo built-in monitoring** | ❌ No | **Low** | Low | Replace with Prometheus/Grafana, Uptime Kuma, or new engine's monitoring. |
| **Periphery agent** | ❌ No | **High** | Medium | Would be removed; replaced by new engine's agent or direct SSH/Docker API access. |

### Lock-in Summary

| Category | Count | Percentage |
|----------|-------|------------|
| **Fully portable** (zero migration effort) | 10 components | ~59% |
| **Komodo-specific** (requires migration work) | 7 components | ~41% |

### Migration Effort Estimate (Engine Swap)

If migrating away from Komodo to another engine:

| Task | Effort | Impact |
|------|--------|--------|
| Compose files | **None** — already portable | All stacks continue working |
| Traefik config | **None** — already portable | Routing unaffected |
| Variables | **Low** — export to `.env` files | One-time export |
| Secrets | **Medium** — manual re-creation in new engine | Cannot be exported programmatically from Komodo |
| Deployment mappings | **Low** — re-create stack-to-server bindings | Trivial configuration |
| GitOps sync | **Medium** — replace TOML with new engine's format | Engine-specific glue |
| Monitoring | **Low** — deploy Prometheus/Grafana stack | Standard Compose stack |
| Periphery agents | **Medium** — uninstall agent, deploy new engine's agent | Ansible role swap |

**Bottom line**: A full engine migration is estimated at **2–4 days of work** for a small fleet, primarily due to secret re-creation and GitOps reconfiguration. The Compose files, Traefik config, and Ansible roles require zero changes.

---

## 6. AI Agent Interaction Model

### Overview

AI agents (such as GitHub Copilot, custom GPT agents, or CI/CD bots) can fully manage this infrastructure without using the Komodo UI. The architecture provides **three interaction planes** for automation:

### Interaction Planes

```
┌─────────────────────────────────────────────────────────────────────┐
│                     AI Agent Interaction Model                       │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │ PLANE 1: Git (Primary — recommended for most operations)   │    │
│  │                                                             │    │
│  │  • Edit Compose files in komodo/stacks/                    │    │
│  │  • Edit ResourceSync TOML in komodo/sync/                  │    │
│  │  • Edit Traefik route files                                │    │
│  │  • Edit Ansible roles and playbooks                        │    │
│  │  • Commit → CI validates → Merge → ResourceSync deploys   │    │
│  │                                                             │    │
│  │  Tools: Git CLI, GitHub API, file editing                  │    │
│  │  Auth: GitHub token (PAT or GitHub App)                    │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │ PLANE 2: Komodo API (For operations Git cannot perform)    │    │
│  │                                                             │    │
│  │  • Create / update / delete secrets                        │    │
│  │  • Trigger stack deployments                               │    │
│  │  • Run Procedures                                          │    │
│  │  • Query server health and container status                │    │
│  │  • Manage API keys                                         │    │
│  │                                                             │    │
│  │  Tools: HTTP client (curl, Python requests)                │    │
│  │  Auth: Komodo API key + secret                             │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │ PLANE 3: Docker Compose CLI (Direct, for emergency/debug)  │    │
│  │                                                             │    │
│  │  • SSH to server → docker compose up/down/logs             │    │
│  │  • Bypass Komodo entirely                                  │    │
│  │  • Compose files are portable — works standalone           │    │
│  │                                                             │    │
│  │  Tools: SSH, Docker Compose CLI                            │    │
│  │  Auth: SSH key (managed by github_ssh_keys role)           │    │
│  └─────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────┘
```

### Typical AI Agent Workflows

| Workflow | Plane | Steps |
|----------|-------|-------|
| Add a new application stack | Git | 1. Create `komodo/stacks/<app>/docker-compose.yml` 2. Add stack definition to `komodo/sync/stacks.toml` 3. Create Traefik route file 4. Add `.env.example` 5. Commit + PR |
| Update an image version | Git | 1. Edit image tag + SHA in Compose file 2. Commit + PR (or Renovate does this automatically) |
| Create a secret | API | 1. `POST /variable` with `is_secret: true` to Komodo API |
| Deploy a stack | API | 1. `POST /execute` with `DeployStack` action via Komodo API |
| Debug a failing container | CLI | 1. SSH to server 2. `docker compose logs <service>` |
| Modify Traefik routing | Git | 1. Edit route YAML in `komodo/stacks/traefik/config/dynamic/routers/` 2. Commit |
| Add a new server | Git + API | 1. Add to Ansible inventory (Git) 2. Add to `komodo/sync/servers.toml` (Git) 3. Register passkey via API |

### Key Takeaway

**You are not bounded to the Komodo UI.** The UI is one of many interfaces. The architecture is designed API-first and Git-first. AI agents interact primarily through Git (editing files, opening PRs) and secondarily through the Komodo REST API (for secrets and deployment triggers). The Compose files are standard Docker Compose that any agent or tool can read, write, and validate.

---

## 7. Hybrid Architecture Model

### Separation of Concerns

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        ANSIBLE (System Layer)                          │
│                                                                         │
│  ┌──────────────┐  ┌────────────┐  ┌─────────────┐  ┌──────────────┐  │
│  │ github_ssh   │  │ system     │  │ docker      │  │ ufw          │  │
│  │ _keys        │  │ _setup     │  │ _group +    │  │ (firewall)   │  │
│  │              │  │            │  │ geerlingguy │  │              │  │
│  │              │  │            │  │ .docker     │  │              │  │
│  └──────────────┘  └────────────┘  └─────────────┘  └──────────────┘  │
│                                                                         │
│  ┌──────────────┐  ┌────────────┐  ┌─────────────┐  ┌──────────────┐  │
│  │ package      │  │ chezmoi    │  │ komodo      │  │ maintenance  │  │
│  │ _managers    │  │ (dotfiles) │  │ (Periphery  │  │              │  │
│  │              │  │            │  │  install)   │  │              │  │
│  └──────────────┘  └────────────┘  └─────────────┘  └──────────────┘  │
│                                                                         │
│  ┌──────────────┐                                                       │
│  │ ansible_pull │                                                       │
│  │ _setup       │                                                       │
│  └──────────────┘                                                       │
└─────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────┐
│                     KOMODO (Application Layer)                         │
│                                                                         │
│  ┌──────────────┐  ┌────────────┐  ┌─────────────┐  ┌──────────────┐  │
│  │ Stacks       │  │ Secrets &  │  │ Monitoring  │  │ Procedures   │  │
│  │ (Compose)    │  │ Variables  │  │ & Alerts    │  │ (Automation) │  │
│  └──────────────┘  └────────────┘  └─────────────┘  └──────────────┘  │
│                                                                         │
│  ┌──────────────┐  ┌────────────┐                                      │
│  │ ResourceSync │  │ Webhooks   │                                      │
│  │ (GitOps)     │  │ (GitHub)   │                                      │
│  └──────────────┘  └────────────┘                                      │
└─────────────────────────────────────────────────────────────────────────┘
```

### What Ansible Manages (System Layer)

| Role | Purpose | Runs via |
|------|---------|----------|
| `github_ssh_keys` | Authorized SSH keys from GitHub | ansible-pull |
| `system_setup` | OS packages, timezone, locale, sysctl | ansible-pull |
| `docker_group` | Add users to Docker group | ansible-pull |
| `geerlingguy.docker` | Install Docker engine + daemon config | ansible-pull |
| `ufw` | Firewall rules | ansible-pull |
| `package_managers` | Homebrew and system packages | ansible-pull |
| `chezmoi` | Dotfiles management | ansible-pull |
| `bpbradley.komodo` | Install/update Komodo Periphery agent | ansible-pull |
| `ansible_pull_setup` | Systemd timer for ansible-pull | ansible-pull |
| `maintenance` | System maintenance timers | ansible-pull |

### What Komodo Manages (Application Layer)

| Resource | Purpose | Defined in |
|----------|---------|------------|
| Servers | Periphery connections | ResourceSync TOML |
| Stacks | Docker Compose applications | ResourceSync TOML + Compose files in repo |
| Variables | Non-sensitive configuration | ResourceSync TOML |
| Secrets | Sensitive values (API keys, passwords) | Komodo Core UI/API (never in Git) |
| Procedures | Automation workflows | ResourceSync TOML |

### What the `docker_compose_modules` Role Becomes

The existing `docker_compose_modules` Ansible role is **replaced entirely** by Komodo Stacks. The role directory can be removed once migration is complete. All Compose files move from Jinja2 templates to plain Docker Compose files in a new `komodo/stacks/` directory. These Compose files use Docker Compose-native `${VAR}` syntax (AP-1) and include `.env.example` files for standalone portability.

---

## 8. Komodo Core Deployment (Azure VM)

### Architecture

Komodo Core runs on a small Azure VM as a Docker Compose stack behind a reverse proxy. This VM is provisioned by Ansible (via a separate playbook or the same ansible-pull mechanism). Core communicates with on-premises Periphery agents exclusively over an encrypted overlay network (see [Section 11](#11-secure-connectivity)) — no direct port exposure to the internet for the Core API.

```
┌────────────────────────────────────────────────────┐
│  Azure VM (B2s — 2 vCPU, 4 GB RAM)                │
│  Debian 13 (Trixie)                                 │
│                                                     │
│  ┌───────────────────────────────────────────────┐  │
│  │  Reverse Proxy (TBD: Caddy/Traefik/Nginx)    │  │
│  │  Port 443 (public — GitHub webhooks + admin)  │  │
│  │       │                                       │  │
│  │       ▼ proxy_pass localhost:9120             │  │
│  │  ┌──────────────┐  ┌──────────────────────┐   │  │
│  │  │ komodo-core  │  │ MongoDB              │   │  │
│  │  │ (API + UI)   │  │ (database)           │   │  │
│  │  │ 127.0.0.1:   │  │                      │   │  │
│  │  │ 9120         │  │                      │   │  │
│  │  └──────────────┘  └──────────────────────┘   │  │
│  │                                               │  │
│  └───────────────────────────────────────────────┘  │
│                                                     │
│  Overlay network agent (outbound to on-prem mesh)   │
│  Ansible-managed: Docker, UFW, SSH keys, OS setup   │
└────────────────────────────────────────────────────┘
```

### VM Specification

| Property | Value | Rationale |
|----------|-------|-----------|
| Size | B2s (2 vCPU, 4 GB RAM) | Sufficient for Komodo Core + MongoDB for a small fleet |
| OS | Debian 13 (Trixie) | Stable, minimal, no Snap/telemetry. Matches on-prem servers (DD-23). |
| Disk | 32 GB Premium SSD | OS + Docker images + MongoDB data |
| Region | West Europe | Close to home network |
| Network | Public IP + NSG restricted | Only port 443 (reverse proxy) exposed. Core API on localhost only. |

### Why Docker on the Core VM

Yes — Docker should be installed on the Core VM. Komodo Core's standard deployment method is via Docker Compose with a database container. This is simpler and more maintainable than a bare-metal installation. Ansible provisions Docker on the VM (using `geerlingguy.docker`), and a dedicated Ansible playbook deploys the Core Compose stack.

### Core Compose File

```yaml
# komodo/core/docker-compose.yml
---
services:
  komodo-core:
    image: ghcr.io/moghtech/komodo-core:${KOMODO_VERSION}
    restart: unless-stopped
    depends_on:
      mongo:
        condition: service_healthy
    ports:
      - "127.0.0.1:9120:9120"          # Localhost only — reverse proxy fronts this
    environment:
      KOMODO_HOST: "https://komodo.${DOMAIN}"
      KOMODO_TITLE: "Komodo"
      KOMODO_PASSKEY_FILE: /run/secrets/passkey
      KOMODO_DATABASE_ADDRESS: mongo:27017
      KOMODO_LOCAL_AUTH: "true"
      KOMODO_INIT_ADMIN_USERNAME_FILE: /run/secrets/admin_username
      KOMODO_INIT_ADMIN_PASSWORD_FILE: /run/secrets/admin_password
      KOMODO_JWT_SECRET_FILE: /run/secrets/jwt_secret
      KOMODO_WEBHOOK_SECRET_FILE: /run/secrets/webhook_secret
      KOMODO_SYNC_DIRECTORY: /syncs
      KOMODO_REPO_DIRECTORY: /repo-cache
      KOMODO_MONITORING_INTERVAL: "15-sec"
      KOMODO_RESOURCE_POLL_INTERVAL: "5-min"
    volumes:
      - komodo-syncs:/syncs
      - komodo-repos:/repo-cache
    secrets:
      - passkey
      - admin_username
      - admin_password
      - jwt_secret
      - webhook_secret
    networks:
      - komodo-internal
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
    security_opt:
      - no-new-privileges:true

  mongo:
    image: docker.io/library/mongo:8.0@sha256:...
    restart: unless-stopped
    volumes:
      - komodo-db:/data/db
    networks:
      - komodo-internal
    healthcheck:
      test: ["CMD", "mongosh", "--eval", "db.adminCommand('ping')"]
      interval: 30s
      timeout: 10s
      retries: 3
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
    security_opt:
      - no-new-privileges:true

volumes:
  komodo-syncs:
  komodo-repos:
  komodo-db:

networks:
  komodo-internal:
    internal: true

secrets:
  passkey:
    file: ./secrets/passkey.txt
  admin_username:
    file: ./secrets/admin_username.txt
  admin_password:
    file: ./secrets/admin_password.txt
  jwt_secret:
    file: ./secrets/jwt_secret.txt
  webhook_secret:
    file: ./secrets/webhook_secret.txt
```

> **Note**: The Compose file uses Docker Compose-native `secrets:` (file-based) per AP-1. Variables use `${VAR}` syntax. The `.env` file provides `KOMODO_VERSION` and `DOMAIN`.

### Core Provisioning via Ansible

The Core VM is added to the Ansible inventory under a `komodo_core` group. Ansible provisions the VM's OS, Docker, firewall, and deploys the Core Compose stack.

```yaml
# ansible/inventory/hosts.yml (addition)
all:
  children:
    komodo_core:
      hosts:
        svlazkomodo1:
          ansible_host: <azure-vm-public-ip>
          ansible_user: ansible
          ansible_become: true
```

A dedicated playbook handles Core deployment:

```yaml
# ansible/playbooks/komodo-core.yml
---
- name: Provision Komodo Core
  hosts: komodo_core
  become: true

  roles:
    - role: github_ssh_keys
      tags: [ssh]

    - role: system_setup
      tags: [base]

    - role: geerlingguy.docker
      tags: [docker]

    - role: ufw
      tags: [firewall]

  tasks:
    - name: Create Komodo Core directory
      ansible.builtin.file:
        path: /opt/komodo-core
        state: directory
        mode: "0755"

    - name: Deploy Komodo Core compose file
      ansible.builtin.copy:
        src: "{{ playbook_dir }}/../../komodo/core/docker-compose.yml"
        dest: /opt/komodo-core/docker-compose.yml
        mode: "0644"

    - name: Create secrets directory
      ansible.builtin.file:
        path: /opt/komodo-core/secrets
        state: directory
        mode: "0700"

    - name: Deploy Komodo Core secrets
      ansible.builtin.copy:
        content: "{{ item.content }}"
        dest: "/opt/komodo-core/secrets/{{ item.name }}"
        mode: "0600"
      loop:
        - { name: passkey.txt, content: "{{ komodo_passkey }}" }
        - { name: admin_username.txt, content: "{{ komodo_admin_username }}" }
        - { name: admin_password.txt, content: "{{ komodo_admin_password }}" }
        - { name: jwt_secret.txt, content: "{{ komodo_jwt_secret }}" }
        - { name: webhook_secret.txt, content: "{{ komodo_webhook_secret }}" }
      no_log: true

    - name: Start Komodo Core
      community.docker.docker_compose_v2:
        project_src: /opt/komodo-core
        state: present
```

> **Note**: Core secrets are stored in Ansible Vault (not SOPS) since this is a single-host deployment. The vault password is provided at playbook runtime.

### Core Firewall Rules

| Port | Protocol | Source | Purpose |
|------|----------|--------|---------|
| 22 | TCP | Admin IPs / Overlay network | SSH access |
| 443 | TCP | GitHub webhook IPs + Admin IPs | Reverse proxy → Komodo Core API/UI |
| 9120 | TCP | `127.0.0.1` only | Komodo Core (reverse proxy backend — not externally accessible) |
| Overlay port | UDP | Overlay network peers | Encrypted overlay mesh (port depends on chosen solution — see [Section 11](#11-secure-connectivity)) |

Core port 9120 is **never directly exposed** to the internet. A reverse proxy (DD-25) terminates TLS on port 443 and forwards to `127.0.0.1:9120`. The Azure NSG restricts port 443 to GitHub webhook IP ranges and admin IPs.

---

## 9. Komodo Periphery Deployment (On-Premises)

### Installation via `bpbradley/ansible-role-komodo`

Periphery is installed on every Docker server using the `bpbradley.komodo` Ansible role. This role:

1. Creates an unprivileged `komodo` system user.
2. Downloads the Periphery binary.
3. Configures TLS (auto-generated certificates).
4. Sets up a systemd service (user scope by default — DD-14).
5. Optionally registers the server in Komodo Core via API.

### Ansible Integration

Add the role to `ansible/requirements.yml`:

```yaml
# ansible/requirements.yml (addition)
roles:
  - name: bpbradley.komodo
    version: "v1.3"
```

Add to the main playbook:

```yaml
# ansible/playbooks/main.yml (updated role list)
- role: bpbradley.komodo
  when: "'komodo_periphery' in server_features"
  tags: [komodo, periphery]
  vars:
    komodo_action: install
    komodo_version: core                    # match Core's version automatically
    komodo_service_scope: user              # least privilege (DD-14)
    komodo_ssl_enabled: true                # TLS between Core ↔ Periphery
    komodo_passkeys:
      - "{{ komodo_passkey }}"              # from Ansible Vault
    komodo_core_url: "https://komodo.{{ domain }}"
    komodo_core_api_key: "{{ komodo_api_key }}"
    komodo_core_api_secret: "{{ komodo_api_secret }}"
    enable_server_management: true          # auto-register in Core
    server_name: "{{ inventory_hostname }}"
```

### Host Variables

Each Docker server adds `komodo_periphery` to its `server_features`:

```yaml
# ansible/inventory/host_vars/svlazdock1.yml (updated)
---
server_features:
  - system_setup
  - github_ssh_keys
  - docker
  - ufw
  - package_managers
  - chezmoi
  - komodo_periphery                  # NEW — replaces docker_compose_modules
  - ansible_pull_setup
  - maintenance

# compose_modules is REMOVED — Komodo manages stacks now
```

### Periphery Security Configuration

| Setting | Value | Rationale |
|---------|-------|-----------|
| `komodo_service_scope` | `user` | Periphery runs as unprivileged `komodo` user with cgroup isolation |
| `komodo_ssl_enabled` | `true` | TLS encryption between Core and Periphery |
| `komodo_passkeys` | Vault-encrypted | Authentication token matching Core config |
| `komodo_allowed_ips` | Core VM IP (optional) | Restrict which IPs can reach Periphery (defense in depth) |
| `komodo_disable_terminals` | `false` | Allow remote terminal access via Komodo UI (useful for debugging) |
| `komodo_disable_container_exec` | `false` | Allow container exec via Komodo UI |

### Periphery Directories

The `bpbradley.komodo` role configures Periphery's working directories under the `komodo` user's home:

```
/home/komodo/
├── .config/
│   └── komodo/
│       └── periphery.config.toml       # Periphery configuration
├── .komodo/
│   ├── repos/                           # Git repo checkouts (for Stacks using repos)
│   ├── stacks/                          # Stack compose files (managed by Komodo)
│   ├── build/                           # Build artifacts
│   └── ssl/                             # Auto-generated TLS certificates
└── .config/
    └── systemd/
        └── user/
            └── periphery.service        # Systemd user unit
```

### UFW Rules for Periphery

Per AP-6 (Zero Inbound Ports), Periphery port 8120 is **not exposed to the internet or the home LAN**. Core reaches Periphery exclusively over the encrypted overlay network (see [Section 11](#11-secure-connectivity)). UFW rules restrict Periphery access to the overlay network's IP range:

```yaml
# UFW allows Core to reach Periphery only via overlay network
- port: 8120
  proto: tcp
  rule: allow
  from_ip: "{{ overlay_network_cidr }}"    # e.g., 100.64.0.0/10 for Tailscale
  comment: "Komodo Core → Periphery (overlay network only)"
```

No inbound ports are opened to the public internet on any on-premises server.

---

## 10. Server Classification & Trust Tiers

### Trust Tier Model (AP-5)

Servers are classified into **trust tiers** based on their network position and exposure level. This determines which stacks they may run, which secrets they receive, and what hardening policies apply.

| Tier | Network Position | Secret Scope | Hardening | Example Use Case |
|------|-----------------|--------------|-----------|------------------|
| **Trusted** | Internal VLAN, no public exposure | Full — all secrets available | Standard (DD-10 baseline) | Password managers, internal tools, databases |
| **Untrusted** | DMZ, public IP, or shared VLAN | Restricted — only secrets tagged for untrusted | Enhanced — terminals disabled, exec disabled, additional network restrictions | Public-facing web apps, external APIs, demo environments |

### Trust Tier Enforcement

Trust tiers are enforced via **Komodo server tags** and **Ansible host variables**:

```yaml
# ansible/inventory/host_vars/svlazdock1.yml
---
server_trust_tier: trusted
server_features:
  - system_setup
  - github_ssh_keys
  - docker
  - ufw
  - package_managers
  - chezmoi
  - komodo_periphery
  - ansible_pull_setup
  - maintenance
```

```yaml
# ansible/inventory/host_vars/future-dmz-server.yml
---
server_trust_tier: untrusted
server_features:
  - system_setup
  - github_ssh_keys
  - docker
  - ufw
  - komodo_periphery
  - ansible_pull_setup
  - maintenance

# Additional hardening for untrusted tier
komodo_disable_terminals: true
komodo_disable_container_exec: true
```

### Untrusted Tier — Additional Hardening

Servers classified as `untrusted` receive these additional controls beyond the DD-10 baseline:

| Control | Setting | Rationale |
|---------|---------|-----------|
| Remote terminals | `komodo_disable_terminals: true` | Prevents interactive shell access via Komodo UI |
| Container exec | `komodo_disable_container_exec: true` | Prevents `docker exec` via Komodo UI |
| Secret scoping | Only secrets tagged `scope:untrusted` or `scope:all` | Prevents leaking internal secrets to DMZ servers |
| Stack placement | Only stacks tagged `tier:untrusted` or `tier:any` | Prevents deploying sensitive stacks to exposed servers |
| Firewall | Stricter UFW — deny all inbound except overlay + required app ports | Minimal attack surface |
| Forward auth | Mandatory, no opt-out | All web UIs require authentication |

### Secret Scoping by Trust Tier

Komodo Variables and Secrets can be tagged to control which servers receive them:

```toml
# komodo/sync/variables.toml

[[variable]]
name = "DOMAIN"
value = "example.com"
description = "Base domain for all services"
# Available to all tiers (default)

[[variable]]
name = "INTERNAL_API_KEY"
value = "..."
description = "API key for internal services only"
tags = ["scope:trusted"]
# Only injected into stacks on trusted servers
```

### Inventory Structure

```yaml
# ansible/inventory/hosts.yml
---
all:
  children:
    # ── Komodo Core (Azure VM) ──
    komodo_core:
      hosts:
        svlazkomodo1:
          ansible_host: <azure-vm-overlay-ip>
          ansible_user: ansible
          ansible_become: true

    # ── Docker Servers (On-Premises, Periphery agents) ──
    docker_servers:
      children:
        trusted_servers:
          hosts:
            svlazdock1:
              ansible_host: 10.0.1.20
              ansible_user: ansible
              ansible_become: true

        untrusted_servers:
          hosts:
            # Future DMZ / public-facing servers go here
```

### Server Roles

| Group | Purpose | Trust Tier | Komodo Role | Example Stacks |
|-------|---------|------------|-------------|----------------|
| `komodo_core` | Komodo Core API/UI | N/A (Core itself) | N/A | Core + MongoDB |
| `trusted_servers` | Internal infrastructure + applications | Trusted | Periphery | Traefik, AdGuard, Vaultwarden, Portainer |
| `untrusted_servers` | DMZ / public-facing services | Untrusted | Periphery (hardened) | Public landing pages, external APIs |

### Ansible Playbook Updates

The main playbook uses `bpbradley.komodo` for Periphery deployment. Trust tier-specific hardening is applied via host variables:

```yaml
# ansible/playbooks/main.yml (updated)
---
- name: Provision and configure servers
  hosts: "{{ target_host | default('all') }}"
  become: true

  pre_tasks:
    - name: Update apt cache (Debian)
      ansible.builtin.apt:
        update_cache: true
        cache_valid_time: 3600
      when: ansible_os_family == "Debian"
      tags: always

  roles:
    - role: github_ssh_keys
      when: "'github_ssh_keys' in server_features"
      tags: [github_ssh_keys, ssh]

    - role: system_setup
      when: "'system_setup' in server_features"
      tags: [system_setup, base]

    - role: docker_group
      when: "'docker' in server_features"
      tags: [docker, docker_group]

    - role: geerlingguy.docker
      when: "'docker' in server_features"
      tags: docker

    - role: ufw
      when: "'ufw' in server_features or 'firewall' in server_features"
      tags: [ufw, firewall]

    - role: package_managers
      when: "'package_managers' in server_features"
      tags: [package_managers, homebrew]

    - role: chezmoi
      when: "'chezmoi' in server_features"
      tags: chezmoi

    # Komodo Periphery — replaces docker_compose_modules
    - role: bpbradley.komodo
      when: "'komodo_periphery' in server_features"
      tags: [komodo, periphery]

    - role: ansible_pull_setup
      when: "'ansible_pull_setup' in server_features"
      tags: [ansible_pull, automation]

    - role: maintenance
      when: "'maintenance' in server_features"
      tags: [maintenance, automation]
```

---

## 11. Secure Connectivity

### Problem

Komodo Core runs in Azure. Periphery agents run on-premises. The architecture requires Core to reach Periphery on port 8120. **Opening inbound ports on the home network is unacceptable** (AP-6).

### Solution: Encrypted Overlay Network

An encrypted overlay network creates a private mesh between the Azure VM and on-premises servers. All participants initiate **outbound** connections to form the mesh — no inbound ports are required on either side.

### Options Evaluated

| Solution | Type | NAT Traversal | Self-Hostable | Complexity | Cost |
|----------|------|--------------|---------------|------------|------|
| **Tailscale** | SaaS mesh VPN | ✅ Built-in | ✅ (Headscale) | Low | Free (personal) |
| **WireGuard** | Point-to-point VPN | ⚠️ Manual (needs one listener) | ✅ | Medium | Free |
| **Nebula** | Overlay mesh | ✅ Built-in | ✅ | Medium | Free |
| **Cloudflare Tunnel** | HTTP tunnel | ✅ Built-in | ❌ | Low | Free |
| **ZeroTier** | Mesh VPN | ✅ Built-in | ✅ | Low | Free (limited) |

### Recommendation

**Decision deferred** — the specific overlay solution is left as an open question (see [Section 27](#27-open-questions)). The architecture is designed to work with any of the above solutions. The key requirements are:

1. **No inbound ports** on on-premises servers (AP-6).
2. **Encrypted transport** between all mesh participants.
3. **Stable IP addresses** for Periphery agents (Komodo needs consistent addressing).
4. **ACL support** to restrict which nodes can communicate.
5. **Ansible-deployable** — the overlay agent must be installable via an Ansible role.

### Network Topology with Overlay

```
┌──────────────────────────┐         ┌──────────────────────────┐
│  Azure VM (Core)         │         │  On-Prem Server          │
│                          │         │  (Periphery)             │
│  Overlay IP: 100.x.x.1  │◄───────►│  Overlay IP: 100.x.x.2  │
│  Public IP: a.b.c.d     │  Mesh   │  LAN IP: 10.0.1.20      │
│                          │         │  Public IP: none         │
│  Core API: 127.0.0.1:   │         │  Periphery: 100.x.x.2:  │
│            9120          │         │             8120         │
│  Reverse Proxy: 443     │         │                          │
└──────────────────────────┘         └──────────────────────────┘
         │                                    │
         │ Outbound to coordination server    │ Outbound to coordination
         │ or direct peer connection          │ server or direct peer
         ▼                                    ▼
   ┌──────────────────────────────────────────────┐
   │  Overlay Coordination (SaaS or self-hosted)  │
   │  NAT traversal, key exchange, peer discovery │
   └──────────────────────────────────────────────┘
```

### Firewall Impact

With an overlay network in place, the firewall rules simplify dramatically:

**On-premises servers**:
- No inbound ports from the internet
- Periphery port 8120 accepts connections only from overlay network CIDR
- Outbound: overlay agent traffic (UDP, typically one port)

**Azure VM (Core)**:
- Inbound: port 443 (reverse proxy) from GitHub webhooks + admin IPs
- Inbound: overlay mesh port (UDP) from peers
- Core API (9120) bound to `127.0.0.1` — not externally accessible

### GitHub Webhooks

GitHub webhooks need to reach Komodo Core's `/webhook` endpoint. Since Core is behind a reverse proxy on port 443, the Azure NSG allows GitHub's webhook IP ranges to reach port 443. The reverse proxy forwards `/webhook` requests to `localhost:9120`. This is the **only** public-facing endpoint.

---

## 12. Stacks (Application Deployment)

### Concept

A Komodo **Stack** is a Docker Compose application deployed to a specific Server (Periphery). Stacks can use:

- **Compose files stored in this Git repository** (recommended — via ResourceSync).
- **Compose files from another Git repository**.
- **Inline Compose content** defined in the Komodo UI.

This architecture uses **repository-based Compose files** for GitOps traceability.

### Repository Layout

```
komodo/
├── core/
│   └── docker-compose.yml           # Core deployment (Azure VM)
├── stacks/
│   ├── traefik/
│   │   ├── docker-compose.yml        # Plain Compose (no Jinja2)
│   │   └── config/
│   │       ├── traefik.yml           # Static Traefik config
│   │       └── dynamic/
│   │           ├── middlewares.yml    # Middleware chain definitions
│   │           └── routers/          # Per-app file-based route configs
│   │               ├── adguard.yml
│   │               ├── vaultwarden.yml
│   │               └── ...
│   ├── forward-auth/
│   │   └── docker-compose.yml
│   ├── adguard/
│   │   ├── docker-compose.yml
│   │   └── config/
│   │       └── AdGuardHome.yaml
│   ├── vaultwarden/
│   │   └── docker-compose.yml
│   ├── portainer/
│   │   └── docker-compose.yml
│   ├── homepage/
│   │   └── docker-compose.yml
│   └── gatus/
│       ├── docker-compose.yml
│       └── config/
│           └── gatus.yml
└── sync/
    ├── servers.toml                  # Server definitions
    ├── stacks.toml                   # Stack definitions
    ├── variables.toml                # Non-sensitive variables
    └── procedures.toml               # Automation procedures
```

### Compose File Format

Compose files are **plain Docker Compose** — no Jinja2 templating, no engine-specific syntax (AP-1). Variables use Docker Compose-native `${VAR}` interpolation. Komodo injects these as environment variables at deployment time. For standalone use, a `.env` file provides the same values.

```yaml
# komodo/stacks/vaultwarden/docker-compose.yml
---
services:
  vaultwarden:
    image: docker.io/vaultwarden/server:1.32.7@sha256:abc123...
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    read_only: true
    tmpfs:
      - /tmp
    environment:
      - DOMAIN=https://vault.${DOMAIN}
      - SIGNUPS_ALLOWED=false
      - ADMIN_TOKEN=${VAULTWARDEN_ADMIN_TOKEN}
    volumes:
      - vaultwarden-data:/data
    networks:
      - vaultwarden-frontend
      - vaultwarden-backend
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"

volumes:
  vaultwarden-data:

networks:
  vaultwarden-frontend:
    driver: bridge
  vaultwarden-backend:
    internal: true
```

Each stack includes a `.env.example` file documenting required variables:

```bash
# komodo/stacks/vaultwarden/.env.example
# Required variables for standalone deployment (docker compose up)
DOMAIN=example.com
VAULTWARDEN_ADMIN_TOKEN=changeme
```

### Variable Interpolation

Per AP-1 (Compose-First Portability), variables use Docker Compose-native `${VAR}` syntax:

- **Variables** (non-sensitive): Defined in ResourceSync TOML and stored in Git. Komodo exports them as environment variables before `docker compose up`.
- **Secrets** (sensitive): Created via Komodo UI/API, stored encrypted in Core's database. Komodo exports them as environment variables before `docker compose up`. Never stored in Git.

```yaml
# In a Compose file (standard Docker Compose syntax):
environment:
  - DOMAIN=https://app.${DOMAIN}           # ${DOMAIN} → Komodo Variable or .env
  - API_KEY=${APP_API_KEY}                  # ${APP_API_KEY} → Komodo Secret or .env
```

> **When to use `[[VAR]]` (Komodo-specific)**: Only when the value must be interpolated *into the Compose YAML structure itself* (not as an environment variable) — for example, in volume paths, network names, or image tags that vary per deployment. This should be rare. Document every usage with a comment explaining why `${VAR}` was insufficient.

### Stack-to-Server Binding

Each Stack is bound to a specific Server in its ResourceSync definition. A Stack cannot deploy to multiple servers simultaneously — create separate Stack resources if needed.

---

## 13. ResourceSync (GitOps)

### Concept

Komodo **ResourceSync** pulls resource definitions (TOML files) from a Git repository and applies them to Core. This is the GitOps control plane — changes to TOML files in this repo automatically update Komodo's configuration.

### Sync Configuration

A single ResourceSync resource connects this Git repo to Komodo Core:

```toml
# This is bootstrapped manually in Komodo UI, pointing to the komodo/sync/ directory.
# After initial setup, all further configuration is managed via the TOML files.
```

### Server Definitions

```toml
# komodo/sync/servers.toml

## ── Trusted Servers ──

[[server]]
name = "svlazdock1"
description = "Production application server (trusted VLAN)"
tags = ["production", "trusted"]

## ── Untrusted Servers ──
# Future DMZ / public-facing servers go here with tag "untrusted"

# Note: Server addresses and passkeys are configured by the
# bpbradley.komodo Ansible role's server management feature.
# These definitions create the server resources; the role
# updates connection details via the API.
```

### Stack Definitions

```toml
# komodo/sync/stacks.toml

## ── Infrastructure Stacks ──

[[stack]]
name = "traefik"
description = "Reverse proxy and TLS termination"
server = "svlazdock1"
run_directory = "/home/komodo/.komodo/stacks/traefik"
file_paths = ["komodo/stacks/traefik/docker-compose.yml"]
git_account = "DevSecNinja"
repo = "DevSecNinja/docker"
branch = "main"
tags = ["infrastructure"]
# Deploy traefik first — other stacks depend on it
# No 'after' needed since this is the first stack

[[stack]]
name = "forward-auth"
description = "Traefik forward authentication"
server = "svlazdock1"
run_directory = "/home/komodo/.komodo/stacks/forward-auth"
file_paths = ["komodo/stacks/forward-auth/docker-compose.yml"]
git_account = "DevSecNinja"
repo = "DevSecNinja/docker"
branch = "main"
tags = ["infrastructure", "auth"]
# Deploy after traefik
[stack.config]
after = ["traefik"]

[[stack]]
name = "adguard"
description = "DNS filtering and ad blocking"
server = "svlazdock1"
run_directory = "/home/komodo/.komodo/stacks/adguard"
file_paths = ["komodo/stacks/adguard/docker-compose.yml"]
git_account = "DevSecNinja"
repo = "DevSecNinja/docker"
branch = "main"
tags = ["infrastructure", "dns"]
[stack.config]
after = ["traefik"]

## ── Application Stacks ──

[[stack]]
name = "vaultwarden"
description = "Password manager"
server = "svlazdock1"
run_directory = "/home/komodo/.komodo/stacks/vaultwarden"
file_paths = ["komodo/stacks/vaultwarden/docker-compose.yml"]
git_account = "DevSecNinja"
repo = "DevSecNinja/docker"
branch = "main"
tags = ["application"]
[stack.config]
after = ["traefik", "forward-auth"]

[[stack]]
name = "portainer"
description = "Container management UI"
server = "svlazdock1"
run_directory = "/home/komodo/.komodo/stacks/portainer"
file_paths = ["komodo/stacks/portainer/docker-compose.yml"]
git_account = "DevSecNinja"
repo = "DevSecNinja/docker"
branch = "main"
tags = ["application"]
[stack.config]
after = ["traefik", "forward-auth"]
```

### Variable Definitions

```toml
# komodo/sync/variables.toml
# Non-sensitive variables — safe to commit to Git

[[variable]]
name = "DOMAIN"
value = "example.com"
description = "Base domain for all services"

[[variable]]
name = "ACME_EMAIL"
value = "admin@example.com"
description = "Email for Let's Encrypt certificate registration"

[[variable]]
name = "COMPOSE_MODULES_BASE_DIR"
value = "/home/komodo/.komodo/stacks"
description = "Base directory for stack files on Periphery"

[[variable]]
name = "TIMEZONE"
value = "Europe/Amsterdam"
description = "Default timezone for containers"
```

### Procedure Definitions

```toml
# komodo/sync/procedures.toml

[[procedure]]
name = "deploy-all-infrastructure"
description = "Deploy all infrastructure stacks in order"
tags = ["infrastructure", "deploy"]

[[procedure.config.stage]]
name = "Deploy Traefik"
executions = [
  { execution.type = "DeployStack", execution.stack = "traefik" }
]

[[procedure.config.stage]]
name = "Deploy Auth & DNS"
executions = [
  { execution.type = "DeployStack", execution.stack = "forward-auth" },
  { execution.type = "DeployStack", execution.stack = "adguard" }
]

[[procedure.config.stage]]
name = "Deploy Applications"
executions = [
  { execution.type = "DeployStack", execution.stack = "vaultwarden" },
  { execution.type = "DeployStack", execution.stack = "portainer" }
]
```

### Sync Lifecycle

```
Git push to main
       │
       ▼
GitHub Webhook → Komodo Core
       │
       ▼
ResourceSync pulls latest TOML files
       │
       ▼
Core diffs current state vs. desired state
       │
       ▼
Creates / updates / deletes resources as needed
       │
       ▼
Stack deploys triggered (if auto-deploy enabled)
```

### Important: What ResourceSync Does NOT Do

- **Does not store secrets**: Secrets must be created via Komodo UI or API. ResourceSync TOML can reference secret names but not their values.
- **Does not auto-deploy stacks by default**: ResourceSync creates/updates Stack definitions. Actual deployment (docker compose up) is triggered separately — either manually, via webhook, or via `auto_deploy` configuration.
- **Does not manage Periphery installation**: That's Ansible's job via `bpbradley.komodo`.

---

## 14. Secret Management

### Architecture

Secrets are managed through Komodo Core's built-in variable/secret system. This replaces the SOPS + Age pipeline from the previous architecture. Per AP-1, secrets are injected as **environment variables** using Docker Compose-native `${VAR}` syntax — not Komodo-specific `[[VAR]]` interpolation.

```
┌─────────────────────────────────────────────────────────┐
│                    Secret Flow                           │
│                                                          │
│  Admin / AI Agent                                        │
│       │                                                  │
│       ▼                                                  │
│  Komodo API (POST /variable)                             │
│       │                                                  │
│       ▼                                                  │
│  Core Database (encrypted at rest on Azure disk)         │
│       │                                                  │
│       ▼                                                  │
│  Stack deployment: ${SECRET_NAME} → actual value          │
│       │                                                  │
│       ▼                                                  │
│  Periphery receives interpolated Compose                 │
│  → docker compose up                                     │
└─────────────────────────────────────────────────────────┘
```

### Secret Types

| Type | Visibility | Storage | Example |
|------|-----------|---------|---------|
| **Variable** | Visible in UI, stored in Git (TOML) | ResourceSync + Core DB | `DOMAIN`, `TIMEZONE` |
| **Secret** | Hidden in UI/logs, never in Git | Core DB only | `VAULTWARDEN_ADMIN_TOKEN`, `CF_API_TOKEN` |

### Creating Secrets

Secrets are created through:

1. **Komodo UI**: Settings → Variables → Add Secret.
2. **Komodo API**: `POST /variable` with `is_secret: true`.
3. **AI Agents**: Via the Komodo REST API using an API key.

```bash
# Example: Create a secret via API
curl -X POST https://komodo.example.com/api/variable \
  -H "Authorization: Bearer <api-key>:<api-secret>" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "VAULTWARDEN_ADMIN_TOKEN",
    "value": "supersecrettoken",
    "is_secret": true,
    "description": "Admin token for Vaultwarden"
  }'
```

### Periphery-Specific Secrets

Some secrets are specific to a Periphery agent (e.g., a server-specific API key). These can be defined via the `bpbradley.komodo` role:

```yaml
# In host_vars
komodo_agent_secrets:
  - name: "LOCAL_SECRET"
    value: "{{ vault_local_secret }}"
```

These secrets are available only on that specific Periphery and are referenced as `${LOCAL_SECRET}` in Compose files.

### Comparison with Previous Architecture

| Aspect | SOPS + Age (old) | Komodo Secrets (new) |
|--------|-----------------|---------------------|
| Storage | Encrypted in Git | Komodo Core database |
| Visibility | Encrypted values visible in Git diffs | Hidden in UI and logs |
| Key management | Age key pairs per host/group | Komodo handles internally |
| AI agent access | Encrypt with public keys, commit | API call to create/update |
| Audit trail | Git history | Komodo audit log |
| Offline access | Yes (keys on host) | No (requires Core) |
| Complexity | High (key distribution, SOPS config) | Low (API calls) |

---

## 15. Network Isolation

### Model

The network isolation model is carried forward from the previous architecture but simplified by removing the requirement for Traefik to join every frontend network.

```
┌─────────────────────────────────────────────────────────────────────┐
│ Host (Periphery)                                                    │
│                                                                     │
│  ┌─────────┐                                                        │
│  │ Traefik │                                                        │
│  │         │  Traefik does NOT join per-app networks.               │
│  │         │  Instead, it routes via file-based config              │
│  │         │  using container IPs or Docker DNS.                    │
│  └────┬────┘                                                        │
│       │                                                             │
│       │ (file-based routing to container IPs)                       │
│       │                                                             │
│  ┌────▼──────────────────────┐  ┌──────────────────────────────┐    │
│  │ app1-frontend network     │  │ app2-frontend network         │   │
│  │  ┌─────────┐              │  │  ┌─────────┐                  │   │
│  │  │ app1-web│              │  │  │ app2-web │                  │   │
│  │  └────┬────┘              │  │  └─────┬───┘                  │   │
│  │       │                   │  │        │                       │   │
│  │  ┌────▼──────────────┐    │  │  ┌─────▼──────────────┐       │   │
│  │  │ app1-backend net  │    │  │  │ app2-backend net    │       │   │
│  │  │  ┌──────────┐     │    │  │  │  ┌────────────┐    │       │   │
│  │  │  │ app1-db  │     │    │  │  │  │ app2-redis │    │       │   │
│  │  │  └──────────┘     │    │  │  │  └────────────┘    │       │   │
│  │  └───────────────────┘    │  │  └────────────────────┘       │   │
│  └───────────────────────────┘  └───────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

### Key Difference from Previous Architecture

In the old architecture (DD-9), Traefik had to **join every app's frontend network** via a dynamically-rendered Compose file with Jinja2 loops. This created tight coupling and required all module variables to be pre-loaded.

In the Komodo architecture, Traefik uses **file-based routing** (DD-7). Traefik's dynamic configuration files specify backend URLs using container IPs or Docker's internal DNS. Traefik does not need to be on the same Docker network as the applications it routes to.

### Network Rules

1. Each stack creates its own `<app>-frontend` bridge network.
2. Stacks with databases/caches add an `<app>-backend` network with `internal: true`.
3. Backend networks block internet access (no egress).
4. Frontend networks allow egress (for API calls, updates, etc.).
5. Traefik routes to apps via file-based configuration, not Docker network membership.

### Docker Network Address Pools (DD-12)

```yaml
# Configured via geerlingguy.docker in Ansible
docker_daemon_options:
  default-address-pools:
    - base: "172.17.0.0/12"
      size: 20
```

This provides ~256 /20 subnets, avoiding `192.168.x.x` LAN conflicts.

---

## 16. Traefik Integration

### File-Based Routing (DD-7)

Traefik uses **file-based dynamic configuration** instead of Docker label discovery for application routing. This decouples Traefik from needing to join every app's Docker network.

### Traefik Stack

```yaml
# komodo/stacks/traefik/docker-compose.yml
---
services:
  socket-proxy:
    image: docker.io/tecnativa/docker-socket-proxy:0.3.0@sha256:...
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    read_only: true
    environment:
      - CONTAINERS=1
      - NETWORKS=1
      - SERVICES=1
      - POST=0
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
    image: docker.io/library/traefik:v3.3.3@sha256:...
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    read_only: true
    depends_on:
      - socket-proxy
    ports:
      - "80:80"
      - "443:443"
    environment:
      - CF_API_EMAIL=${ACME_EMAIL}
      - CF_DNS_API_TOKEN=${CF_API_TOKEN}
    volumes:
      - ./config/traefik.yml:/traefik.yml:ro
      - ./config/dynamic:/etc/traefik/dynamic:ro
      - traefik-certs:/letsencrypt
    networks:
      - traefik-socket
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"

volumes:
  traefik-certs:

networks:
  traefik-socket:
    internal: true
```

### Static Configuration

```yaml
# komodo/stacks/traefik/config/traefik.yml
---
api:
  dashboard: true
  insecure: false

entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
  websecure:
    address: ":443"

providers:
  file:
    directory: /etc/traefik/dynamic
    watch: true

certificatesResolvers:
  letsencrypt:
    acme:
      email: "admin@example.com"
      storage: /letsencrypt/acme.json
      dnsChallenge:
        provider: cloudflare
        resolvers:
          - "1.1.1.1:53"
          - "1.0.0.1:53"
```

### File-Based Route Configuration

Each application gets a route file in `config/dynamic/routers/`:

```yaml
# komodo/stacks/traefik/config/dynamic/routers/vaultwarden.yml
---
http:
  routers:
    vaultwarden:
      rule: "Host(`vault.example.com`)"
      entryPoints:
        - websecure
      service: vaultwarden
      tls:
        certResolver: letsencrypt
      middlewares:
        - secure-headers@file
        - forward-auth@file

  services:
    vaultwarden:
      loadBalancer:
        servers:
          - url: "http://host.docker.internal:8080"
          # Or use the container's IP on its frontend network
```

> **Important**: Since Traefik does not join per-app networks, it needs another way to reach app containers. Options:
>
> 1. **Expose app ports on the host** (e.g., `127.0.0.1:8080:80`) and route via `host.docker.internal` or `172.17.0.1`.
> 2. **Use a shared `traefik-routing` network** that Traefik and the app's web-facing container both join (simpler than per-app networks for Traefik).
> 3. **Use Docker Socket Proxy** for service discovery — Traefik discovers services via Docker labels but doesn't need network membership (Traefik supports routing via the Docker provider even without shared networks when using `host` networking or exposed ports).
>
> **Recommended approach**: Option 2 — a single shared `traefik-routing` network for Traefik → application web containers. Per-app backend networks remain isolated. This is simpler than per-app frontend networks while maintaining backend isolation. See [Open Questions](#23-open-questions) for further discussion.

### Middleware Definitions

```yaml
# komodo/stacks/traefik/config/dynamic/middlewares.yml
---
http:
  middlewares:
    redirect-to-https:
      redirectScheme:
        scheme: "https"
        permanent: true

    rate-limit:
      rateLimit:
        average: 200
        burst: 100

    secure-headers:
      headers:
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
        customResponseHeaders:
          X-Robots-Tag: "none,noarchive,nosnippet,notranslate,noimageindex"
          server: ""

    forward-auth:
      forwardAuth:
        address: "http://forward-auth:4181"
        trustForwardHeader: true

    health-bypass:
      chain:
        middlewares:
          - rate-limit-health
          - whitelist-localnetwork

    rate-limit-health:
      rateLimit:
        average: 10
        burst: 5

    whitelist-localnetwork:
      ipAllowList:
        sourceRange:
          - "192.168.0.0/16"
          - "10.0.0.0/8"
          - "172.16.0.0/12"
```

---

## 17. Traefik Forward Auth

### Overview

Forward auth protects all web-facing stacks by default (DD-11). The `forward-auth` stack deploys `traefik-forward-auth` which integrates with Traefik as a middleware.

### Forward Auth Stack

```yaml
# komodo/stacks/forward-auth/docker-compose.yml
---
services:
  forward-auth:
    image: ghcr.io/italypaleale/traefik-forward-auth:v3.1.0@sha256:...
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    read_only: true
    environment:
      - CLIENT_ID=${FORWARD_AUTH_CLIENT_ID}
      - CLIENT_SECRET=${FORWARD_AUTH_CLIENT_SECRET}
      - SECRET=${FORWARD_AUTH_SECRET}
    networks:
      - traefik-routing
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"

networks:
  traefik-routing:
    external: true
```

### Policy

- **Default-on**: Every web-facing stack's Traefik route includes the `forward-auth@file` middleware.
- **Opt-out**: Stacks that handle their own authentication omit `forward-auth` from their route file with a comment explaining why.
- **Health bypass**: Stacks with health endpoints use the `health-bypass@file` middleware chain for unauthenticated health checks from local networks only.

---

## 18. Container Hardening Standards

These standards are carried forward from the previous architecture and apply to **all** Compose files in `komodo/stacks/`.

### Mandatory Settings (Every Service)

```yaml
services:
  example:
    image: docker.io/org/app:v1.0.0@sha256:...      # Registry + version + SHA
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true                        # Prevent privilege escalation
    cap_drop:
      - ALL                                           # Drop all Linux capabilities
    # cap_add:                                        # Add back only what's needed
    #   - NET_BIND_SERVICE
    read_only: true                                   # Read-only root filesystem
    # tmpfs:                                          # Writable dirs via tmpfs
    #   - /tmp
    #   - /run
    logging:
      driver: json-file
      options:
        max-size: "10m"                               # 10 MB per log file
        max-file: "3"                                 # 3 rotated files max
```

### Enforcement

| Rule | Requirement | Rationale |
|------|-------------|-----------|
| Registry prefix | `docker.io/`, `ghcr.io/`, `quay.io/`, etc. | Explicit source; prevents supply-chain confusion |
| SHA256 digest | `@sha256:...` after tag | Deterministic; prevents tag mutation attacks |
| `no-new-privileges` | Required on every service | Prevents privilege escalation |
| `cap_drop: [ALL]` | Required on every service | Least privilege; add back specific caps with justification |
| `read_only: true` | Default; opt out with documented reason | Prevents in-container persistence |
| `logging` limits | `max-size: 10m`, `max-file: 3` | Prevents disk exhaustion |
| `restart: unless-stopped` | Required on every service | Survives reboots |
| No `privileged: true` | Forbidden unless explicitly justified | Minimizes blast radius |
| No `ports:` exposure | Only Traefik (80/443) and essential services (DNS 53) | All traffic through Traefik |

### CI Validation

Bats tests validate all Compose files in `komodo/stacks/` against these rules:

```bash
# tests/bash/compose-hardening-test.bats
@test "all compose files enforce security_opt no-new-privileges" {
  for compose_file in komodo/stacks/*/docker-compose.yml; do
    stack_name=$(basename "$(dirname "$compose_file")")
    grep -q "no-new-privileges" "$compose_file" || \
      fail "Stack $stack_name missing security_opt no-new-privileges"
  done
}

@test "all compose files enforce cap_drop ALL" {
  for compose_file in komodo/stacks/*/docker-compose.yml; do
    stack_name=$(basename "$(dirname "$compose_file")")
    grep -q "cap_drop" "$compose_file" || \
      fail "Stack $stack_name missing cap_drop"
  done
}

@test "all compose files enforce logging limits" {
  for compose_file in komodo/stacks/*/docker-compose.yml; do
    stack_name=$(basename "$(dirname "$compose_file")")
    grep -q "max-size" "$compose_file" || \
      fail "Stack $stack_name missing logging max-size"
  done
}

@test "all images include registry prefix and SHA digest" {
  for compose_file in komodo/stacks/*/docker-compose.yml; do
    stack_name=$(basename "$(dirname "$compose_file")")
    # Check that every image: line has a registry prefix
    images=$(grep -E "^\s+image:" "$compose_file" | sed 's/.*image:\s*//' || true)
    for img in $images; do
      # Skip interpolated images (contain [[)
      echo "$img" | grep -q '\[\[' && continue
      echo "$img" | grep -qE "^(docker\.io|ghcr\.io|quay\.io|mcr\.microsoft\.com)" || \
        fail "Stack $stack_name image $img missing registry prefix"
      echo "$img" | grep -q "@sha256:" || \
        fail "Stack $stack_name image $img missing SHA256 digest"
    done
  done
}
```

---

## 19. Image Pinning & Renovate

### Format

All Docker images in Compose files are pinned with **registry + version + SHA digest**:

```yaml
image: docker.io/vaultwarden/server:1.32.7@sha256:abc123...
```

### Renovate Configuration

Renovate watches `komodo/stacks/*/docker-compose.yml` for image references:

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "customManagers": [
    {
      "customType": "regex",
      "fileMatch": ["komodo/stacks/.+/docker-compose\\.yml$"],
      "matchStrings": [
        "image:\\s*[\"']?(?<depName>[^:@\"'\\s]+):(?<currentValue>[^@\"'\\s]+)(?:@(?<currentDigest>sha256:[a-f0-9]+))?[\"']?"
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

### Renovate → Komodo Deployment Flow

```
Renovate detects new image version
       │
       ▼
Opens PR with updated Compose file (version + digest)
       │
       ▼
CI validates (yamllint, Bats tests, compose validation)
       │
       ▼
PR merged to main
       │
       ▼
GitHub webhook → Komodo ResourceSync
       │
       ▼
Stack auto-redeploys with new image (if auto_deploy enabled)
```

---

## 20. DNS Management

### Architecture

DNS management is simplified compared to the previous architecture. Instead of auto-generating Unbound zone files from module vars via Jinja2 templates, DNS records are managed through:

1. **AdGuard Home** for DNS filtering and local DNS overrides (UI-based).
2. **Unbound** as recursive resolver behind AdGuard.
3. Optional: A **Komodo Procedure** that uses the AdGuard API to sync DNS records.

### AdGuard + Unbound Stack

```yaml
# komodo/stacks/adguard/docker-compose.yml
---
services:
  adguard:
    image: docker.io/adguard/adguardhome:v0.107.52@sha256:...
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    cap_add:
      - NET_BIND_SERVICE
    ports:
      - "53:53/udp"
      - "53:53/tcp"
    volumes:
      - adguard-data:/opt/adguardhome/work
      - ./config:/opt/adguardhome/conf
    networks:
      - adguard-frontend
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"

volumes:
  adguard-data:

networks:
  adguard-frontend:
    driver: bridge
```

### DNS Record Management

Unlike the previous architecture's automated Unbound zone generation, DNS records for internal services are managed through **AdGuard Home's DNS rewrites** feature (UI or API). This is simpler and more operationally visible.

For automation, a Komodo Procedure can call the AdGuard API to create/update DNS rewrites when stacks are deployed.

---

## 21. Monitoring & Healthchecks

### Komodo Built-In Monitoring

Komodo Core provides built-in monitoring for all registered Servers and their containers:

- **Server health**: CPU, memory, disk usage.
- **Container status**: Running, stopped, restarting.
- **Alerts**: Configurable alert destinations (Discord, Slack, email).
- **Stats history**: Stored in Core DB with configurable retention.

### Optional Gatus Stack

For end-to-end HTTP healthchecks (validating the full Traefik → app → response chain), deploy Gatus as a Stack:

```yaml
# komodo/stacks/gatus/docker-compose.yml
---
services:
  gatus:
    image: docker.io/twinproduction/gatus:v5.17.0@sha256:...
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    read_only: true
    volumes:
      - ./config:/config:ro
    networks:
      - gatus-frontend
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"

networks:
  gatus-frontend:
    driver: bridge
```

Gatus configuration is a plain YAML file (not auto-generated). New endpoints are added manually when stacks are deployed:

```yaml
# komodo/stacks/gatus/config/gatus.yml
---
endpoints:
  - name: "Vaultwarden"
    group: "Applications"
    url: "https://vault.example.com/alive"
    interval: 5m
    conditions:
      - "[STATUS] == 200"
      - "[RESPONSE_TIME] < 1000"
      - "[CERTIFICATE_EXPIRATION] > 48h"

  - name: "AdGuard Home"
    group: "Infrastructure"
    url: "https://adguard.example.com"
    interval: 5m
    conditions:
      - "[STATUS] == 200"

  - name: "Komodo Core"
    group: "Infrastructure"
    url: "https://komodo.example.com"
    interval: 5m
    conditions:
      - "[STATUS] == 200"
```

---

## 22. TLS Certificate Strategy

### Certificate Authority

All TLS certificates are issued by **Let's Encrypt** via Traefik's built-in ACME client.

### Challenge Type: DNS-01 via Cloudflare (DD-13)

- DNS-01 challenges avoid inbound port 80 requirements.
- Supports wildcard certificates.
- Works for internal-only services.

### Required Secrets (in Komodo)

| Secret Name | Purpose |
|-------------|---------|
| `CF_API_TOKEN` | Cloudflare DNS API token for DNS-01 challenges |

### Certificate Storage

Certificates persist in the `traefik-certs` Docker volume. This survives container restarts and avoids rate-limit issues with Let's Encrypt.

---

## 23. Backup Strategy

> **Status**: Should have (Phase 3)

### Planned Architecture

| Component | Tool | Destination |
|-----------|------|-------------|
| Docker volumes | `offen/docker-volume-backup` | Azure Blob Storage |
| Database dumps | `tiredofit/docker-db-backup` | Azure Blob Storage |
| Komodo Core DB | `mongodump` via `tiredofit/docker-db-backup` (explicit MongoDB support) | Azure Blob Storage |

### Komodo Core Backup

The Core VM database (MongoDB) is backed up via `tiredofit/docker-db-backup`, which has **native `mongodump`/`mongorestore` support** (DD-16). This provides consistent, point-in-time backups without filesystem-level locking concerns. Komodo also provides a built-in "Backup Core Database" procedure created at initialization.

---

## 24. Testing Strategy

### Test Categories

| Category | Framework | When | What |
|----------|-----------|------|------|
| Linting | yamllint, ansible-lint | CI | YAML syntax, Ansible best practices |
| Syntax | ansible-playbook --syntax-check | CI | Playbook validity |
| Compose validation | Bats + docker compose config | CI | All `komodo/stacks/*/docker-compose.yml` are valid |
| Container hardening | Bats | CI | Registry prefix, SHA, security_opt, cap_drop, logging |
| ResourceSync TOML | Bats | CI | TOML files are syntactically valid |
| Role structure | Bats | CI | All roles have required files |
| Integration | Bats + Docker | CI (with Docker) | Full deploy cycle on test host |

### Test Files

```
tests/
└── bash/
    ├── lint-test.bats                 # Existing — yamllint, ansible-lint
    ├── syntax-test.bats               # Existing — playbook syntax
    ├── docker-test.bats               # Existing — Docker provisioning
    ├── ansible-pull-test.bats         # Existing — ansible-pull script
    ├── github-ssh-keys-test.bats      # Existing — SSH keys role
    ├── roles-test.bats                # Existing — role structure
    ├── compose-hardening-test.bats    # NEW — container hardening checks
    ├── resourcesync-test.bats         # NEW — TOML file validation
    └── run-tests.sh                   # Test runner
```

### Compose Validation in CI

Since Compose files are now plain Docker Compose (no Jinja2), validation is straightforward:

```bash
# tests/bash/compose-hardening-test.bats
@test "all compose files pass docker compose config" {
  for compose_file in komodo/stacks/*/docker-compose.yml; do
    stack_name=$(basename "$(dirname "$compose_file")")

    # Replace [[VARIABLE]] placeholders with dummy values for validation
    tmpfile=$(mktemp /tmp/compose-XXXXXX.yml)
    sed 's/\[\[.*\]\]/dummy-value/g' "$compose_file" > "$tmpfile"

    docker compose -f "$tmpfile" config --quiet || \
      fail "Stack $stack_name compose file fails validation"

    rm -f "$tmpfile"
  done
}
```

---

## 25. Implementation Order

### Phase 1 — Secure Connectivity & Core Setup

> **Focus**: Establish the encrypted overlay network and get Komodo Core running on Azure with MongoDB behind a reverse proxy.

| Task | Description | Priority | Depends on |
|------|-------------|----------|------------|
| 1.1 | Choose and deploy encrypted overlay network solution (see [Section 11](#11-secure-connectivity)) | Must | — |
| 1.2 | Provision Azure VM (B2s, Debian 13 Trixie) | Must | — |
| 1.3 | Install overlay agent on Azure VM and on-premises servers | Must | 1.1, 1.2 |
| 1.4 | Add `svlazkomodo1` to Ansible inventory under `komodo_core` group | Must | 1.2 |
| 1.5 | Create `ansible/playbooks/komodo-core.yml` playbook | Must | 1.4 |
| 1.6 | Create `komodo/core/docker-compose.yml` with Core + MongoDB | Must | 1.2 |
| 1.7 | Deploy reverse proxy on Core VM (TBD: Caddy/Traefik/Nginx) | Must | 1.6 |
| 1.8 | Run core playbook to deploy Core | Must | 1.5, 1.6, 1.7 |
| 1.9 | Configure Core authentication (local auth initially) | Must | 1.8 |
| 1.10 | Create initial API key in Core for Ansible integration | Must | 1.9 |
| 1.11 | Configure UFW on Core VM (SSH + 443 + overlay) | Must | 1.8 |

### Phase 2 — Periphery Deployment

> **Focus**: Install Periphery agents on Docker servers via Ansible. Establish Core ↔ Periphery connectivity over the overlay network.

| Task | Description | Priority | Depends on |
|------|-------------|----------|------------|
| 2.1 | Add `bpbradley.komodo` to `ansible/requirements.yml` | Must | Phase 1 |
| 2.2 | Update host_vars: replace `compose_modules` with `komodo_periphery` in `server_features`, set `server_trust_tier` | Must | 2.1 |
| 2.3 | Update `ansible/playbooks/main.yml` to include `bpbradley.komodo` role | Must | 2.1 |
| 2.4 | Configure Periphery variables (passkey, Core overlay URL, API key) in Ansible Vault | Must | 2.1 |
| 2.5 | Run ansible-pull on all Docker servers to install Periphery | Must | 2.3, 2.4 |
| 2.6 | Verify all servers appear in Komodo Core UI with correct trust tier tags | Must | 2.5 |
| 2.7 | Configure UFW to allow Core → Periphery on port 8120 (overlay network CIDR only) | Must | 2.5 |

### Phase 3 — Traefik & Infrastructure Stacks

> **Focus**: Deploy Traefik, forward auth, and DNS stacks. Establish the networking and routing layer.

| Task | Description | Priority | Depends on |
|------|-------------|----------|------------|
| 3.1 | Create `komodo/stacks/traefik/` with Compose + config files + `.env.example` | Must | Phase 2 |
| 3.2 | Create `komodo/stacks/forward-auth/` + `.env.example` | Must | 3.1 |
| 3.3 | Create Traefik middleware definitions (`middlewares.yml`) | Must | 3.1 |
| 3.4 | Create initial ResourceSync TOML files (`servers.toml`, `stacks.toml`, `variables.toml`) | Must | Phase 2 |
| 3.5 | Bootstrap ResourceSync in Komodo Core pointing to this repo | Must | 3.4 |
| 3.6 | Create secrets in Komodo (CF_API_TOKEN, FORWARD_AUTH_*) | Must | 3.5 |
| 3.7 | Deploy Traefik stack via Komodo | Must | 3.1, 3.6 |
| 3.8 | Deploy forward-auth stack via Komodo | Must | 3.2, 3.7 |
| 3.9 | Deploy AdGuard/Unbound stack | Should | 3.7 |
| 3.10 | Configure GitHub webhook for ResourceSync auto-sync | Should | 3.5 |

### Phase 4 — Application Stacks & Validation

> **Focus**: Migrate application stacks to production server. Validate end-to-end functionality.

| Task | Description | Priority | Depends on |
|------|-------------|----------|------------|
| 4.1 | Create application stack Compose files + `.env.example` (Vaultwarden, Portainer, Homepage, etc.) | Must | Phase 3 |
| 4.2 | Add stack definitions to ResourceSync TOML with trust tier tags | Must | 4.1 |
| 4.3 | Create Traefik route files for each application | Must | 4.1 |
| 4.4 | Deploy all stacks to production server | Must | 4.2 |
| 4.5 | Validate end-to-end: Traefik → forward-auth → app → response | Must | 4.4 |
| 4.6 | Set up Gatus healthcheck stack | Should | 4.5 |
| 4.7 | Remove old `docker_compose_modules` role | Should | 4.5 |

### Phase 5 — CI & Testing

> **Focus**: Establish CI pipeline with Bats tests for Compose hardening, portability validation, and TOML validation.

| Task | Description | Priority | Depends on |
|------|-------------|----------|------------|
| 5.1 | Create `compose-hardening-test.bats` | Must | Phase 4 |
| 5.2 | Create `resourcesync-test.bats` | Should | Phase 3 |
| 5.3 | Create `compose-portability-test.bats` (validate no `[[VAR]]` usage, `.env.example` exists) | Should | Phase 4 |
| 5.4 | Update Renovate config for `komodo/stacks/` paths | Must | Phase 4 |
| 5.5 | Update GitHub Actions workflow for new test files | Must | 5.1 |

### Phase 6 — Hardening & Operations (Roadmap)

| Task | Description | Priority | Depends on |
|------|-------------|----------|------------|
| 6.1 | Set up Core database backup (`tiredofit/docker-db-backup` with `mongodump`) | Should | Phase 1 |
| 6.2 | Set up application volume backups | Could | Phase 4 |
| 6.3 | Migrate Core auth from local to OIDC | Could | Phase 1 |
| 6.4 | Enable `ui_write_disabled` after ResourceSync is stable | Could | Phase 3 |
| 6.5 | Set up Komodo alerting (Discord, email) | Should | Phase 4 |
| 6.6 | Implement automated Renovate PR → deploy pipeline | Could | Phase 5 |
| 6.7 | Onboard first untrusted server (DMZ) with restricted secret scope | Could | Phase 4 |

---

## 26. Migration from Ansible Pull

### Migration Strategy

Since the previous architecture was largely unimplemented (only basic Ansible roles and one Traefik module exist), the migration is a **greenfield build** rather than a data migration.

### What Gets Removed

| Component | Action | Rationale |
|-----------|--------|-----------|
| `ansible/roles/docker_compose_modules/` | Remove after Phase 4 | Replaced by Komodo Stacks |
| `compose_modules` host variable | Remove from host_vars | Replaced by `komodo_periphery` in `server_features` |
| SOPS configuration (if any) | Remove | Replaced by Komodo Secrets |
| Jinja2 Compose templates | Do not create | Compose files are now plain YAML |

### What Gets Retained

| Component | Status | Rationale |
|-----------|--------|-----------|
| All system-level Ansible roles | Unchanged | Komodo does not manage OS |
| `ansible_pull_setup` | Unchanged | System provisioning still uses ansible-pull |
| `maintenance` role | Unchanged | System maintenance timers |
| UFW firewall role | Updated | Add Periphery port 8120 rule (overlay CIDR only) |
| `geerlingguy.docker` | Unchanged | Docker engine installation |
| Bats tests for existing roles | Unchanged | Still valid |
| Container hardening standards | Carried forward | Applied to Compose files in `komodo/stacks/` |

### What Gets Added

| Component | Description |
|-----------|-------------|
| `bpbradley.komodo` role in requirements.yml | Periphery installation |
| `komodo_periphery` server feature | Replaces `compose_modules` |
| `server_trust_tier` host variable | Trusted/untrusted classification |
| `komodo/` directory | Stacks, sync TOML, Core config |
| `.env.example` per stack | Portability — enables standalone `docker compose up` |
| `ansible/playbooks/komodo-core.yml` | Core VM provisioning |
| Encrypted overlay network agent | Secure Core ↔ Periphery connectivity |
| Reverse proxy on Core VM | TLS termination for Komodo Core |
| Bats tests for Compose hardening | Validates `komodo/stacks/` |
| Bats tests for Compose portability | Validates no `[[VAR]]` usage |

---

## 27. Open Questions

| # | Question | Context | Severity |
|---|----------|---------|----------|
| 1 | Traefik routing to containers: shared network vs. host-port binding? | File-based routing requires Traefik to reach app containers. A shared `traefik-routing` network is simpler but reduces isolation. Host-port binding is more isolated but adds port management complexity. | High |
| 2 | Should ResourceSync auto-deploy stacks on Git push? | Auto-deploy is convenient but risky for production. Consider manual deploy for production with webhook-triggered sync of definitions only. | Medium |
| 3 | How to handle Core VM provisioning — Terraform or manual Azure CLI? | Ansible provisions the VM's OS, but VM creation itself needs a decision. | Medium |
| 4 | OIDC provider for Komodo Core authentication? | Authentik, Authelia, Zitadel, or cloud-based (Azure AD/Entra ID)? | Low |
| 5 | Alert destinations for Komodo monitoring? | Discord, Slack, email, PagerDuty? | Low |
| 6 | Which encrypted overlay network solution? | Tailscale (easiest, SaaS dependency), Headscale (self-hosted Tailscale), WireGuard (manual but proven), Nebula (self-hosted mesh), ZeroTier (SaaS). See [Section 11](#11-secure-connectivity). | High |
| 7 | Which reverse proxy for Komodo Core VM? | Caddy (automatic TLS, simple config), Traefik (consistent with on-prem), Nginx (mature, well-known). Only needed on the Core VM — on-prem uses the Traefik stack. | Medium |
| 8 | DNS automation via AdGuard API or manual management? | Auto-generation was complex in old architecture. Manual is simpler for a small fleet. | Low |
| 9 | How to scope Komodo secrets to trust tiers? | Komodo may not natively support secret scoping. May require separate Variable namespaces, server-level environment injection, or a convention-based approach. | Medium |

---

## 28. Roadmap Items

| # | Item | Priority | Notes |
|---|------|----------|-------|
| 1 | **OIDC authentication for Core** | Should | Replace local auth with SSO |
| 2 | **Azure Blob backup pipeline** | Should | Volume + MongoDB backups via `tiredofit/docker-db-backup` |
| 3 | **Komodo alerting to Discord** | Should | Server health + container alerts |
| 4 | **Automated Renovate → deploy** | Could | Auto-deploy non-critical image updates |
| 5 | **External monitoring** | Could | Uptime Robot or similar for Core reachability |
| 6 | **Centralized logging** | Could | Loki + Promtail stack via Komodo |
| 7 | **First untrusted server onboarding** | Could | DMZ server with scoped secrets and enhanced hardening |
| 8 | **Compose portability CI tests** | Should | Validate no `[[VAR]]` usage, `.env.example` presence |
| 9 | **Core high availability** | Won't (this time) | Overkill for homelab; single Core VM is sufficient |
| 10 | **Multi-region Periphery** | Won't (this time) | All servers are on the same LAN (+ overlay) |
