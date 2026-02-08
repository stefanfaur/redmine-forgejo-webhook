RedmineApp::Application.routes.draw do
  post 'forgejo/webhook/:project_id', to: 'forgejo_webhook#create', as: 'forgejo_webhook'
  post 'forgejo/webhook', to: 'forgejo_webhook#create'
end
