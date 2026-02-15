---
name: issue-creation
description: Creates well-structured GitHub issues following Scrum methodology with detailed functional descriptions, testing requirements, acceptance criteria, and business justification. Use when the user asks to create, draft, write, or plan issues, user stories, bugs, tasks, or backlog items.
---

# Issue Creation Skill

## Purpose

This skill creates comprehensive, developer-ready GitHub issues following **Scrum methodology**. Every issue must be complete enough for a developer or AI agent to pick up and implement without needing additional clarification.

## Issue Types

### Feature (User Story)

Use the **User Story** format for new functionality or enhancements.

### Bug

Use the **Bug Report** format for defects, regressions, or unexpected behavior.

---

## Mandatory Issue Sections

Every issue **must** contain all of the following sections. Do not skip any.

### 1. Title

- Prefix with issue type: `[Feature]` or `[Bug]`
- Be specific and action-oriented
- Include the affected component or role name
- Examples:
  - `[Feature] Add Prometheus monitoring Docker Compose module`
  - `[Bug] ansible-pull timer fails to restart after config change`

### 2. Description

Provide a detailed **functional description** of the work.

**For Features** — use the User Story format:

```markdown
## Description

**As a** [role/persona],
**I want** [capability/action],
**So that** [business value/outcome].

### Functional Details

[Detailed explanation of what needs to be built, how it should work, and how it
integrates with the existing system. Reference specific files, roles, playbooks,
or modules where applicable.]
```

**For Bugs** — use the Bug Report format and include a **Severity Classification**:

| Severity | Meaning |
|---|---|
| **Critical** | Active vulnerability, data exposure, or complete security control failure. Blocks deployment. |
| **High** | Significant weakening of security posture or missing defense-in-depth layer. Must fix before next release. |
| **Medium** | Reduces security margin or deviates from hardening best practices. Address soon. |
| **Low** | Minor hardening improvement or defense-in-depth enhancement. Address when convenient. |
| **Info** | Observation or suggestion. No immediate action required. |

```markdown
## Description

**Severity**: [Critical / High / Medium / Low / Info]

### Summary
[Clear, concise description of the defect.]

### Steps to Reproduce
1. [Step 1]
2. [Step 2]
3. [Step 3]

### Expected Behavior
[What should happen.]

### Actual Behavior
[What happens instead.]

### Environment
- **Host**: [e.g., SVLAZDOCK1, SVLAZDEV1]
- **OS**: [e.g., Ubuntu 24.04]
- **Ansible version**: [e.g., 2.20+]
- **Related roles/modules**: [e.g., docker_compose_modules, maintenance]
```

### 3. Scope

Define clear boundaries of the work. List what is **in scope** and what is **out of scope**.

```markdown
## Scope

### In Scope
- [ ] [Specific deliverable 1]
- [ ] [Specific deliverable 2]
- [ ] [Specific deliverable 3]

### Out of Scope
- [Item explicitly excluded and why]
- [Item deferred to a future issue]
```

### 4. Acceptance Criteria

Provide **measurable, testable** criteria using the Given/When/Then format. All criteria must be met for the issue to be considered **Done**.

```markdown
## Acceptance Criteria

- [ ] **Given** [precondition], **When** [action], **Then** [expected result]
- [ ] **Given** [precondition], **When** [action], **Then** [expected result]
- [ ] All existing tests pass (`task test`)
- [ ] No new yamllint errors (`task lint:yaml`)
- [ ] No new ansible-lint errors (`task lint:ansible`)
- [ ] Playbook syntax check passes (`task syntax`)
- [ ] Change is backward-compatible with existing servers running `ansible-pull` from `main`, or a migration path is documented
- [ ] Security Assessment section is completed (see Section 8)
```

### 5. Testing Requirements

Specify exactly what tests must be written or updated, and how to validate the work.

```markdown
## Testing Requirements

### New Tests
- [ ] [Describe new test case 1 — file location and what it validates]
- [ ] [Describe new test case 2 — file location and what it validates]

### Existing Tests
- [ ] All Bats tests pass: `task test` or `./tests/bash/run-tests.sh`
- [ ] Linting passes: `task lint`
- [ ] Syntax checks pass: `task syntax`
- [ ] CI pipeline passes on the PR branch

### Manual Validation
- [ ] [Describe any manual validation steps if applicable]
```

