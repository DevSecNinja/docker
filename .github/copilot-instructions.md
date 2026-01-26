# Copilot Instructions for Docker Infrastructure Repository

## Project Overview

This is an Ansible-based infrastructure automation repository that manages Docker servers using the **Ansible Pull** approach. Servers automatically pull their configuration from this repository and apply changes when Git commits are detected.

## Technology Stack

- **Ansible**: 2.20+ (Infrastructure as Code)
- **Python**: 3.8+ (Ansible runtime)
- **Docker**: Container platform managed by Ansible
- **YAML**: Configuration and playbook syntax
- **Bash**: Helper scripts
- **GitHub Actions**: CI/CD pipeline

## Key Commands

### Testing
```bash
# Lint YAML and Ansible files
bash ansible/scripts/tests/lint-test.sh

# Check Ansible syntax
bash ansible/scripts/tests/syntax-test.sh

# Test Docker provisioning
bash ansible/scripts/tests/docker-test.sh
```

### Running Ansible
```bash
# Manual ansible-pull execution
sudo ansible-pull \
    --url https://github.com/DevSecNinja/docker.git \
    --checkout main \
    --directory /var/lib/ansible/local \
    --inventory ansible/inventory/hosts.yml \
    --extra-vars "target_host=$(hostname)" \
    --only-if-changed \
    ansible/playbooks/main.yml
```

### Local Development
```bash
# Install required Ansible collections
ansible-galaxy collection install -r ansible/requirements.yml

# Check playbook syntax locally
ansible-playbook ansible/playbooks/main.yml --syntax-check
```

## Repository Structure

```
ansible/
├── ansible.cfg              # Ansible configuration
├── requirements.yml         # External roles and collections
├── playbooks/
│   └── main.yml            # Main playbook for ansible-pull
├── inventory/
│   ├── hosts.yml           # Server inventory
│   └── host_vars/          # Host-specific variables
├── roles/                   # Custom Ansible roles
│   ├── ansible_pull_setup/ # Ansible-pull automation
│   ├── chezmoi/            # Dotfiles management
│   ├── docker_compose_modules/  # Modular Docker Compose
│   ├── traefik/            # Reverse proxy
│   └── ufw/                # Firewall configuration
└── scripts/
    ├── ansible-pull.sh     # Installation wrapper
    └── tests/              # CI/CD test scripts
```

## Code Conventions

### Ansible Playbooks and Roles
- Use YAML with 2-space indentation
- Follow Ansible best practices for role structure
- All playbooks must start with `---`
- Use descriptive task names with proper capitalization
- Use `ansible.builtin.*` module names explicitly
- Always include `meta/main.yml` with role dependencies
- Use `defaults/main.yml` for default variables
- Use `handlers/main.yml` for service restarts

### YAML Style
- Use 2-space indentation (never tabs)
- No trailing whitespace
- End files with a single newline
- Use `---` document start marker
- Quote strings when they contain special characters
- Use lowercase for booleans: `true`, `false`

### Naming Conventions
- Roles: lowercase with underscores (e.g., `ansible_pull_setup`)
- Variables: lowercase with underscores (e.g., `server_features`)
- Host names: UPPERCASE (e.g., `SVLAZDOCK1`)
- Tags: lowercase (e.g., `docker`, `traefik`)

### File Organization
- Group related tasks in role subdirectories
- Use `tasks/main.yml` as the entry point for roles
- Split complex roles into separate task files
- Store templates in `templates/` directory
- Keep defaults in `defaults/main.yml`

## Testing Requirements

### Before Making Changes
1. Always run linting first: `bash ansible/scripts/tests/lint-test.sh`
2. Check syntax: `bash ansible/scripts/tests/syntax-test.sh`
3. For Docker-related changes, run: `bash ansible/scripts/tests/docker-test.sh`

### After Making Changes
- All YAML files must pass yamllint
- All Ansible files must pass ansible-lint
- Playbooks must pass syntax-check
- GitHub Actions workflow must succeed

### CI/CD Pipeline
The repository includes comprehensive GitHub Actions testing:
- Lint checks (yamllint, ansible-lint)
- Syntax validation
- Docker provisioning tests
- Ansible-pull functionality tests

Workflows trigger on:
- Push to `main` or `copilot/**` branches
- Pull requests
- Manual workflow dispatch

## Important Boundaries

### DO NOT Modify
- `.git/` directory or git history
- LICENSE file (MIT License)
- Production server configurations without explicit approval
- Secrets or credentials (use Ansible Vault if needed)

### DO Modify Carefully
- `ansible/inventory/hosts.yml` - Server inventory (only with clear understanding)
- `ansible/playbooks/main.yml` - Main playbook (ensure backward compatibility)
- GitHub Actions workflows - Test thoroughly before merging

### ALWAYS
- Follow existing code structure and patterns
- Test changes using provided test scripts
- Maintain backward compatibility with existing servers
- Document significant changes in commit messages
- Use feature branches for development
- Keep changes minimal and focused

## Example Workflows

### Adding a New Ansible Role
1. Create role structure:
   ```bash
   cd ansible/roles
   mkdir -p newrole/{tasks,defaults,meta,templates,handlers}
   ```

2. Create `tasks/main.yml`:
   ```yaml
   ---
   - name: Example task
     ansible.builtin.debug:
       msg: "This is a new role"
   ```

3. Add `meta/main.yml` with dependencies:
   ```yaml
   ---
   dependencies: []
   ```

4. Add to `ansible/playbooks/main.yml`
5. Test with CI pipeline

### Adding a New Server
1. Add to `ansible/inventory/hosts.yml`:
   ```yaml
   NEWSERVER:
     ansible_host: newserver.local
     ansible_user: ansible
     server_features:
       - docker
   ```

2. (Optional) Add host-specific vars in `ansible/inventory/host_vars/NEWSERVER.yml`
3. Test the configuration

### Modifying Docker Compose Modules
1. Edit module definition in `ansible/roles/docker_compose_modules/vars/modules/`
2. Update role tasks if needed in `ansible/roles/docker_compose_modules/tasks/`
3. Test with: `bash ansible/scripts/tests/docker-test.sh`

## Security Considerations

- Never commit secrets, API keys, or passwords
- Use Ansible Vault for sensitive data (when implemented)
- Follow principle of least privilege for user permissions
- Keep UFW firewall rules restrictive
- Review Docker container security best practices
- Validate all external inputs

## Documentation

- Update README.md for significant feature additions
- Update INSTALL.md for installation procedure changes
- Keep inline comments minimal unless explaining complex logic
- Use descriptive task names that explain the purpose
- Document role variables in `defaults/main.yml` comments

## Common Pitfalls to Avoid

1. Don't use tabs in YAML files (use 2 spaces)
2. Don't skip linting and syntax checks
3. Don't break ansible-pull functionality (it's core to this repo)
4. Don't hardcode values that should be variables
5. Don't remove or modify unrelated tests
6. Don't add unnecessary dependencies
7. Always use `--no-pager` with git commands in scripts to avoid interactive prompts

## Additional Resources

- Ansible Documentation: https://docs.ansible.com/
- Ansible Best Practices: https://docs.ansible.com/ansible/latest/user_guide/playbooks_best_practices.html
- Docker Documentation: https://docs.docker.com/
- Repository README: [README.md](../README.md)
- Installation Guide: [INSTALL.md](../INSTALL.md)
