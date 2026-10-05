FROM node:22-bookworm AS node

FROM ruby:4.0.7-bookworm

COPY --from=node /usr/local/ /usr/local/

# Chromium, which the screenshot harness (scripts/screenshots.mjs) drives, needs
# these; Firefox-esr for the system specs does not.
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    build-essential \
    firefox-esr \
    git \
    libasound2 \
    libdrm2 \
    libgbm1 \
    libpq-dev \
    libwayland-server0 \
    postgresql-client \
  && rm -rf /var/lib/apt/lists/*

ENV BUNDLE_PATH=/usr/local/bundle

# Keep `yarn install` from pulling the ~650MB Chromium download in every
# environment, including CI, which does not run the screenshot harness.
# bin/devcontainer-setup installs the browser explicitly where it is wanted.
ENV PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1

WORKDIR /workspace/sydneylindyhub
