class ForgejoWebhookController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :check_if_login_required
  
  before_action :verify_signature
  before_action :find_project

  def create
    payload = JSON.parse(request.body.read)
    event_type = request.headers['X-Gitea-Event'] || request.headers['X-Forgejo-Event']
    
    case event_type
    when 'push'
      handle_push_event(payload)
    when 'pull_request'
      handle_pull_request_event(payload)
    when 'issues'
      handle_issues_event(payload)
    else
      Rails.logger.info "Forgejo Webhook: Unhandled event type: #{event_type}"
    end
    
    render json: { status: 'ok' }, status: :ok
  rescue JSON::ParserError => e
    Rails.logger.error "Forgejo Webhook: JSON parsing error: #{e.message}"
    render json: { error: 'Invalid JSON' }, status: :bad_request
  rescue => e
    Rails.logger.error "Forgejo Webhook: Error processing webhook: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    render json: { error: 'Internal server error' }, status: :internal_server_error
  end

  private

  def verify_signature
    secret = Setting.plugin_redmine_forgejo_webhook['secret_token']
    return if secret.blank?

    signature = request.headers['X-Gitea-Signature'] || request.headers['X-Forgejo-Signature']
    
    if signature.blank?
      Rails.logger.warn "Forgejo Webhook: Missing signature"
      render json: { error: 'Unauthorized' }, status: :unauthorized
      return
    end

    body = request.body.read
    request.body.rewind
    
    expected_signature = OpenSSL::HMAC.hexdigest('SHA256', secret, body)
    
    unless Rack::Utils.secure_compare(signature, expected_signature)
      Rails.logger.warn "Forgejo Webhook: Invalid signature"
      render json: { error: 'Unauthorized' }, status: :unauthorized
    end
  end

  def find_project
    if params[:project_id].present?
      @project = Project.find_by(identifier: params[:project_id])
      unless @project
        Rails.logger.warn "Forgejo Webhook: Project not found: #{params[:project_id]}"
        render json: { error: 'Project not found' }, status: :not_found
      end
    end
  end

  def handle_push_event(payload)
    repository_name = payload.dig('repository', 'name')
    commits = payload['commits'] || []

    commits.each do |commit|
      process_commit_message(commit['message'], commit, actor_from(commit['author']))
    end

    Rails.logger.info "Forgejo Webhook: Processed push event for #{repository_name} with #{commits.size} commits"
  end

  def handle_pull_request_event(payload)
    action = payload['action']
    pr = payload['pull_request']
    pr_number = pr['number']
    title = pr['title']
    body = pr['body']

    Rails.logger.info "Forgejo Webhook: Pull request #{action}: ##{pr_number} - #{title}"

    # Process PR title and body for issue references
    # TODO(task-8): wire PR sender as actor via pull_request.user
    process_commit_message(title, pr, {})
    process_commit_message(body, pr, {}) if body.present?
  end

  def handle_issues_event(payload)
    action = payload['action']
    issue = payload['issue']
    issue_number = issue['number']
    title = issue['title']

    Rails.logger.info "Forgejo Webhook: Issue #{action}: ##{issue_number} - #{title}"
  end

  def actor_from(hash)
    return {} unless hash.is_a?(Hash)
    { name: hash['name'], email: hash['email'], username: hash['username'] }
  end

  def process_commit_message(message, commit_data, actor)
    return if message.blank?

    issue_pattern = /(?:refs?|references?|fixes?|fixed|close[sd]?)\s*#(\d+)/i
    simple_pattern = /#(\d+)/

    issue_ids = []
    message.scan(issue_pattern) { |m| issue_ids << m[0].to_i }
    message.scan(simple_pattern) { |m| issue_ids << m[0].to_i } if issue_ids.empty?

    issue_ids.uniq.each { |id| update_issue(id, message, commit_data, actor) }
  end

  def update_issue(issue_id, message, commit_data, actor)
    issue = Issue.find_by(id: issue_id)
    unless issue
      Rails.logger.warn "Forgejo Webhook: Issue ##{issue_id} not found"
      return
    end

    if @project && issue.project_id != @project.id
      Rails.logger.warn "Forgejo Webhook: Issue ##{issue_id} not in project #{@project.identifier}"
      return
    end

    resolved = ForgejoWebhook::UserResolver.new(
      name: actor[:name], email: actor[:email], username: actor[:username]
    ).call
    notes = ForgejoWebhook::NoteBuilder.new(message, commit_data, resolved.attribution).call

    save_with_fallback(issue_id, notes, resolved.user, message)
  end

  def save_with_fallback(issue_id, notes, user, message)
    return true if attempt(Issue.find(issue_id), user, notes, message)

    # Re-fetch a clean Issue object — init_journal uses @current_journal ||= ...
    # so retrying on the same instance would reuse the failed journal.
    attempt(Issue.find(issue_id), User.anonymous, notes, message)
  end

  def attempt(issue, user, notes, message)
    issue.init_journal(user, notes)
    apply_status_change(issue, message)
    return true if issue.save

    Rails.logger.warn "Forgejo Webhook: save as #{user.login.presence || 'anonymous'} failed: #{issue.errors.full_messages.join(', ')}"
    false
  rescue ActiveRecord::ActiveRecordError => e
    Rails.logger.error "Forgejo Webhook: save raised #{e.class}: #{e.message}"
    false
  end

  def apply_status_change(issue, message)
    if should_close_issue?(message) && !issue.status.is_closed
      close_issue(issue)
    elsif should_reopen_issue?(message) && issue.status.is_closed
      reopen_issue(issue)
    end
  end

  def should_close_issue?(message)
    return false unless Setting.plugin_redmine_forgejo_webhook['auto_close_issues']
    message =~ /(?:fixes?|fixed|close[sd]?)\s*#\d+/i
  end

  def should_reopen_issue?(message)
    return false unless Setting.plugin_redmine_forgejo_webhook['auto_reopen_issues']
    message =~ /(?:reopen[s]?)\s*#\d+/i
  end

  def close_issue(issue)
    closed_status = IssueStatus.where(is_closed: true).first
    if closed_status
      issue.status = closed_status
      Rails.logger.info "Forgejo Webhook: Closing issue ##{issue.id}"
    end
  end

  def reopen_issue(issue)
    open_status = IssueStatus.where(is_closed: false).first
    if open_status
      issue.status = open_status
      Rails.logger.info "Forgejo Webhook: Reopening issue ##{issue.id}"
    end
  end
end
