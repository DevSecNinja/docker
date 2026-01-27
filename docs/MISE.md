# mise Configuration

This project uses [mise](https://mise.jdx.dev/) (formerly rtx) for managing tool versions and environment variables.

## What is mise?

mise is a polyglot tool version manager that:
- Manages versions of Python, Node.js, and other tools
- Automatically activates the correct versions when entering the project directory
- Loads environment variables from `.env`
- Replaces tools like asdf, nvm, pyenv, rbenv, etc.

## Quick Start

### Install mise

```bash
# Install mise
curl https://mise.run | sh

# Activate mise in your shell
echo 'eval "$(mise activate bash)"' >> ~/.bashrc  # For bash
echo 'mise activate fish | source' >> ~/.config/fish/config.fish  # For fish
```

Or use Task:

```bash
task install:mise
```

### Install All Tools

```bash
# Using mise directly
mise install

# Or using Task
task install
```

## Configuration Files

- **`.mise.toml`**: Main configuration file defining tools and versions
- **`.tool-versions`**: Alternative format (compatible with asdf)
- **`.env`**: Environment variables loaded automatically by mise

## Managed Tools

This project configures the following tools via mise:

- **Python 3.14**: Main Python version for Ansible and development
- **Task**: Task runner / build tool (installed via `aqua` backend as recommended by [Task docs](https://taskfile.dev/docs/installation#mise))
- **bats**: Testing framework
- **ansible**: Installed via pipx (managed by mise)
- **ansible-lint**: Linting tool for Ansible
- **yamllint**: YAML linting tool

### Why `aqua:go-task/task`?

The Task documentation recommends using the `aqua` or `ubi` backends with mise because they install directly from GitHub releases, ensuring you get the official binaries. This is more reliable than other backends.

## Task Integration

All Task commands automatically work with mise-managed tools. No special configuration needed!

```bash
# These commands will use mise-managed tools
task install
task test
task lint
task ansible:check
```

## Common Commands

### Using mise directly:

```bash
# Install all configured tools
mise install

# List installed tools
mise list

# Check mise health
mise doctor

# Upgrade all tools
mise upgrade

# Show current environment
mise env
```

### Using Task (recommended):

```bash
# Install mise and all tools
task install

# Check mise health
task mise:doctor

# List installed tools
task mise:list

# Upgrade all tools
task mise:upgrade
```

## Troubleshooting

### Tools not found after installation

Make sure mise is activated in your shell:

```bash
# Check if mise is active
which python3  # Should point to mise shims

# Activate mise manually
eval "$(mise activate bash)"  # or your shell
```

### Trust configuration file

If mise warns about trusting the configuration:

```bash
mise trust
# or
task mise:trust
```

### Python packages missing

If Ansible or other Python tools are not found:

```bash
# Reinstall Python tools via mise
mise install pipx:ansible pipx:ansible-lint pipx:yamllint

# Or reinstall via Task
task install:python
```

## Why mise?

Benefits over manual installation:

- ✅ Consistent tool versions across team members
- ✅ Automatic version switching per project
- ✅ No need to install tools system-wide
- ✅ Easy to upgrade all tools at once
- ✅ Environment variables managed alongside tools
- ✅ Works with existing Task workflows

## Migration from Direct Installation

If you previously installed tools directly:

1. Install mise: `task install:mise`
2. Install tools via mise: `mise install`
3. Verify tools work: `task info`
4. (Optional) Uninstall system-wide versions

## Documentation

- mise documentation: https://mise.jdx.dev/
- Task documentation: https://taskfile.dev/
- Project README: [../README.md](../README.md)
