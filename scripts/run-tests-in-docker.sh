#!/usr/bin/env bash
# Run Rails tests inside Docker (avoids local Ruby/bundler issues).
# Usage: ./scripts/run-tests-in-docker.sh [test path...]
# Example: ./scripts/run-tests-in-docker.sh test/controllers/images_controller_test.rb
#          ./scripts/run-tests-in-docker.sh   # runs full test suite

set -e
cd "$(dirname "$0")/.."

# Ensure postgres is up
docker compose up -d postgresql

# Compose project network (default: directory name + _default)
NETWORK="${COMPOSE_PROJECT_NAME:-haven}_default"

TEST_ARGS=("$@")

docker run --rm \
  -v "$(pwd)":/app \
  -w /app \
  --network "$NETWORK" \
  -e RAILS_ENV=test \
  -e HAVEN_DB_HOST=postgresql \
  -e PG_USER=haven \
  ruby:3.3.7-slim-bookworm \
  bash -c '
    apt-get update && apt-get install -y --no-install-recommends \
      build-essential pkg-config libpq-dev libyaml-dev libffi-dev libgdbm-dev \
      libsqlite3-dev imagemagick libheif1
    bundle config unset path 2>/dev/null || true
    bundle config set --local without "development"
    bundle install
    bin/rails db:create db:schema:load
    bundle exec rails test "$@"
  ' _ "${TEST_ARGS[@]}"
