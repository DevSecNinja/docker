#!/usr/bin/env bats
# Tests for Ansible linting

# Setup function runs before each test
setup() {
	# Get repository root
	REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
	export REPO_ROOT
	ANSIBLE_DIR="${REPO_ROOT}/ansible"
	export ANSIBLE_DIR
}

@test "lint-test: yamllint is available or can be installed" {
	if ! command -v yamllint >/dev/null 2>&1; then
		run pip install yamllint
		[ "$status" -eq 0 ]
	fi
	run yamllint --version
	[ "$status" -eq 0 ]
}

@test "lint-test: ansible-lint is available or can be installed" {
	if ! command -v ansible-lint >/dev/null 2>&1; then
		run pip install ansible ansible-lint
		[ "$status" -eq 0 ]
	fi
	# Check if ansible-lint actually works (may fail on Python 3.14+)
	run ansible-lint --version
	if [ "$status" -ne 0 ]; then
		skip "ansible-lint not compatible with current Python version"
	fi
}

@test "lint-test: yamllint passes on ansible directory" {
	# Ensure yamllint is installed
	if ! command -v yamllint >/dev/null 2>&1; then
		pip install yamllint
	fi

	cd "$ANSIBLE_DIR"
	# Only lint our own files, exclude external roles
	run bash -c "find . -name '*.yml' -o -name '*.yaml' | grep -v 'roles/geerlingguy' | xargs yamllint"
	[ "$status" -eq 0 ]
}

@test "lint-test: ansible-lint passes on roles" {
	# Check if ansible-lint is functional first
	if ! ansible-lint --version >/dev/null 2>&1; then
		skip "ansible-lint not compatible with current Python version"
	fi

	cd "$ANSIBLE_DIR"
	run ansible-lint -c .ansible-lint roles/
	[ "$status" -eq 0 ]
}

@test "lint-test: all YAML files have valid syntax" {
	cd "$REPO_ROOT"

	# Find all YAML files
	local found_yaml=false
	while IFS= read -r yaml_file; do
		if [ -n "$yaml_file" ] && [ -f "$yaml_file" ]; then
			found_yaml=true
			# Basic syntax check using Python
			run python3 -c "import yaml; yaml.safe_load(open('$yaml_file'))"
			if [ "$status" -ne 0 ]; then
				echo "YAML syntax error in: $yaml_file"
				return 1
			fi
		fi
	done < <(find ansible -name "*.yml" -o -name "*.yaml" 2>/dev/null)

	if [ "$found_yaml" = false ]; then
		skip "No YAML files found"
	fi
}
