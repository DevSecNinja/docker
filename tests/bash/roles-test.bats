#!/usr/bin/env bats
# Test file for additional Ansible roles
# Tests for system_setup, ufw, maintenance, and docker_group roles

setup() {
    REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    export REPO_ROOT
    ANSIBLE_DIR="${REPO_ROOT}/ansible"
    export ANSIBLE_DIR
}

# ============================================================
# system_setup role tests
# ============================================================

@test "system_setup role: directory structure exists" {
    [ -d "${ANSIBLE_DIR}/roles/system_setup/tasks" ]
    [ -d "${ANSIBLE_DIR}/roles/system_setup/defaults" ]
    [ -d "${ANSIBLE_DIR}/roles/system_setup/meta" ]
    [ -d "${ANSIBLE_DIR}/roles/system_setup/templates" ]
}

@test "system_setup role: main.yml exists and has valid syntax" {
    [ -f "${ANSIBLE_DIR}/roles/system_setup/tasks/main.yml" ]
    run python3 -c "import yaml; yaml.safe_load(open('${ANSIBLE_DIR}/roles/system_setup/tasks/main.yml'))"
    [ "$status" -eq 0 ]
}

@test "system_setup role: uses FQCN for ansible.builtin modules" {
    # Check for bare module names at the start of a task (after - name:)
    # Exclude attribute names like 'shell:' within other modules
    run grep -E "^- (user|group|file|template|copy|command|shell|apt|debug):" \
        "${ANSIBLE_DIR}/roles/system_setup/tasks/main.yml"
    # Should find nothing (all should use FQCN)
    [ "$status" -eq 1 ] || [ -z "$output" ]
}

@test "system_setup role: defaults exist" {
    [ -f "${ANSIBLE_DIR}/roles/system_setup/defaults/main.yml" ]
}

# ============================================================
# docker_group role tests
# ============================================================

@test "docker_group role: directory structure exists" {
    [ -d "${ANSIBLE_DIR}/roles/docker_group/tasks" ]
    [ -d "${ANSIBLE_DIR}/roles/docker_group/defaults" ]
    [ -d "${ANSIBLE_DIR}/roles/docker_group/meta" ]
}

@test "docker_group role: main.yml exists and has valid syntax" {
    [ -f "${ANSIBLE_DIR}/roles/docker_group/tasks/main.yml" ]
    run python3 -c "import yaml; yaml.safe_load(open('${ANSIBLE_DIR}/roles/docker_group/tasks/main.yml'))"
    [ "$status" -eq 0 ]
}

@test "docker_group role: uses FQCN for ansible.builtin modules" {
    run grep -E "^\s+(group|user|file|debug):" \
        "${ANSIBLE_DIR}/roles/docker_group/tasks/main.yml"
    # Should find nothing (all should use FQCN)
    [ "$status" -eq 1 ] || [ -z "$output" ]
}

@test "docker_group role: has README documentation" {
    [ -f "${ANSIBLE_DIR}/roles/docker_group/README.md" ]
}

# ============================================================
# ufw role tests
# ============================================================

@test "ufw role: directory structure exists" {
    [ -d "${ANSIBLE_DIR}/roles/ufw/tasks" ]
    [ -d "${ANSIBLE_DIR}/roles/ufw/defaults" ]
    [ -d "${ANSIBLE_DIR}/roles/ufw/meta" ]
}

@test "ufw role: main.yml exists and has valid syntax" {
    [ -f "${ANSIBLE_DIR}/roles/ufw/tasks/main.yml" ]
    run python3 -c "import yaml; yaml.safe_load(open('${ANSIBLE_DIR}/roles/ufw/tasks/main.yml'))"
    [ "$status" -eq 0 ]
}

@test "ufw role: uses FQCN for ansible.builtin modules" {
    run grep -E "^\s+(apt|command|debug):" "${ANSIBLE_DIR}/roles/ufw/tasks/main.yml"
    # Should find nothing (all should use FQCN)
    [ "$status" -eq 1 ] || [ -z "$output" ]
}

