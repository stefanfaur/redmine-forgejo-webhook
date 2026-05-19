#!/usr/bin/env bash
# Build (cached) and run the plugin's tests inside a disposable Redmine container.
#
# Usage:
#   docker/run-tests.sh                # all tests
#   docker/run-tests.sh TEST=plugins/redmine_forgejo_webhook/test/unit/forgejo_webhook/user_resolver_test.rb
#   docker/run-tests.sh shell          # interactive bash in the test container
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
IMAGE_TAG="redmine-forgejo-webhook-test:latest"

docker build \
  -f "$SCRIPT_DIR/Dockerfile.test" \
  -t "$IMAGE_TAG" \
  "$SCRIPT_DIR"

docker run --rm \
  -v "$PLUGIN_DIR:/plugin:ro" \
  -e PLUGIN_NAME=redmine_forgejo_webhook \
  "$IMAGE_TAG" \
  "$@"
