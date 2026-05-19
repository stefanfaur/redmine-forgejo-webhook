module ForgejoWebhook
  class UserResolver
    Result = Struct.new(:user, :attribution, keyword_init: true)

    def initialize(name:, email:, username:)
      @name = name
      @email = email
      @username = username
    end

    def call
      Result.new(user: lookup || User.anonymous, attribution: build_attribution)
    end

    private

    attr_reader :name, :email, :username

    def lookup
      return nil if email.blank? && username.blank?
      by_email
    end

    def by_email
      return nil if email.blank?
      ea = EmailAddress.find_by(address: email.downcase)
      user = ea&.user
      user if user&.active?
    end

    def build_attribution
      parts = []
      parts << name if name.present?
      parts << "<#{email}>" if email.present?
      return nil if parts.empty?
      "Author: #{parts.join(' ')}"
    end
  end
end