### 6. Business Justification (Necessity)

Explain **why** this work matters. State the business outcome expected.

```markdown
## Business Justification

### Problem
[What problem does this solve? What is the current pain point or gap?]

### Expected Outcome
[What measurable improvement or capability will this deliver?]

### Impact of Inaction
[What happens if this is not done? Risk, technical debt, user impact, etc.]

### Priority Rationale
[Why this priority level? What depends on this?]
```

### 7. Implementation Notes (Optional but Recommended)

Provide guidance to help the developer or AI agent get started quickly.

```markdown
## Implementation Notes

### Affected Files
- `ansible/roles/<role>/tasks/main.yml`
- `ansible/inventory/host_vars/<host>.yml`
- `tests/bash/<test>.bats`

### Approach
[Suggested implementation approach, patterns to follow, or relevant examples
in the codebase to reference.]

### Dependencies
- [External dependency, Ansible collection, or prerequisite issue]

### Risks
- [Known risks or areas requiring caution]
```

### 8. Security Assessment (Mandatory)

Every issue must include a security assessment. This is a **public repository** — every committed byte is visible to adversaries. Security analysis is not optional.

#### Security Impact Assessment

State whether the change affects the attack surface. If any of the following are true, the issue is **security-relevant** and requires the full security assessment below:

- Introduces a new Docker container or Compose module
- Exposes a new port or changes network configuration
- Modifies SSH key management or user access
- Changes the ansible-pull trust chain (scripts, timers, repo URL)
- Adds a new external dependency (image, collection, role, package)
- Changes secret handling (SOPS config, `.env` templates, vault)

If none of the above apply, state: *"No security impact — this change does not alter the attack surface."*

#### Full Security Assessment (for security-relevant issues)

```markdown
## Security Assessment

### Security Impact
[Does this change alter the attack surface? What is introduced, exposed, or modified?]

### STRIDE Threat Context
[Which STRIDE categories apply? Spoofing, Tampering, Repudiation, Information
Disclosure, Denial of Service, Elevation of Privilege. State the category and
the specific threat scenario.]

### Blast Radius
[How many servers/services are affected if this change has a defect?
A single module? All hosts? The entire ansible-pull pipeline?]

### Backward Compatibility
[Will this change break existing servers running ansible-pull from the main
branch? If yes, describe the migration path. If no, state why.]

### Rollback Strategy
[How can this change be reverted if it causes issues in production?
Describe the rollback steps.]

### Supply Chain Consideration
[If a new external dependency is introduced: Is it from a verified publisher?
Is it pinned by version and SHA digest? If no new dependency, state N/A.]

### Security Checklist
- [ ] No plaintext secrets introduced
- [ ] New containers use `security_opt: [no-new-privileges:true]`
- [ ] New containers specify a non-root user where the image supports it
- [ ] New containers drop all capabilities and add back only what is needed
- [ ] No unnecessary host ports exposed
- [ ] Docker networks are properly isolated (frontend/backend separation)
- [ ] Image references include SHA digest
- [ ] UFW rules are minimal and documented
- [ ] `.env` files are mode `0600` and owned by root
- [ ] SOPS encryption covers all sensitive variables
```

---

## Labels

Apply the appropriate labels to every issue:

| Label | Usage |
|---|---|
| `type: feature` | New functionality or enhancement |
| `type: bug` | Defect or regression |
| `priority: critical` | Blocks production or other work |
| `priority: high` | Should be in the current sprint |
| `priority: medium` | Should be in the next sprint |
| `priority: low` | Backlog, nice-to-have |
| `role: <name>` | Affected Ansible role (e.g., `role: docker_compose_modules`) |
| `area: ci` | CI/CD pipeline related |
| `area: testing` | Test suite related |
| `area: docs` | Documentation related |
| `area: security` | Security-relevant change |
| `severity: critical` | Active vulnerability or control failure (bugs only) |
| `severity: high` | Significant security posture weakening (bugs only) |
| `severity: medium` | Deviates from hardening best practices (bugs only) |
| `severity: low` | Minor hardening improvement (bugs only) |

