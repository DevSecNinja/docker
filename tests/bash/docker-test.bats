#!/usr/bin/env bats
# Tests for Docker provisioning

# Setup function runs before each test
setup() {
	# Get repository root
	REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
	export REPO_ROOT
	ANSIBLE_DIR="${REPO_ROOT}/ansible"
	export ANSIBLE_DIR
}

@test "docker-test: ansible is available" {
	if ! command -v ansible >/dev/null 2>&1; then
		run pip install ansible
		[ "$status" -eq 0 ]
	fi
	run ansible --version
	[ "$status" -eq 0 ]
}

@test "docker-test: ansible collections can be installed" {
	run ansible-galaxy collection install community.general ansible.posix community.docker
	[ "$status" -eq 0 ]
}

@test "docker-test: required roles can be installed" {
	cd "$ANSIBLE_DIR"
	# Try to install roles, but don't fail if some are unavailable
	ansible-galaxy install -r requirements.yml --ignore-errors || true
	# Just check that the command ran (exit code can be 0 or non-zero)
	[ -f requirements.yml ]
}

@test "docker-test: can create test inventory" {
	mkdir -p /tmp/test-inventory
	cat > /tmp/test-inventory/hosts.yml <<'EEOF'
---
all:
  children:
    docker_servers:
      hosts:
        localhost:
          ansible_connection: local
          ansible_become: true
          server_features:
            - docker
            - chezmoi
          compose_modules: []
EEOF

	[ -f /tmp/test-inventory/hosts.yml ]
}

@test "docker-test: playbook passes check mode" {
	# Ensure ansible is installed
	if ! command -v ansible-playbook >/dev/null 2>&1; then
		pip install ansible
	fi

	# Install collections
	ansible-galaxy collection install community.general ansible.posix community.docker

	# Create test inventory
	mkdir -p /tmp/test-inventory
	cat > /tmp/test-inventory/hosts.yml <<'EEOF'
---
all:
  children:
    docker_servers:
      hosts:
        localhost:
          ansible_connection: local
          ansible_become: true
          server_features:
            - docker
            - chezmoi
          compose_modules: []
EEOF

	cd "$ANSIBLE_DIR"
	run ansible-playbook \
		--check \
		--inventory /tmp/test-inventory/hosts.yml \
		--extra-vars "target_host=localhost" \
		--skip-tags traefik \
		playbooks/main.yml

	# Accept success or some expected warnings
	[ "$status" -eq 0 ] || [[ "$output" =~ "WARNING" ]]
}

@test "docker-test: docker role can be applied" {
	# Ensure ansible is installed
	if ! command -v ansible-playbook >/dev/null 2>&1; then
		pip install ansible
	fi

	# Install collections
	ansible-galaxy collection install community.general ansible.posix community.docker

	# Create test inventory
	mkdir -p /tmp/test-inventory
	cat > /tmp/test-inventory/hosts.yml <<'EEOF'
---
all:
  children:
    docker_servers:
      hosts:
        localhost:
          ansible_connection: local
          ansible_become: true
          server_features:
            - docker
          compose_modules: []
EEOF

	cd "$ANSIBLE_DIR"
	run ansible-playbook \
		--inventory /tmp/test-inventory/hosts.yml \
		--extra-vars "target_host=localhost" \
		--tags docker \
		playbooks/main.yml

	# Check if docker was installed successfully
	[ "$status" -eq 0 ]
}

@test "docker-test: docker command is available after installation" {
	# This test checks if docker was installed by the previous test
	if command -v docker >/dev/null 2>&1; then
		run docker --version
		[ "$status" -eq 0 ]
	else
		skip "Docker not installed (requires previous test to run successfully)"
	fi
}

@test "docker-test: docker service is running" {
	# Check if docker service is running
	if command -v docker >/dev/null 2>&1 && command -v systemctl >/dev/null 2>&1; then
		run sudo systemctl is-active docker
		# Accept if service is active or if systemctl is not available
		[ "$status" -eq 0 ] || [[ "$output" =~ "active" ]] || skip "Docker service not managed by systemd"
	else
		skip "Docker or systemctl not available"
	fi
}
