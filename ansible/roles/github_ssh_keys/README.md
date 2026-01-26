# GitHub SSH Keys Role

This Ansible role automatically fetches and installs public SSH keys from a GitHub user profile.

## Description

The role fetches SSH keys from GitHub's public keys API endpoint (`https://github.com/{username}.keys`) and adds them to a target user's `authorized_keys` file. This is useful for automatically provisioning servers with SSH access based on keys already managed in GitHub.

## Requirements

- Internet connectivity to reach GitHub's API
- Target user must exist on the system
- The GitHub user must have at least one public SSH key uploaded to their profile

## Role Variables

Available variables are listed below, along with default values (see `defaults/main.yml`):

```yaml
# GitHub username to fetch SSH keys from
# REQUIRED: Must be set per-host in inventory or host_vars
github_ssh_keys_username: YourGitHubUsername

# Target user to install SSH keys for (defaults to ansible_user)
github_ssh_keys_target_user: "{{ ansible_user }}"

# Whether to remove other keys (exclusive mode)
github_ssh_keys_exclusive: false
```

## Dependencies

None.

## Example Playbook

```yaml
---
- hosts: servers
  become: true
  roles:
    - role: github_ssh_keys
      github_ssh_keys_username: YourGitHubUsername
```

Or with inventory variables:

```yaml
# In group_vars or host_vars
github_ssh_keys_username: YourGitHubUsername
github_ssh_keys_target_user: ansible
```

## Security Considerations

- **GitHub username is required**: You must explicitly set `github_ssh_keys_username` to your own GitHub username in your host_vars or inventory. The role will fail if this is not configured, preventing unauthorized access.
- **Verify your keys**: Make sure your GitHub account only has the SSH keys you want to use for server access.
- **Exclusive mode**: When `github_ssh_keys_exclusive` is `true`, all other keys will be removed from the user's `authorized_keys` file, including any keys not managed via GitHub (for example, manually installed emergency access keys or the key you originally used to access the server). If that key is not present in the configured GitHub account, enabling exclusive mode can immediately lock you out, especially during unattended `ansible-pull` execution. Only enable exclusive mode after confirming that your GitHub account contains at least one valid key that will continue to provide administrative access.
- **Public information**: Remember that anyone can view your public SSH keys on GitHub at `https://github.com/{username}.keys`.

## Warning Message

If you forget to set `github_ssh_keys_username`, the role will fail with an error message:

```
github_ssh_keys_username is not set. You must configure a GitHub username
in your host_vars or inventory to use this role. Set it to your own GitHub
username to fetch your public SSH keys.
```

## License

MIT

## Author

DevSecNinja
