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
      message = commit['message']
      process_commit_message(message, commit)
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
    process_commit_message(title, pr)
    process_commit_message(body, pr) if body.present?
  end

  def handle_issues_event(payload)
    action = payload['action']
    issue = payload['issue']
    issue_number = issue['number']
    title = issue['title']
    
    Rails.logger.info "Forgejo Webhook: Issue #{action}: ##{issue_number} - #{title}"
  end

  def process_commit_message(message, commit_data)
    # Find issue references in commit message (e.g., #123, refs #123, fixes #123)
    issue_pattern = /(?:refs?|references?|fixes?|fixed|close[sd]?)\s*#(\d+)/i
    simple_pattern = /#(\d+)/
    
    issue_ids = []
    
    # Look for keyword references first
    message.scan(issue_pattern) do |match|
      issue_ids << match[0].to_i
    end
    
    # If no keyword references found, look for simple #123 references
    if issue_ids.empty?
      message.scan(simple_pattern) do |match|
        issue_ids << match[0].to_i
      end
    end
    
    issue_ids.uniq.each do |issue_id|
      update_issue(issue_id, message, commit_data)
    end
  end

  def update_issue(issue_id, message, commit_data)
    issue = Issue.find_by(id: issue_id)
    
    unless issue
      Rails.logger.warn "Forgejo Webhook: Issue ##{issue_id} not found"
      return
    end
    
    # Check project scope if specified
    if @project && issue.project_id != @project.id
      Rails.logger.warn "Forgejo Webhook: Issue ##{issue_id} not in project #{@project.identifier}"
      return
    end
    
    # Create a journal entry (comment) on the issue
    journal = issue.init_journal(User.anonymous, create_journal_notes(message, commit_data))
    
    # Check if we should close or reopen the issue
    if should_close_issue?(message)
      close_issue(issue) if issue.status.is_closed == false
    elsif should_reopen_issue?(message)
      reopen_issue(issue) if issue.status.is_closed == true
    end
    
    if issue.save
      Rails.logger.info "Forgejo Webhook: Updated issue ##{issue_id}"
    else
      Rails.logger.error "Forgejo Webhook: Failed to update issue ##{issue_id}: #{issue.errors.full_messages.join(', ')}"
    end
  rescue => e
    Rails.logger.error "Forgejo Webhook: Error updating issue ##{issue_id}: #{e.message}"
  end

  def create_journal_notes(message, commit_data)
    notes = "Commit referenced this issue"
    
    if commit_data['sha'] || commit_data['id']
      sha = commit_data['sha'] || commit_data['id']
      short_sha = sha[0..7]
      notes += ": @#{short_sha}@"
    end
    
    if commit_data['url']
      notes += "\n\n#{commit_data['url']}"
    end
    
    if message.present?
      # Limit message length in notes
      commit_msg = message.lines.first&.strip || message
      commit_msg = commit_msg[0..200] + '...' if commit_msg.length > 200
      notes += "\n\n> #{commit_msg}"
    end
    
    notes
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
