#!/usr/bin/env bash
# Boot a long-running Redmine (development env) on http://localhost:3000 with
# this plugin mounted, so you can preview rendered journal notes in a browser.
#
# Usage:
#   docker/run-web.sh              # boot Redmine on :3000 (Ctrl-C to stop)
#   docker/run-web.sh shell        # interactive bash in the same image
#   docker/run-web.sh reset        # wipe the persisted dev DB volume
#
# Default Redmine credentials after first boot: admin / admin (Redmine will
# prompt to change the password on first login). A demo project ("demo") with
# one open issue is seeded automatically.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
IMAGE_TAG="redmine-forgejo-webhook-test:latest"
VOLUME="redmine-forgejo-webhook-dev-db"
CONTAINER="redmine-forgejo-webhook-web"
PORT="${PORT:-3000}"

case "${1:-up}" in
  reset)
    docker volume rm "$VOLUME" 2>/dev/null || true
    echo "removed volume: $VOLUME"
    exit 0
    ;;
  shell)
    docker build -f "$SCRIPT_DIR/Dockerfile.test" -t "$IMAGE_TAG" "$SCRIPT_DIR"
    exec docker run --rm -it \
      -v "$PLUGIN_DIR:/plugin:ro" \
      -v "$VOLUME:/redmine/db" \
      -e PLUGIN_NAME=redmine_forgejo_webhook \
      "$IMAGE_TAG" \
      shell
    ;;
  up|"")
    docker build -f "$SCRIPT_DIR/Dockerfile.test" -t "$IMAGE_TAG" "$SCRIPT_DIR"
    exec docker run --rm -it \
      --name "$CONTAINER" \
      -v "$PLUGIN_DIR:/plugin:ro" \
      -v "$VOLUME:/redmine/db" \
      -p "${PORT}:3000" \
      -e PLUGIN_NAME=redmine_forgejo_webhook \
      "$IMAGE_TAG" \
      web
    ;;
  *)
    echo "unknown subcommand: $1" >&2
    echo "usage: $0 [up|shell|reset]" >&2
    exit 2
    ;;
esac
