#!/usr/bin/env bats
# Tests for the git_repos role (github_user enumeration format)

# Setup function runs before each test
setup() {
	# Get repository root
	REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
	export REPO_ROOT
	ANSIBLE_DIR="${REPO_ROOT}/ansible"
	export ANSIBLE_DIR
	ROLE_DIR="${ANSIBLE_DIR}/roles/git_repos"
	export ROLE_DIR
	# GitHub user enumerated by the end-to-end test
	GH_TEST_USER="DevSecNinja"
	export GH_TEST_USER
}

@test "git-repos-test: role files exist" {
	[ -f "$ROLE_DIR/tasks/main.yml" ]
	[ -f "$ROLE_DIR/tasks/github_user.yml" ]
	[ -f "$ROLE_DIR/defaults/main.yml" ]
}

@test "git-repos-test: github_user task file is valid YAML" {
	if ! command -v yamllint >/dev/null 2>&1; then
		run pip install yamllint
		[ "$status" -eq 0 ]
	fi
	cd "$REPO_ROOT"
	run yamllint "$ROLE_DIR/tasks/github_user.yml"
	[ "$status" -eq 0 ]
}

@test "git-repos-test: main task file includes github_user sub-tasks" {
	run grep -q "github_user.yml" "$ROLE_DIR/tasks/main.yml"
	[ "$status" -eq 0 ]
}

@test "git-repos-test: GitHub repos API is accessible for test user" {
	# Verify the public repositories endpoint responds
	run curl -f -s "https://api.github.com/users/${GH_TEST_USER}/repos?per_page=1"
	[ "$status" -eq 0 ]
	# Response must be a JSON array
	[[ "$output" =~ ^\[ ]]
}

@test "git-repos-test: end-to-end clone of a single repo" {
	# Requires sudo (apt) and network access; only run in CI
	if [ "$CI" != "true" ]; then
		skip "Skipping e2e clone test in local environment (requires sudo + network)"
	fi

	local dest="/tmp/git-repos-e2e"
	rm -rf "$dest"

	# Minimal playbook that applies only the git_repos role, capped at one repo
	cat > /tmp/git-repos-e2e-playbook.yml <<EEOF
---
- name: E2E test git_repos github_user format
  hosts: localhost
  connection: local
  become: true
  vars:
    ansible_user: runner
    git_repos:
      - github_user: ${GH_TEST_USER}
        dest: ${dest}
        user: runner
        group: runner
        limit: 1
  roles:
    - role: git_repos
EEOF

	# Run from the repository root so ansible.cfg resolves roles_path
	cd "$REPO_ROOT"
	run timeout 180 ansible-playbook /tmp/git-repos-e2e-playbook.yml
	[ "$status" -eq 0 ]

	# Exactly one repository should have been cloned
	local cloned
	cloned=$(find "$dest" -mindepth 2 -maxdepth 2 -name ".git" -type d | wc -l)
	[ "$cloned" -eq 1 ]
}