---

## Scrum Estimation

Include a **Story Point estimate** using the Fibonacci scale (1, 2, 3, 5, 8, 13). Add this at the bottom of the issue.

```markdown
## Estimation

**Story Points**: [1/2/3/5/8/13]

| Points | Guideline |
|---|---|
| 1 | Trivial change, single file, no tests needed |
| 2 | Small change, 1-2 files, minor test updates |
| 3 | Moderate change, new task file or template, test additions |
| 5 | New role or module, multiple files, new test suite |
| 8 | Complex feature spanning multiple roles, significant testing |
| 13 | Large architectural change, should consider splitting |

> If estimated at 13 or above, split the issue into smaller issues.
```

---

## Definition of Done

Every issue must meet **all** of these criteria before it can be closed:

1. All **Acceptance Criteria** are met
2. All **Testing Requirements** are satisfied
3. Code follows the repository's [conventions](../../copilot-instructions.md):
   - 2-space YAML indentation
   - `ansible.builtin.*` FQCNs used
   - `snake_case` for variables, `UPPERCASE` for hosts
   - `---` document start markers
   - Lowercase booleans (`true`/`false`)
4. `task lint` passes with zero errors
5. `task syntax` passes
6. `task test` passes (all Bats tests)
7. CI pipeline passes on the PR branch
8. PR reviewed and approved (if applicable)
9. Changes are backward-compatible with existing servers (or migration path documented)
10. No secrets or credentials committed
11. Security Assessment completed — attack surface impact stated, STRIDE analysis done if security-relevant
12. New external dependencies are pinned by version and SHA digest

---

## Complete Issue Template — Feature

Below is a ready-to-use template. Fill in all bracketed placeholders.

```markdown
## Description

**As a** [role/persona],
**I want** [capability/action],
**So that** [business value/outcome].

### Functional Details

[Detailed explanation of the feature, its behavior, integration points,
and any relevant technical context.]

## Scope

### In Scope
- [ ] [Deliverable 1]
- [ ] [Deliverable 2]

### Out of Scope
- [Excluded item and reason]

## Acceptance Criteria

- [ ] **Given** [precondition], **When** [action], **Then** [expected result]
- [ ] **Given** [precondition], **When** [action], **Then** [expected result]
- [ ] All existing tests pass (`task test`)
- [ ] No new linting errors (`task lint`)
- [ ] Playbook syntax check passes (`task syntax`)

## Testing Requirements

### New Tests
- [ ] [Test description — file and validation target]

### Existing Tests
- [ ] `task test` — all Bats tests pass
- [ ] `task lint` — zero errors
- [ ] `task syntax` — passes
- [ ] CI pipeline passes

### Manual Validation
- [ ] [Manual step if applicable]

## Business Justification

### Problem
[Current pain point or gap.]

### Expected Outcome
[Measurable improvement.]

### Impact of Inaction
[Consequence of not doing this work.]

### Priority Rationale
[Why this priority?]

## Implementation Notes

### Affected Files
- [File paths]

### Approach
[Suggested approach.]

### Dependencies
- [Dependencies]

### Risks
- [Risks]

## Security Assessment

### Security Impact
[Does this change alter the attack surface? State yes/no and what is affected.
If no security impact, state: "No security impact — this change does not alter
the attack surface."]

### STRIDE Threat Context
[If security-relevant: which STRIDE categories apply and the threat scenario.
If not security-relevant: N/A]

### Blast Radius
[How many servers/services are affected if this change has a defect?]

### Backward Compatibility
[Will this break existing servers? Migration path if yes.]

### Rollback Strategy
[How can this change be reverted?]

### Supply Chain Consideration
[New external dependency? Verified publisher? Pinned by version + SHA? If none: N/A]

### Security Checklist
- [ ] No plaintext secrets introduced
- [ ] New containers use `security_opt: [no-new-privileges:true]`
- [ ] New containers specify a non-root user where supported
- [ ] No unnecessary host ports exposed
- [ ] Docker networks properly isolated
- [ ] Image references include SHA digest
- [ ] `.env` files are mode `0600` and owned by root

## Estimation

**Story Points**: [1/2/3/5/8/13]
```

