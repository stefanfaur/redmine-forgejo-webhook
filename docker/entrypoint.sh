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

MODE="${1:-test}"

case "$MODE" in
  web)
    # Long-running dev instance for browser preview of rendered notes.
    # Persists across container restarts when /redmine/db is volume-mounted.
    export RAILS_ENV=development
    bundle exec rake db:migrate redmine:plugins:migrate RAILS_ENV=development --trace

    # First-boot bootstrap: default data (roles/statuses/trackers/...) plus a
    # demo project + issue. Guarded so subsequent boots are idempotent.
    if [ ! -f db/.seeded ]; then
      bundle exec rake redmine:load_default_data REDMINE_LANG=en RAILS_ENV=development
      bundle exec rails runner /plugin/docker/seed.rb
      touch db/.seeded
    fi

    exec bundle exec rails server -b 0.0.0.0 -p 3000
    ;;
  shell|bash)
    # Hermetic test DB; matches test mode for consistency.
    rm -f db/test.sqlite3
    bundle exec rake db:migrate redmine:plugins:migrate RAILS_ENV=test --trace
    exec bash
    ;;
  test)
    rm -f db/test.sqlite3
    bundle exec rake db:migrate redmine:plugins:migrate RAILS_ENV=test --trace
    shift
    exec bundle exec rake redmine:plugins:test \
        NAME="$PLUGIN_NAME" \
        RAILS_ENV=test \
        "$@"
    ;;
  *)
    # Default: anything else (e.g. `TEST=...`) is forwarded to the rake task.
    rm -f db/test.sqlite3
    bundle exec rake db:migrate redmine:plugins:migrate RAILS_ENV=test --trace
    exec bundle exec rake redmine:plugins:test \
        NAME="$PLUGIN_NAME" \
        RAILS_ENV=test \
        "$@"
    ;;
esac
