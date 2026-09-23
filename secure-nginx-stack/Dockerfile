# syntax=docker/dockerfile:1.7

# Multi-stage, multi-target Dockerfile for the frontend/backend/database demo
# services. Build with --target {frontend,backend,database} to select one.
# Base image is pinned by digest; keep this in sync with compose.yaml.
FROM nginxinc/nginx-unprivileged:1-alpine3.24@sha256:e75f89810bf5bfbcf58a1cfb32a1a11de55b7623d732e67735d513b720d7436a AS base

USER root
# Strip default content/config so nothing unintended is ever served.
RUN rm -rf /usr/share/nginx/html/* /etc/nginx/conf.d/* /docker-entrypoint.d/*
USER 101:101

# ---- frontend --------------------------------------------------------------
FROM base AS frontend
COPY --chown=101:101 --chmod=0444 nginx/frontend.conf /etc/nginx/nginx.conf
COPY --chown=101:101 --chmod=0444 html/ /usr/share/nginx/html/
EXPOSE 8080
HEALTHCHECK --interval=15s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -q -O /dev/null http://127.0.0.1:8080/healthz || exit 1

# ---- backend ----------------------------------------------------------------
FROM base AS backend
COPY --chown=101:101 --chmod=0444 nginx/backend.conf /etc/nginx/nginx.conf
EXPOSE 8080
HEALTHCHECK --interval=15s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -q -O /dev/null http://127.0.0.1:8080/healthz || exit 1

# ---- database (demo only, not a real database) ------------------------------
FROM base AS database
COPY --chown=101:101 --chmod=0444 nginx/database.conf /etc/nginx/nginx.conf
EXPOSE 8080
HEALTHCHECK --interval=15s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -q -O /dev/null http://127.0.0.1:8080/healthz || exit 1
