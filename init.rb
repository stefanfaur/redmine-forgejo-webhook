Redmine::Plugin.register :redmine_forgejo_webhook do
  name 'Redmine Forgejo/Gitea Webhook'
  author 'vanzhiganov'
  description 'Plugin to receive webhooks from Forgejo/Gitea and update Redmine issues'
  version '0.1.0'
  url 'https://github.com/vanzhiganov/redmine-forgejo-webhook'
  author_url 'https://github.com/vanzhiganov'

  settings default: {
    'secret_token' => '',
    'auto_close_issues' => true,
    'auto_reopen_issues' => false
  }, partial: 'settings/forgejo_webhook_settings'

  project_module :forgejo_webhook do
    permission :manage_forgejo_webhook, { forgejo_webhook: [:settings] }
  end
end
