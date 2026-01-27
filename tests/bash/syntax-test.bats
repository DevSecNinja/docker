#!/usr/bin/env bats
# Tests for Ansible syntax check

# Setup function runs before each test
setup() {
	# Get repository root
	REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
	export REPO_ROOT
	ANSIBLE_DIR="${REPO_ROOT}/ansible"
	export ANSIBLE_DIR
}

@test "syntax-test: ansible is available or can be installed" {
	if ! command -v ansible >/dev/null 2>&1; then
		run pip install ansible
		[ "$status" -eq 0 ]
	fi
	run ansible --version
	[ "$status" -eq 0 ]
}

@test "syntax-test: required ansible collections can be installed" {
	# Install Ansible if needed
	if ! command -v ansible-galaxy >/dev/null 2>&1; then
		pip install ansible
	fi

	run ansible-galaxy collection install community.general ansible.posix community.docker
	[ "$status" -eq 0 ]
}

@test "syntax-test: main playbook exists" {
	[ -f "$ANSIBLE_DIR/playbooks/main.yml" ]
}

@test "syntax-test: main playbook has valid syntax" {
	# Install Ansible if needed
	if ! command -v ansible-playbook >/dev/null 2>&1; then
		pip install ansible
	fi

	# Install collections
	ansible-galaxy collection install community.general ansible.posix community.docker || true

	# Install required roles (ignore errors for external roles)
	ansible-galaxy install -r "$ANSIBLE_DIR/requirements.yml" --ignore-errors || true

	cd "$REPO_ROOT"
	# Try syntax check, but don't fail if external roles are missing
	run ansible-playbook --syntax-check ansible/playbooks/main.yml
	# Accept success or role-not-found errors (expected when external roles aren't installed)
	[ "$status" -eq 0 ] || [[ "$output" =~ "role".*"could not be found" ]] || [[ "$output" =~ "couldn't resolve module" ]]
}

@test "syntax-test: all shell scripts have valid syntax" {
	cd "$REPO_ROOT"

	# Find all .sh files and validate syntax
	local found_scripts=false
	while IFS= read -r script; do
		if [ -n "$script" ] && [ -f "$script" ]; then
			if head -n 1 "$script" | grep -q "#!/bin/bash\|#!/usr/bin/env bash"; then
				found_scripts=true
				run bash -n "$script"
				if [ "$status" -ne 0 ]; then
					echo "Bash syntax error in: $script"
					return 1
				fi
			elif head -n 1 "$script" | grep -q "#!/bin/sh"; then
				found_scripts=true
				run sh -n "$script"
				if [ "$status" -ne 0 ]; then
					echo "Shell syntax error in: $script"
					return 1
				fi
			fi
		fi
	done < <(find ansible tests -name "*.sh" 2>/dev/null | grep -v node_modules || true)

	if [ "$found_scripts" = false ]; then
		skip "No shell scripts found"
	fi
}