@test "ufw role: uses community.general.ufw module" {
    run grep "community.general.ufw" "${ANSIBLE_DIR}/roles/ufw/tasks/main.yml"
    [ "$status" -eq 0 ]
}

@test "ufw role: defaults include SSH protection" {
    run grep -E "ufw_allow_ssh|ufw_ssh_port" "${ANSIBLE_DIR}/roles/ufw/defaults/main.yml"
    [ "$status" -eq 0 ]
}

# ============================================================
# maintenance role tests
# ============================================================

@test "maintenance role: directory structure exists" {
    [ -d "${ANSIBLE_DIR}/roles/maintenance/tasks" ]
    [ -d "${ANSIBLE_DIR}/roles/maintenance/defaults" ]
    [ -d "${ANSIBLE_DIR}/roles/maintenance/meta" ]
    [ -d "${ANSIBLE_DIR}/roles/maintenance/templates" ]
    [ -d "${ANSIBLE_DIR}/roles/maintenance/handlers" ]
}

@test "maintenance role: main.yml exists and has valid syntax" {
    [ -f "${ANSIBLE_DIR}/roles/maintenance/tasks/main.yml" ]
    run python3 -c "import yaml; yaml.safe_load(open('${ANSIBLE_DIR}/roles/maintenance/tasks/main.yml'))"
    [ "$status" -eq 0 ]
}

@test "maintenance role: daily maintenance tasks exist and valid" {
    [ -f "${ANSIBLE_DIR}/roles/maintenance/tasks/setup_daily_maintenance.yml" ]
    run python3 -c "import yaml; yaml.safe_load(open('${ANSIBLE_DIR}/roles/maintenance/tasks/setup_daily_maintenance.yml'))"
    [ "$status" -eq 0 ]
}

@test "maintenance role: weekly maintenance tasks exist and valid" {
    [ -f "${ANSIBLE_DIR}/roles/maintenance/tasks/setup_weekly_maintenance.yml" ]
    run python3 -c "import yaml; yaml.safe_load(open('${ANSIBLE_DIR}/roles/maintenance/tasks/setup_weekly_maintenance.yml'))"
    [ "$status" -eq 0 ]
}

@test "maintenance role: uses FQCN for ansible.builtin modules" {
    # Check all maintenance task files
    for file in main.yml setup_daily_maintenance.yml setup_weekly_maintenance.yml setup_docker_maintenance.yml docker_maintenance.yml; do
        run grep -E "^\s+(file|template|debug|include_tasks|meta|systemd):" \
            "${ANSIBLE_DIR}/roles/maintenance/tasks/${file}"
        # Should find nothing (all should use FQCN)
        [ "$status" -eq 1 ] || [ -z "$output" ]
    done
}

@test "maintenance role: systemd templates exist" {
    [ -f "${ANSIBLE_DIR}/roles/maintenance/templates/maintenance-daily.service.j2" ]
    [ -f "${ANSIBLE_DIR}/roles/maintenance/templates/maintenance-daily.timer.j2" ]
    [ -f "${ANSIBLE_DIR}/roles/maintenance/templates/maintenance-weekly.service.j2" ]
    [ -f "${ANSIBLE_DIR}/roles/maintenance/templates/maintenance-weekly.timer.j2" ]
    [ -f "${ANSIBLE_DIR}/roles/maintenance/templates/maintenance-docker.service.j2" ]
    [ -f "${ANSIBLE_DIR}/roles/maintenance/templates/maintenance-docker.timer.j2" ]
}

@test "maintenance role: docker maintenance tasks exist" {
    [ -f "${ANSIBLE_DIR}/roles/maintenance/tasks/docker_maintenance.yml" ]
    [ -f "${ANSIBLE_DIR}/roles/maintenance/tasks/setup_docker_maintenance.yml" ]
}

