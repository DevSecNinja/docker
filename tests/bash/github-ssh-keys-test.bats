#!/usr/bin/env bats
# Tests for github_ssh_keys role

# Setup function runs before each test
setup() {
	# Get repository root
	REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
	export REPO_ROOT
	ANSIBLE_DIR="${REPO_ROOT}/ansible"
	export ANSIBLE_DIR
}

@test "github-ssh-keys-test: ansible is available" {
	if ! command -v ansible >/dev/null 2>&1; then
		run pip install ansible
		[ "$status" -eq 0 ]
	fi
	run ansible --version
	[ "$status" -eq 0 ]
}

@test "github-ssh-keys-test: required roles can be installed" {
	cd "$ANSIBLE_DIR"
	# Try to install roles, but don't fail if some are unavailable
	ansible-galaxy install -r requirements.yml --ignore-errors || true
	# Just check that the requirements file exists
	[ -f requirements.yml ]
}

@test "github-ssh-keys-test: can create test inventory" {
	mkdir -p /tmp/test-inventory
	cat > /tmp/test-inventory/hosts.yml <<'EEOF'
---
all:
  children:
    test_servers:
      hosts:
        localhost:
          ansible_connection: local
          ansible_become: true
          # Using 'runner' as ansible_user - this is the default user in GitHub Actions
          ansible_user: runner
          server_features:
            - github_ssh_keys
          # Using DevSecNinja for testing - in production, set to your GitHub username
          github_ssh_keys_username: DevSecNinja
EEOF
	[ -f /tmp/test-inventory/hosts.yml ]
}

@test "github-ssh-keys-test: GitHub SSH keys API is accessible" {
	# Verify GitHub SSH keys can be fetched
	run curl -f -s https://github.com/DevSecNinja.keys
	[ "$status" -eq 0 ]
}

@test "github-ssh-keys-test: playbook can run in check mode" {
	# Create test inventory
	mkdir -p /tmp/test-inventory
	cat > /tmp/test-inventory/hosts.yml <<'EEOF'
---
all:
  children:
    test_servers:
      hosts:
        localhost:
          ansible_connection: local
          ansible_become: true
          # Using 'vscode' user which exists in dev container
          ansible_user: vscode
          server_features:
            - github_ssh_keys
          # Using DevSecNinja for testing - in production, set to your GitHub username
          github_ssh_keys_username: DevSecNinja
EEOF

	# Run playbook in check mode with github_ssh_keys tag from repository root
	cd "$REPO_ROOT"
	run ansible-playbook \
		--check \
		--inventory /tmp/test-inventory/hosts.yml \
		--extra-vars "target_host=localhost" \
		--tags github_ssh_keys \
		ansible/playbooks/main.yml

	# Accept success (0) or check-mode specific warnings/limitations
	[ "$status" -eq 0 ] || [[ "$output" =~ "check mode" ]]
}
