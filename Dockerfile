# syntax=docker/dockerfile:1
FROM docker.io/library/node:22-bookworm AS node
FROM docker.io/library/ruby:4.0.7-slim-bookworm AS base
WORKDIR /app
ENV RAILS_ENV=production BUNDLE_DEPLOYMENT=1 BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_WITHOUT=development:test RAILS_LOG_TO_STDOUT=1 PORT=8080
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates libpq5 libyaml-0-2 curl \
    && rm -rf /var/lib/apt/lists/*

FROM base AS build
COPY --from=node /usr/local/ /usr/local/
RUN apt-get update && apt-get install -y --no-install-recommends build-essential libpq-dev libyaml-dev git \
    && rm -rf /var/lib/apt/lists/* \
    && rm -f /usr/local/bin/yarn /usr/local/bin/yarnpkg && corepack enable
COPY Gemfile Gemfile.lock .ruby-version ./
RUN bundle install && rm -rf /usr/local/bundle/cache
COPY package.json yarn.lock .yarnrc.yml ./
ENV PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
RUN corepack install && yarn install --immutable
COPY . .
# Build-only placeholders: no database, credentials, or live services are needed.
ENV CANONICAL_HOST=public.invalid EDITORIAL_HOST=editor.invalid SECRET_KEY_BASE=build-placeholder
RUN bin/rails dartsass:build && yarn build && SKIP_JS_BUILD=true bin/rails assets:precompile

FROM base AS runtime
RUN groupadd --gid 10001 rails && useradd --uid 10001 --gid rails --create-home rails
COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build --chown=rails:rails /app/Gemfile /app/Gemfile.lock /app/.ruby-version /app/Rakefile /app/config.ru ./
COPY --from=build --chown=rails:rails /app/app ./app
COPY --from=build --chown=rails:rails /app/bin ./bin
COPY --from=build --chown=rails:rails /app/config ./config
COPY --from=build --chown=rails:rails /app/db ./db
COPY --from=build --chown=rails:rails /app/lib ./lib
COPY --from=build --chown=rails:rails /app/public ./public
RUN mkdir -p tmp/pids log && chown -R rails:rails tmp log
USER rails
EXPOSE 8080
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]

# Optional batch image: includes the existing export validation and upload tools.
FROM runtime AS publisher
USER root
COPY --from=node /usr/local/ /usr/local/
RUN rm -f /usr/local/bin/yarn /usr/local/bin/yarnpkg && corepack enable
COPY --from=build --chown=rails:rails /app/node_modules /app/node_modules
COPY --from=build --chown=rails:rails /app/package.json /app/yarn.lock /app/.yarnrc.yml ./
COPY --from=build --chown=rails:rails /app/scripts/check-static-site.mjs ./scripts/check-static-site.mjs
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/playwright ASSETS_PRECOMPILED=true
RUN yarn playwright install --with-deps chromium && chmod -R a+rX /opt/playwright
# Wrangler writes project-local temporary files during Pages uploads.
RUN mkdir -p /app/.wrangler && chown -R rails:rails /app/.wrangler
USER rails
CMD ["bin/publish-static-site"]

# The default build is the smaller web image.
FROM runtime AS web