@test "maintenance role: docker maintenance playbook exists and has valid syntax" {
    [ -f "${REPO_ROOT}/ansible/playbooks/maintenance-docker.yml" ]
    run ansible-playbook "${REPO_ROOT}/ansible/playbooks/maintenance-docker.yml" --syntax-check
    [ "$status" -eq 0 ]
}

# ============================================================
# package_managers role tests
# ============================================================

@test "package_managers role: directory structure exists" {
    [ -d "${ANSIBLE_DIR}/roles/package_managers/tasks" ]
    [ -d "${ANSIBLE_DIR}/roles/package_managers/defaults" ]
    [ -d "${ANSIBLE_DIR}/roles/package_managers/meta" ]
}

@test "package_managers role: main.yml exists and has valid syntax" {
    [ -f "${ANSIBLE_DIR}/roles/package_managers/tasks/main.yml" ]
    run python3 -c "import yaml; yaml.safe_load(open('${ANSIBLE_DIR}/roles/package_managers/tasks/main.yml'))"
    [ "$status" -eq 0 ]
}

@test "package_managers role: install_homebrew.yml exists and has valid syntax" {
    [ -f "${ANSIBLE_DIR}/roles/package_managers/tasks/install_homebrew.yml" ]
    run python3 -c "import yaml; yaml.safe_load(open('${ANSIBLE_DIR}/roles/package_managers/tasks/install_homebrew.yml'))"
    [ "$status" -eq 0 ]
}

@test "package_managers role: uses FQCN for ansible.builtin modules" {
    for file in main.yml install_homebrew.yml; do
        run grep -E "^\s+(apt|command|copy|debug|file|get_url|stat|include_tasks):" \
            "${ANSIBLE_DIR}/roles/package_managers/tasks/${file}"
        # Should find nothing (all should use FQCN)
        [ "$status" -eq 1 ] || [ -z "$output" ]
    done
}

@test "package_managers role: defaults exist" {
    [ -f "${ANSIBLE_DIR}/roles/package_managers/defaults/main.yml" ]
}

@test "package_managers role: cleans up temporary sudo in always block" {
    run grep -A2 "always:" "${ANSIBLE_DIR}/roles/package_managers/tasks/install_homebrew.yml"
    [ "$status" -eq 0 ]
    run grep "homebrew_temp_" "${ANSIBLE_DIR}/roles/package_managers/tasks/install_homebrew.yml"
    [ "$status" -eq 0 ]
}

@test "package_managers role: is included in main playbook" {
    run grep "role: package_managers" "${ANSIBLE_DIR}/playbooks/main.yml"
    [ "$status" -eq 0 ]
}

# ============================================================
# docker_compose_modules role tests
# ============================================================

@test "docker_compose_modules role: uses FQCN for ansible.builtin modules" {
    # Check for bare module names at task level (starting with hyphen)
    # Exclude attribute names like 'file:' within other modules
    for file in main.yml deploy_module.yml; do
        run grep -E "^- (file|template|debug|include_tasks|include_vars):" \
            "${ANSIBLE_DIR}/roles/docker_compose_modules/tasks/${file}"
        # Should find nothing (all should use FQCN)
        [ "$status" -eq 1 ] || [ -z "$output" ]
    done
}

@test "docker_compose_modules role: traefik module configuration exists" {
    [ -f "${ANSIBLE_DIR}/roles/docker_compose_modules/vars/modules/traefik.yml" ]
    run python3 -c "import yaml; yaml.safe_load(open('${ANSIBLE_DIR}/roles/docker_compose_modules/vars/modules/traefik.yml'))"
    [ "$status" -eq 0 ]
}

# ============================================================
# Removed traefik role verification (duplicate was removed)
# ============================================================

@test "duplicate traefik role: should not exist (using docker_compose_modules instead)" {
    [ ! -d "${ANSIBLE_DIR}/roles/traefik" ]
}

# ============================================================
# Inventory structure tests
# ============================================================

