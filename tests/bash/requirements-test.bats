#!/usr/bin/env bats
# Tests for Python dependency requirements

setup() {
	# Get repository root
	REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
	export REPO_ROOT
	REQUIREMENTS_FILE="${REPO_ROOT}/requirements.txt"
	export REQUIREMENTS_FILE
}

@test "requirements-test: uses maintained Molecule Docker driver plugin" {
	run bash -c "grep -Eq '^molecule-plugins\\[docker\\]==[0-9]+\\.[0-9]+\\.[0-9]+$' \"${REQUIREMENTS_FILE}\""
	[ "$status" -eq 0 ]
}

@test "requirements-test: excludes abandoned molecule-docker package" {
	run bash -c "! grep -Eiq '^[[:space:]]*molecule-docker([=<>~![:space:]]|$)' \"${REQUIREMENTS_FILE}\""
	[ "$status" -eq 0 ]
}

@test "requirements-test: does not pin transitive Jinja dependency directly" {
	run bash -c "! grep -Eiq '^[[:space:]]*jinja2([=<>~![:space:]]|$)' \"${REQUIREMENTS_FILE}\""
	[ "$status" -eq 0 ]
}