---

## Complete Issue Template — Bug

```markdown
## Description

**Severity**: [Critical / High / Medium / Low / Info]

### Summary
[Clear description of the defect.]

### Steps to Reproduce
1. [Step 1]
2. [Step 2]
3. [Step 3]

### Expected Behavior
[What should happen.]

### Actual Behavior
[What happens instead.]

### Environment
- **Host**: [e.g., SVLAZDOCK1]
- **OS**: [e.g., Ubuntu 24.04]
- **Ansible version**: [e.g., 2.20+]
- **Related roles/modules**: [e.g., maintenance]

## Scope

### In Scope
- [ ] [Fix deliverable 1]
- [ ] [Fix deliverable 2]

### Out of Scope
- [Excluded item and reason]

## Acceptance Criteria

- [ ] **Given** [the bug scenario], **When** [action], **Then** [correct behavior]
- [ ] Bug no longer reproducible following the Steps to Reproduce
- [ ] No regression in related functionality
- [ ] All existing tests pass (`task test`)
- [ ] No new linting errors (`task lint`)

## Testing Requirements

### New Tests
- [ ] [Regression test — file and what it validates]

### Existing Tests
- [ ] `task test` — all Bats tests pass
- [ ] `task lint` — zero errors
- [ ] `task syntax` — passes
- [ ] CI pipeline passes

### Manual Validation
- [ ] [Reproduce the bug, apply the fix, verify resolution]

## Business Justification

### Problem
[Impact of the bug on operations or users.]

### Expected Outcome
[Bug resolved, system behaves correctly.]

### Impact of Inaction
[What happens if the bug is not fixed.]

### Priority Rationale
[Severity and urgency justification.]

## Implementation Notes

### Root Cause Analysis
[Known or suspected root cause.]

### Affected Files
- [File paths]

### Approach
[Suggested fix approach.]

### Risks
- [Risks of the fix, potential side effects]

## Security Assessment

### Security Impact
[Does this fix alter the attack surface? If no: "No security impact."]

### STRIDE Threat Context
[If the bug itself is a security issue, classify it. Otherwise: N/A]

### Blast Radius
[How many servers/services are affected by the bug and by the fix?]

### Backward Compatibility
[Will the fix break existing servers? Migration path if yes.]

### Rollback Strategy
[How to revert the fix if it introduces a regression.]

### Supply Chain Consideration
[If the fix changes dependencies: verified publisher? Pinned? Otherwise: N/A]

## Estimation

**Story Points**: [1/2/3/5/8/13]
```

---

## Rules for the Agent

1. **Never create a vague issue.** Every section must have concrete, specific content — no TODOs or "TBD" placeholders in the final issue.
2. **Always include all mandatory sections.** Omitting a section makes the issue incomplete and unactionable.
3. **Reference real files and paths** from this repository when listing affected files or implementation notes.
4. **Keep issues scoped.** A single issue should represent a single deployable unit of work. If the scope grows beyond 8 story points, split into multiple issues.
5. **Use the correct template** — Feature for new work, Bug for defects.
6. **Include testing commands** — always reference `task test`, `task lint`, and `task syntax` in testing requirements.
7. **Validate against the Definition of Done** before considering the issue ready.
8. **Write for the implementer** — assume the person (or agent) picking up the issue has access to the repo but no prior context about this specific change.
9. **Always complete the Security Assessment section.** If the change is not security-relevant, explicitly state "No security impact." Never leave it blank.
10. **Classify bug severity** — every bug must carry a severity label (Critical/High/Medium/Low/Info) in both the description and the issue labels.
11. **State backward compatibility** — every issue must confirm the change won't break servers pulling from `main`, or document the migration path.
12. **Include rollback strategy** for non-trivial changes — describe how the change can be reverted.
13. **Flag new external dependencies** — if the issue introduces a new Docker image, Ansible collection, or package, state the trust posture (verified publisher, version + SHA pinning).
