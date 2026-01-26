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
# IMPORTANT: Change this to your own GitHub username!
github_ssh_keys_username: DevSecNinja

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

- **Always change the default username**: The default username `DevSecNinja` is only for demonstration. Using the default in production would grant access to the wrong person.
- **Verify your keys**: Make sure your GitHub account only has the SSH keys you want to use for server access.
- **Exclusive mode**: When `github_ssh_keys_exclusive` is `true`, all other keys will be removed from the user's `authorized_keys` file.
- **Public information**: Remember that anyone can view your public SSH keys on GitHub at `https://github.com/{username}.keys`.

## Warning Message

If you use the default username (`DevSecNinja`), the role will display a warning message:

```
WARNING: Using default GitHub username 'DevSecNinja'.
For security, you should change 'github_ssh_keys_username' to your own GitHub username
in your host_vars or inventory configuration.
```

## License

MIT

## Author

DevSecNinja
