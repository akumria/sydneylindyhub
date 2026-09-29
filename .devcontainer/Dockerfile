FROM node:22-bookworm AS node

FROM ruby:4.0.7-bookworm

COPY --from=node /usr/local/ /usr/local/

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    build-essential \
    firefox-esr \
    git \
    libpq-dev \
    postgresql-client \
  && rm -rf /var/lib/apt/lists/*

ENV BUNDLE_PATH=/usr/local/bundle

WORKDIR /workspace/sydneylindyhub
