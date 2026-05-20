require File.expand_path('../../test_helper', __FILE__)

class ForgejoWebhookControllerTest < Redmine::ControllerTest
  tests ForgejoWebhookController
  fixtures :projects, :issues, :issue_categories, :users, :email_addresses,
           :roles, :members, :member_roles, :issue_statuses, :enumerations,
           :trackers, :enabled_modules, :workflows

  def setup
    Setting.plugin_redmine_forgejo_webhook = {
      'secret_token' => '',
      'auto_close_issues' => true,
      'auto_reopen_issues' => false
    }
    Setting.text_formatting = 'markdown'
  end

  def push_payload
    JSON.parse(File.read(Rails.root.join('plugins/redmine_forgejo_webhook/test/fixtures/forgejo_webhook/push_payload.json')))
  end

  def test_push_attributes_journal_to_matched_user_with_full_message
    @request.headers['Content-Type'] = 'application/json'
    @request.headers['X-Gitea-Event'] = 'push'

    assert_difference 'Issue.find(1).journals.count', 1 do
      post :create, body: push_payload.to_json
    end

    journal = Issue.find(1).journals.last
    assert_equal User.find(2), journal.user, 'journal author should be jsmith'
    assert_includes journal.notes, '> Long body explaining the change.'
    assert_includes journal.notes, '> Second line of body.'
    assert_includes journal.notes, 'Author: John Smith <jsmith@somenet.foo>'
  end
end
