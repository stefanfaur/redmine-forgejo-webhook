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

  def test_multi_author_push_creates_one_journal_per_commit_with_correct_authors
    payload = JSON.parse(File.read(Rails.root.join('plugins/redmine_forgejo_webhook/test/fixtures/forgejo_webhook/push_multi_author.json')))

    assert_difference 'Issue.find(1).journals.count', 2 do
      @request.headers['Content-Type'] = 'application/json'
      @request.headers['X-Gitea-Event'] = 'push'
      post :create, body: payload.to_json
    end

    last_two = Issue.find(1).journals.last(2)

    jsmith_journal = last_two.find { |j| j.user_id == 2 }
    dlopper_journal = last_two.find { |j| j.user_id == 3 }

    refute_nil jsmith_journal, 'jsmith should have a journal'
    refute_nil dlopper_journal, 'dlopper should have a journal'

    assert_includes jsmith_journal.notes, 'Author: John Smith <jsmith@somenet.foo>'
    assert_includes dlopper_journal.notes, 'Author: Dave Lopper <dlopper@somenet.foo>'
  end

  def test_falls_back_to_anonymous_when_resolved_user_save_fails
    # Make the first save attempt fail so the controller retries as anonymous.
    # We monkey-patch Issue#save to fail the first call and then restore the
    # original method so the anonymous retry actually persists the journal.
    Issue.class_eval do
      alias_method :__orig_save_for_fallback_test, :save
      @@__fallback_test_calls = 0
      def save(*args, **kwargs)
        @@__fallback_test_calls += 1
        return false if @@__fallback_test_calls == 1
        __orig_save_for_fallback_test(*args, **kwargs)
      end
    end

    begin
      @request.headers['Content-Type'] = 'application/json'
      @request.headers['X-Gitea-Event'] = 'push'

      assert_difference 'Issue.find(1).journals.count', 1 do
        post :create, body: push_payload.to_json
      end

      journal = Issue.find(1).journals.last
      assert_equal User.anonymous, journal.user
      assert_equal 2, self.class.class_variable_get(:@@__fallback_test_calls),
                   'expected exactly 2 Issue#save invocations (1 failed + 1 anonymous retry)'
    ensure
      Issue.class_eval do
        remove_method :save
        alias_method :save, :__orig_save_for_fallback_test
        remove_method :__orig_save_for_fallback_test
      end
    end
  end
end
