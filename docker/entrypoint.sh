#!/usr/bin/env bash
set -euo pipefail

PLUGIN_NAME="${PLUGIN_NAME:-redmine_forgejo_webhook}"
PLUGIN_SRC=/plugin
PLUGIN_DST="/redmine/plugins/${PLUGIN_NAME}"

if [ ! -d "$PLUGIN_SRC" ]; then
  echo "Error: plugin source must be bind-mounted at /plugin" >&2
  exit 2
fi

# Link plugin into Redmine's plugins/ tree (idempotent)
mkdir -p /redmine/plugins
ln -sfn "$PLUGIN_SRC" "$PLUGIN_DST"

cd /redmine

# Ensure secret key exists for Rails
if [ -z "${SECRET_KEY_BASE:-}" ]; then
  export SECRET_KEY_BASE="$(bundle exec rake generate_secret_token 2>/dev/null; openssl rand -hex 32)"
fi

# Reset DB on each run for hermetic tests
rm -f db/test.sqlite3
bundle exec rake db:migrate redmine:plugins:migrate RAILS_ENV=test --trace

case "${1:-test}" in
  shell|bash)
    exec bash
    ;;
  test)
    shift
    exec bundle exec rake redmine:plugins:test \
        NAME="$PLUGIN_NAME" \
        RAILS_ENV=test \
        "$@"
    ;;
  *)
    # Default: anything else (e.g. `TEST=...`) is forwarded to the rake task.
    exec bundle exec rake redmine:plugins:test \
        NAME="$PLUGIN_NAME" \
        RAILS_ENV=test \
        "$@"
    ;;
esac