@test "inventory: hosts.yml uses server type groups instead of docker_servers" {
    # The old docker_servers group must not exist
    run grep "docker_servers" "${ANSIBLE_DIR}/inventory/hosts.yml"
    [ "$status" -eq 1 ]

    # Server type groups must exist
    run grep "application_servers" "${ANSIBLE_DIR}/inventory/hosts.yml"
    [ "$status" -eq 0 ]
    run grep "development_servers" "${ANSIBLE_DIR}/inventory/hosts.yml"
    [ "$status" -eq 0 ]
    run grep "dmz_servers" "${ANSIBLE_DIR}/inventory/hosts.yml"
    [ "$status" -eq 0 ]
}

@test "inventory: each host belongs to exactly one server type group" {
    # Ensure ansible is installed
    if ! command -v ansible-inventory >/dev/null 2>&1; then
        pip install ansible >/dev/null 2>&1
    fi

    # Define server type groups
    local server_type_groups="application_servers development_servers dmz_servers infrastructure_servers"

    # Get all hosts from the inventory
    cd "$REPO_ROOT"
    local hosts
    hosts=$(ansible-inventory -i "${ANSIBLE_DIR}/inventory/hosts.yml" --list 2>/dev/null \
        | python3 -c "import sys,json; d=json.load(sys.stdin); meta=d.get('_meta',{}).get('hostvars',{}); print(' '.join(meta.keys()))")

    for host in $hosts; do
        local count=0
        for group in $server_type_groups; do
            # Check if this host is in this group
            local in_group
            in_group=$(ansible-inventory -i "${ANSIBLE_DIR}/inventory/hosts.yml" --list 2>/dev/null \
                | python3 -c "import sys,json; d=json.load(sys.stdin); g=d.get('${group}',{}).get('hosts',[]); print('yes' if '${host}' in g else 'no')")
            if [ "$in_group" = "yes" ]; then
                count=$((count + 1))
            fi
        done
        # Each host must be in exactly one server type group
        [ "$count" -eq 1 ] || {
            echo "Host '${host}' is in ${count} server type groups (expected exactly 1)" >&2
            false
        }
    done
}

@test "inventory: ansible_host is defined for every host" {
    # Ensure ansible is installed
    if ! command -v ansible-inventory >/dev/null 2>&1; then
        pip install ansible >/dev/null 2>&1
    fi

    cd "$REPO_ROOT"
    # Get hostvars and check ansible_host for each
    local result
    result=$(ansible-inventory -i "${ANSIBLE_DIR}/inventory/hosts.yml" --list 2>/dev/null \
        | python3 -c "
import sys, json
d = json.load(sys.stdin)
hostvars = d.get('_meta', {}).get('hostvars', {})
missing = [h for h, v in hostvars.items() if 'ansible_host' not in v]
if missing:
    print('MISSING: ' + ', '.join(missing))
    sys.exit(1)
else:
    print('OK')
")
    [ "$result" = "OK" ] || {
        echo "Hosts missing ansible_host: ${result}" >&2
        false
    }
}

@test "inventory: no server_type variable in host_vars (DD-37)" {
    # server_type must be derived from group membership, not set explicitly
    for host_var_file in "${ANSIBLE_DIR}"/inventory/host_vars/*.yml; do
        run grep -E "^server_type:" "$host_var_file"
        [ "$status" -eq 1 ] || {
            echo "Found explicit server_type in $(basename "$host_var_file") — must be derived from group_names (DD-37)" >&2
            false
        }
    done
}

@test "inventory: svlazdock1 has server_environment set to production" {
    run grep "server_environment: production" "${ANSIBLE_DIR}/inventory/host_vars/svlazdock1.yml"
    [ "$status" -eq 0 ]
}

@test "inventory: svlazdev1 has server_environment set to development" {
    run grep "server_environment: development" "${ANSIBLE_DIR}/inventory/host_vars/svlazdev1.yml"
    [ "$status" -eq 0 ]
}

@test "inventory: svlazdev1 has deploy_all_modules enabled" {
    run grep "deploy_all_modules: true" "${ANSIBLE_DIR}/inventory/host_vars/svlazdev1.yml"
    [ "$status" -eq 0 ]
}
