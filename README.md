# Redmine Forgejo/Gitea Webhook Plugin

This plugin allows Redmine to receive and process webhooks from Forgejo and Gitea repositories. It automatically updates Redmine issues based on commit messages and pull requests.

## Features

- Receives webhooks from Forgejo/Gitea repositories
- Automatically references issues in commit messages (e.g., `#123`, `refs #123`)
- Automatically closes issues with keywords: `fixes #123`, `closes #123`, `fixed #123`
- Optional: Reopen issues with keyword: `reopen #123`
- Secure webhook verification using secret tokens
- Adds journal entries (comments) to referenced issues with commit information
- Supports project-specific webhooks

## Installation

1. Clone this repository into your Redmine plugins directory:

```bash
cd /path/to/redmine/plugins
git clone https://github.com/stefanfaur/redmine-forgejo-webhook.git redmine_forgejo_webhook
```

2. Restart your Redmine instance:

```bash
# For Passenger
touch /path/to/redmine/tmp/restart.txt

# For other servers, restart the service
systemctl restart redmine
```

3. The plugin should now appear in **Administration → Plugins**

## Configuration

### Redmine Setup

1. Go to **Administration → Plugins**
2. Click **Configure** next to "Redmine Forgejo/Gitea Webhook"
3. Configure the settings:
   - **Secret Token** (optional but recommended): Enter a secret token to verify webhook requests
   - **Automatically close issues**: Enable to close issues when commits contain keywords like "fixes #123"
   - **Automatically reopen issues**: Enable to reopen closed issues when commits contain "reopen #123"
4. Note the webhook URL displayed in the settings

### Forgejo/Gitea Setup

1. Go to your repository settings in Forgejo/Gitea
2. Navigate to **Settings → Webhooks**
3. Click **Add Webhook → Gitea** (or Forgejo)
4. Configure the webhook:
   - **Target URL**: `https://your-redmine-instance.com/forgejo/webhook` or `https://your-redmine-instance.com/forgejo/webhook/PROJECT_IDENTIFIER`
   - **HTTP Method**: POST
   - **POST Content Type**: application/json
   - **Secret**: Enter the same secret token you configured in Redmine (if using)
   - **Trigger On**: Select "Push events" (and optionally "Pull request events", "Issue events")
   - **Active**: Check this box
5. Click **Add Webhook**

## Usage

### Referencing Issues in Commits

Simply mention issue numbers in your commit messages:

```bash
git commit -m "Add new feature, refs #123"
```

This will add a comment to issue #123 with the commit information.

### Closing Issues with Commits

Use closing keywords in your commit messages:

```bash
git commit -m "Fix the bug, fixes #123"
git commit -m "Resolve issue, closes #456"
git commit -m "Fixed the problem, fixed #789"
```

These commits will automatically close the referenced issues (if auto-close is enabled).

### Reopening Issues

If enabled, you can reopen issues:

```bash
git commit -m "Revert changes, reopen #123"
```

### Supported Keywords

**For referencing:**
- `#123`
- `refs #123`
- `references #123`

**For closing:**
- `fixes #123`
- `fixed #123`
- `fix #123`
- `closes #123`
- `closed #123`
- `close #123`

**For reopening:**
- `reopen #123`
- `reopens #123`

## Webhook Events

The plugin handles the following webhook events:

- **Push events**: Processes commits and updates referenced issues
- **Pull request events**: Processes PR title and description for issue references
- **Issue events**: Logged for future functionality

## Security

- The plugin supports webhook signature verification using HMAC-SHA256
- Always use HTTPS for webhook URLs in production
- Use a strong, random secret token

## Troubleshooting

### Webhooks not working?

1. Check Redmine logs: `log/production.log`
2. Verify the webhook URL is correct and accessible
3. Check that the secret token matches (if configured)
4. Ensure the Redmine user has permission to update issues
5. Test the webhook in Forgejo/Gitea settings (Recent Deliveries)

### Issues not being updated?

1. Verify issue IDs exist in Redmine
2. Check that commit messages use correct keywords
3. Ensure auto-close/auto-reopen settings are enabled if using those features
4. Check Redmine logs for errors

## Development

To contribute or modify this plugin:

```bash
# Clone the repository
git clone https://github.com/stefanfaur/redmine-forgejo-webhook.git

# Make your changes

# Test in your Redmine instance
# Restart Redmine after changes
```

## License

This plugin is released under the MIT License.

## Author

Created by vanzhiganov

## Support

For issues, questions, or contributions, please visit:
https://github.com/stefanfaur/redmine-forgejo-webhook
