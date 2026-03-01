# -----------------------------------------------------------------------------
# Stage 1: Build gems and precompile assets (full build deps, not in final image)
# -----------------------------------------------------------------------------
FROM ruby:3.3.7-slim-bookworm AS builder
WORKDIR /app

RUN apt-get update -yqq && \
    apt-get install -yqq --no-install-recommends \
        autoconf bison build-essential libssl-dev libyaml-dev libreadline6-dev \
        zlib1g-dev libncurses5-dev libffi-dev libgdbm-dev libreadline-dev \
        git libgdbm6 nodejs dirmngr gnupg apt-transport-https ca-certificates npm \
        libpq-dev libsqlite3-dev pkg-config imagemagick && \
    npm install --global yarn && \
    gem update --system && \
    gem update strscan --default && \
    gem install bundler -v 2.4.12 --no-document

ENV RAILS_ENV=production

ADD Gemfile Gemfile.lock Rakefile config.ru .ruby-version ./
RUN bundle config build.bcrypt --use-system-libraries && \
    bundle config set --local deployment 'true' && \
    bundle config set --local without 'development test' && \
    bundle install

# Copy app and precompile assets (done in builder so we don't need node in runtime)
COPY . .
RUN bin/rails assets:precompile

# -----------------------------------------------------------------------------
# Stage 2: Runtime image (slim: no build tools, no nginx, no npm/yarn)
# -----------------------------------------------------------------------------
FROM ruby:3.3.7-slim-bookworm AS runtime
WORKDIR /app

# Runtime-only deps: pg gem needs libpq5, cron for feeds, imagemagick for image_processing
RUN apt-get update -yqq && \
    apt-get install -yqq --no-install-recommends \
        ca-certificates libpq5 cron imagemagick && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

ENV MALLOC_ARENA_MAX='2'
ENV HAVEN_DEPLOY="local"
ENV RAILS_ENV=production
ENV RAILS_SERVE_STATIC_FILES=true

# Copy installed gems from builder
COPY --from=builder /usr/local/bundle /usr/local/bundle

# Copy application and precompiled assets
COPY --from=builder /app /app

# Cron for feed updates
COPY deploymentscripts/lib/docker/feed-fetch-cron /etc/cron.d/feed-fetch-cron
RUN chmod 0644 /etc/cron.d/feed-fetch-cron && \
    crontab /etc/cron.d/feed-fetch-cron && \
    touch /var/log/cron.log

EXPOSE 3000

CMD ["bash", "./bin/docker-start"]
