# Idempotent dev-environment seed for the Forgejo webhook preview instance.
# Creates a public "demo" project containing a single open issue so the plugin
# webhook endpoint has somewhere to attach journal notes.

project = Project.find_or_initialize_by(identifier: 'demo')
if project.new_record?
  project.name = 'Demo'
  project.is_public = true
  project.save!
end

unless project.module_enabled?(:issue_tracking)
  project.enabled_module_names = (project.enabled_module_names | %w[issue_tracking])
end

tracker = Tracker.first
raise 'no Tracker found - did redmine:load_default_data run?' if tracker.nil?
project.trackers << tracker unless project.trackers.include?(tracker)
project.save!

open_status = IssueStatus.where(is_closed: false).order(:position).first
raise 'no open IssueStatus found' if open_status.nil?

unless project.issues.exists?(subject: 'Seed issue for webhook preview')
  Issue.create!(
    project:     project,
    tracker:     tracker,
    author:      User.find(1),
    subject:     'Seed issue for webhook preview',
    description: "Hit `POST /forgejo_webhook?project_id=demo` with a Forgejo " \
                 "push payload referencing this issue (e.g. `refs #" \
                 "#{(Issue.maximum(:id) || 0) + 1}`) to see rendered notes.",
    status:      open_status
  )
end

issue = project.issues.order(:id).first
puts "[seed] project=#{project.identifier} issue=##{issue.id} status=#{issue.status.name}"
