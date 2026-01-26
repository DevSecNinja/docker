# Bats Testing Framework

This directory contains the test suite for the Ansible Docker infrastructure using the [Bats (Bash Automated Testing System)](https://github.com/bats-core/bats-core) framework.

## Overview

The test suite validates:
- Ansible configuration syntax and linting
- Ansible playbook execution
- Docker provisioning
- ansible-pull functionality
- Shell script syntax

## Directory Structure

```
tests/bash/
├── run-tests.sh              # Test runner script
├── lint-test.bats            # Linting tests (yamllint, ansible-lint)
├── syntax-test.bats          # Syntax validation tests
├── docker-test.bats          # Docker provisioning tests
└── ansible-pull-test.bats    # ansible-pull functionality tests
```

## Running Tests

### Run All Tests

```bash
./tests/bash/run-tests.sh
```

### Run Specific Test File

```bash
./tests/bash/run-tests.sh --test lint-test.bats
```

### Run in CI Mode

This installs dependencies automatically and generates JUnit XML output:

```bash
./tests/bash/run-tests.sh --ci
```

### Get Help

```bash
./tests/bash/run-tests.sh --help
```

## Prerequisites

### Local Development

- Python 3.8+
- Bash 4.0+
- Bats (will be auto-installed if not present)

The test runner will automatically:
- Install Bats if not found (via npm, homebrew, or from source in CI mode)
- Install required Python packages (ansible, ansible-lint, yamllint)
- Install required Ansible collections

### CI/CD

In CI mode (`--ci` flag), the script will:
- Install Bats from GitHub releases
- Generate JUnit XML test results (`test-results.xml`)
- Exit with non-zero status on failures

## Test Organization

Each `.bats` file contains multiple test cases following this pattern:

```bash
#!/usr/bin/env bats

setup() {
    # Runs before each test
    REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    export REPO_ROOT
}

@test "descriptive test name" {
    # Test commands
    run command_to_test
    [ "$status" -eq 0 ]
}
```

## Test Categories

### Linting Tests (`lint-test.bats`)

Validates code quality and style:
- yamllint checks on YAML files
- ansible-lint checks on Ansible roles
- Excludes external roles (e.g., geerlingguy.docker)

### Syntax Tests (`syntax-test.bats`)

Validates syntax without execution:
- Ansible playbook syntax
- Shell script syntax (bash and sh)
- Verifies required files exist

### Docker Tests (`docker-test.bats`)

Tests Docker provisioning:
- Ansible can install required collections
- Test inventory can be created
- Playbook passes in check mode
- Docker role can be applied
- Docker is installed and running

### Ansible Pull Tests (`ansible-pull-test.bats`)

Tests ansible-pull functionality:
- ansible-pull script exists and is valid
- ansible-pull can run from local repository
- Inventory files are in correct locations

## CI/CD Integration

### GitHub Actions Workflow

The CI workflow (`.github/workflows/ci.yml`) runs the test suite on:
- Push to `main` or `copilot/**` branches
- Pull requests
- Manual workflow dispatch

Features:
- Automatic dependency installation
- Test result publishing
- Test artifacts upload
- Parallel execution support

### Test Results

Test results are published using the `EnricoMi/publish-unit-test-result-action` which provides:
- Test summary in PR checks
- Failed test details
- Test trends over time

## Writing New Tests

1. Create a new `.bats` file in `tests/bash/`
2. Add a `setup()` function for test initialization
3. Write test cases using `@test` blocks
4. Use `run` command to capture command output and exit status
5. Make assertions using standard bash test operators

Example:

```bash
#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    export REPO_ROOT
}

@test "my new test" {
    # Run a command
    run echo "hello world"
    
    # Assert exit status
    [ "$status" -eq 0 ]
    
    # Assert output content
    [[ "$output" =~ "hello" ]]
}

@test "test with skip condition" {
    if [ ! -f /some/optional/file ]; then
        skip "Optional file not present"
    fi
    
    run cat /some/optional/file
    [ "$status" -eq 0 ]
}
```

## Best Practices

1. **Use descriptive test names**: Make it clear what is being tested
2. **Use `skip` for conditional tests**: Don't fail tests for missing optional dependencies
3. **Clean up after tests**: Remove temporary files and directories
4. **Test in isolation**: Each test should be independent
5. **Use setup/teardown**: Initialize test environment properly
6. **Handle CI differences**: Some tests may need to skip in CI environments

## Troubleshooting

### Bats Not Found

The test runner will attempt to install Bats automatically. If this fails:

- **macOS**: `brew install bats-core`
- **Ubuntu/Debian**: `sudo apt-get install bats`
- **npm**: `npm install -g bats`
- **Manual**: See [Bats installation guide](https://github.com/bats-core/bats-core#installation)

### Tests Fail Locally But Pass in CI

This usually indicates environment differences. Common causes:
- Missing system packages
- Different Python/Ansible versions
- File permissions issues
- sudo configuration differences

### Linting Errors

Run linting tests individually to see specific errors:

```bash
./tests/bash/run-tests.sh --test lint-test.bats
```

Fix yamllint errors in your YAML files according to the [yamllint rules](https://yamllint.readthedocs.io/).

Fix ansible-lint errors according to [Ansible best practices](https://docs.ansible.com/ansible/latest/tips_tricks/ansible_tips_tricks.html).

## References

- [Bats Documentation](https://bats-core.readthedocs.io/)
- [Ansible Documentation](https://docs.ansible.com/)
- [yamllint Documentation](https://yamllint.readthedocs.io/)
- [ansible-lint Documentation](https://ansible-lint.readthedocs.io/)
