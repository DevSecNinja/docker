# Renovate Troubleshooting

## Known Issues

### Ansible Galaxy HTTP 500 Internal Server Errors

**Issue**: Renovate periodically encounters HTTP 500 (Internal Server Error) when fetching collection versions from the Ansible Galaxy API (https://galaxy.ansible.com).

**Root Cause**: This is a known intermittent issue with Ansible Galaxy service stability. The errors are not caused by configuration issues in this repository but rather by temporary backend failures on Galaxy's infrastructure.

**Collections Affected**:
- `ansible.posix`
- `community.general`
- `community.docker`

**Solution Implemented**:

The `renovate.json` configuration has been enhanced with the following settings to make Renovate more resilient to these temporary API failures:

1. **Host Rules with Error Tolerance** (`abortOnError: false`):
   ```json
   "hostRules": [
     {
       "matchHost": "galaxy.ansible.com",
       "abortOnError": false
     }
   ]
   ```
   This tells Renovate to continue processing other dependencies even when Ansible Galaxy returns 500 errors, preventing complete Renovate run failures.

2. **Stability Days** (`stabilityDays: 3`):
   ```json
   "ansible-galaxy": {
     "stabilityDays": 3
   }
   ```
   This waits for 3 days after a new collection release before considering it for updates, allowing time for:
   - New releases to stabilize on Galaxy's infrastructure
   - Issues with new releases to be discovered
   - Reducing pressure on Galaxy API during high-traffic periods

3. **PR Scheduling**:
   ```json
   "prSchedule": [
     "before 9am on monday"
   ]
   ```
   This limits when Renovate creates pull requests, reducing the frequency of API calls and the impact of temporary failures.

## Monitoring and Next Steps

- **If errors persist**: They will typically resolve themselves when Ansible Galaxy service stabilizes. No action is required from this repository.
- **Manual verification**: You can manually check if collections are accessible:
  ```bash
  curl -s "https://galaxy.ansible.com/api/v3/plugin/ansible/content/published/collections/index/ansible/posix/versions/"
  ```
- **Alternative sources**: If Galaxy is consistently unavailable, consider using a private Ansible Automation Hub or artifact proxy.

## References

- [Renovate Ansible Galaxy Documentation](https://docs.renovatebot.com/modules/manager/ansible-galaxy/)
- [Ansible Galaxy Forum Discussions](https://forum.ansible.com/)
- [Renovate Configuration Options](https://docs.renovatebot.com/configuration-options/)
