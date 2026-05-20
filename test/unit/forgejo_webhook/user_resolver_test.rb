require File.expand_path('../../../test_helper', __FILE__)

class ForgejoWebhook::UserResolverTest < ActiveSupport::TestCase
  fixtures :users, :email_addresses

  def test_matches_active_user_by_email_case_insensitively
    user = User.find(2) # jsmith — has email jsmith@somenet.foo
    result = ForgejoWebhook::UserResolver.new(
      name: 'John Smith', email: 'JSMITH@somenet.foo', username: nil
    ).call

    assert_equal user, result.user
    assert_nil result.attribution,
               'attribution must be nil when the journal is already attributed to a resolved user'
  end

  def test_returns_anonymous_when_email_blank_and_username_blank
    result = ForgejoWebhook::UserResolver.new(name: 'Jane', email: nil, username: nil).call
    assert_equal User.anonymous, result.user
    assert_equal 'Author: Jane', result.attribution
  end

  def test_falls_through_to_username_when_email_misses
    user = User.find(2) # jsmith
    result = ForgejoWebhook::UserResolver.new(
      name: nil, email: 'unknown@x.com', username: 'JSmith'
    ).call

    assert_equal user, result.user
    assert_nil result.attribution,
               'attribution must be nil when resolved via username fallback'
  end

  def test_skips_locked_user_matched_by_email_and_falls_through
    locked = User.find(3) # dlopper (standard fixtures); has email dlopper@somenet.foo
    locked.update_column(:status, User::STATUS_LOCKED)
    active = User.find(2) # jsmith

    result = ForgejoWebhook::UserResolver.new(
      name: nil, email: locked.mail, username: active.login
    ).call

    assert_equal active, result.user
  end

  def test_returns_anonymous_when_nothing_matches
    result = ForgejoWebhook::UserResolver.new(
      name: 'Ghost', email: 'nobody@nowhere.invalid', username: 'ghost-user'
    ).call

    assert_equal User.anonymous, result.user
    assert_equal 'Author: Ghost <nobody@nowhere.invalid>', result.attribution
  end
end
