# syntax=docker/dockerfile:1
# check=error=true

# This Dockerfile is designed for production, not development. Build and run by hand:
# docker build -t waterhole .
# docker run -d -p 80:80 --env-file .env.production -v waterhole_storage:/rails/storage --name waterhole waterhole
# Every setting comes from ENV; see .env.production.sample.

# For a containerized dev environment, see Dev Containers: https://guides.rubyonrails.org/getting_started_with_devcontainer.html

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version
ARG RUBY_VERSION=4.0.10
FROM docker.io/library/ruby:$RUBY_VERSION-alpine AS base

# Rails app lives here
WORKDIR /rails

# Install base packages. icu-data-full carries the CJK/Thai dictionaries that
# ffi-icu's word boundaries need (icu-libs alone pulls only icu-data-en).
# bash for bin/docker-entrypoint. Alpine's tzdata keeps backward links like
# Asia/Calcutta, which is what browsers report.
# No postgresql-client: db:prepare loads db/schema.rb, so nothing runs psql.
RUN apk add --no-cache bash curl icu-libs icu-data-full jemalloc tzdata && \
    ln -s /usr/lib/libjemalloc.so.2 /usr/local/lib/libjemalloc.so

# Set production environment variables and enable jemalloc for reduced memory usage and latency.
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test:assets" \
    LD_PRELOAD="/usr/local/lib/libjemalloc.so"

# Throw-away build stage to reduce size of final image
FROM base AS build

# The build also needs the assets group (Tailwind) for assets:precompile.
ENV BUNDLE_WITHOUT="development:test"

# Install packages needed to build gems. pg normally installs precompiled for
# musl; libpq-dev is there for when it has to compile.
RUN apk add --no-cache build-base git libpq-dev openssl-dev yaml-dev pkgconf

# Install application gems, and precompile bootsnap for the ones the image
# keeps (not the assets group), in a layer cached until Gemfile.lock changes.
COPY Gemfile Gemfile.lock ./

RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    # -j 1 disable parallel compilation to avoid a QEMU bug: https://github.com/rails/bootsnap/issues/495
    BUNDLE_WITHOUT="development:test:assets" bundle exec bootsnap precompile -j 1 --gemfile

# Copy application code
COPY . .

# Precompile bootsnap code for faster boot times.
# -j 1 disable parallel compilation to avoid a QEMU bug: https://github.com/rails/bootsnap/issues/495
RUN bundle exec bootsnap precompile -j 1 app/ lib/

# Precompiling assets for production without requiring secret RAILS_MASTER_KEY.
# Tailwind (the assets group) builds the CSS first; without it the pages would
# ship unstyled, so fail the build. Then drop the assets gems from the image.
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile && \
    { ls public/assets/tailwind-*.css > /dev/null || { echo "Tailwind CSS was not built" >&2; exit 1; }; } && \
    BUNDLE_WITHOUT="development:test:assets" bundle clean --force




# Final stage for app image
FROM base

# Run and own only the runtime files as a non-root user for security
RUN addgroup -S -g 1000 rails && \
    adduser -S -u 1000 -G rails -h /home/rails -s /bin/bash rails
USER 1000:1000

# Copy built artifacts: gems, application
COPY --chown=rails:rails --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --chown=rails:rails --from=build /rails /rails

# The release tag, set by the release workflow; error reports carry it as their
# release. Empty for local builds.
ARG WATERHOLE_VERSION=""
ENV WATERHOLE_VERSION="${WATERHOLE_VERSION}"

# Entrypoint prepares the database.
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

# Start server via Thruster by default, this can be overwritten at runtime
EXPOSE 80
CMD ["./bin/thrust", "./bin/rails", "server"]
