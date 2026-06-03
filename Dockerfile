# syntax=docker/dockerfile:1
# =============================================================================
# Railway-optimized Dockerfile for hermes-agent
# Bypasses s6-overlay entirely — Railway manages processes itself.
# Based on the upstream NousResearch/hermes-agent Dockerfile with Railway mods.
# =============================================================================

# ---------- Source stages ----------
FROM ghcr.io/astral-sh/uv:0.11.6-python3.13-trixie@sha256:b3c543b6c4f23a5f2df22866bd7857e5d304b67a564f4feab6ac22044dde719b AS uv_source

# Node 22 LTS source stage (bookworm-slim for glibc compat)
FROM node:22-bookworm-slim@sha256:7af03b14a13c8cdd38e45058fd957bf00a72bbe17feac43b1c15a689c029c732 AS node_source

# ---------- Runtime stage ----------
FROM debian:13.4

ENV PYTHONUNBUFFERED=1
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/hermes/.playwright

# ---------- System dependencies ----------
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    ca-certificates curl iputils-ping python3 python-is-python3 ripgrep \
    ffmpeg gcc python3-dev libffi-dev procps git openssh-client \
    docker-cli xz-utils && \
    rm -rf /var/lib/apt/lists/*

# ---------- User setup ----------
RUN useradd -u 10000 -m -d /opt/data hermes

# ---------- uv (Python package manager) ----------
COPY --chmod=0755 --from=uv_source /usr/local/bin/uv /usr/local/bin/uvx /usr/local/bin/

# ---------- Node 22 LTS ----------
COPY --chmod=0755 --from=node_source /usr/local/bin/node /usr/local/bin/
COPY --from=node_source /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/npm
COPY --from=node_source /usr/local/lib/node_modules/corepack /usr/local/lib/node_modules/corepack
RUN ln -sf /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm && \
    ln -sf /usr/local/lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx && \
    ln -sf /usr/local/lib/node_modules/corepack/dist/corepack.js /usr/local/bin/corepack

# ---------- Working directory ----------
WORKDIR /opt/hermes

# ---------- npm dependencies (layer-cached) ----------
COPY package.json package-lock.json ./
COPY web/package.json web/package-lock.json web/
COPY ui-tui/package.json ui-tui/package-lock.json ui-tui/
COPY ui-tui/packages/hermes-ink/ ui-tui/packages/hermes-ink/

ENV npm_config_install_links=false

RUN npm install --prefer-offline --no-audit && \
    npx playwright install --with-deps chromium --only-shell && \
    (cd web && npm install --prefer-offline --no-audit) && \
    (cd ui-tui && npm install --prefer-offline --no-audit) && \
    npm cache clean --force

# ---------- Python dependencies (layer-cached) ----------
COPY pyproject.toml uv.lock ./
RUN touch ./README.md
RUN uv sync --frozen --no-install-project --extra all --extra messaging --extra anthropic --extra bedrock --extra azure-identity

# ---------- Source code ----------
COPY --chown=hermes:hermes . .

# ---------- Build web dashboard and TUI ----------
RUN cd web && npm run build && \
    cd ../ui-tui && npm run build

# ---------- Permissions ----------
# Make install dir world-readable; venv and node_modules need to be
# writable by hermes user for runtime lazy installs.
USER root
RUN chmod -R a+rX /opt/hermes && \
    chown -R hermes:hermes /opt/hermes/.venv /opt/hermes/ui-tui /opt/hermes/node_modules

# ---------- Link hermes-agent itself (editable, no-deps) ----------
RUN uv pip install --no-cache-dir --no-deps -e "."

# ---------- Bake build-time git revision ----------
ARG HERMES_GIT_SHA=
RUN if [ -n "${HERMES_GIT_SHA}" ]; then \
        printf '%s\n' "${HERMES_GIT_SHA}" > /opt/hermes/.hermes_build_sha && \
        chown hermes:hermes /opt/hermes/.hermes_build_sha; \
    fi

# ---------- Runtime environment ----------
ENV HERMES_WEB_DIST=/opt/hermes/hermes_cli/web_dist
ENV HERMES_HOME=/opt/data
ENV PATH="/opt/hermes/bin:/opt/hermes/.venv/bin:/opt/data/.local/bin:${PATH}"

RUN mkdir -p /opt/data

# ---------- Railway entrypoint (bypasses s6-overlay) ----------
# Railway manages processes itself — s6-overlay's /init would conflict.
# This script handles setup + runs gateway directly without supervision tree.
COPY --chmod=0755 docker/railway-entrypoint.sh /opt/hermes/docker/railway-entrypoint.sh
# Backup: ensure execute permission even if BuildKit --chmod didn't work
RUN chmod +x /opt/hermes/docker/railway-entrypoint.sh

ENTRYPOINT ["/opt/hermes/docker/railway-entrypoint.sh"]
CMD []
