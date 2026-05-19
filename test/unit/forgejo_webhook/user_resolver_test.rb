require File.expand_path('../../../test_helper', __FILE__)

class ForgejoWebhook::UserResolverTest < ActiveSupport::TestCase
  fixtures :users, :email_addresses

  def test_matches_active_user_by_email_case_insensitively
    user = User.find(2) # jsmith — has email jsmith@somenet.foo
    result = ForgejoWebhook::UserResolver.new(
      name: 'John Smith', email: 'JSMITH@somenet.foo', username: nil
    ).call

    assert_equal user, result.user
    assert_equal 'Author: John Smith <JSMITH@somenet.foo>', result.attribution
  end

  def test_returns_anonymous_when_email_blank_and_username_blank
    result = ForgejoWebhook::UserResolver.new(name: 'Jane', email: nil, username: nil).call
    assert_equal User.anonymous, result.user
    assert_equal 'Author: Jane', result.attribution
  end
end
