# syntax=docker/dockerfile:1
#
# The whole Roc app: the Joy/WASM frontend bundle and the backend binary that serves it, so one
# container is the app. Build from the repository root:
#
#   docker build -f Dockerfile.app -t school-app .
#   docker run --rm -p 8000:8000 --env-file roc-backend/.env school-app
#
# `devops/docker-compose.yml` builds it as the `app` service.
#
# The compiler is pinned to the nightly this project builds with. Those live in roc-lang/nightlies
# (the older roc-lang/roc nightly tag stopped at a build that predates this compiler, and its
# `-latest` assets are not the new compiler). The asset name drops the tag's `nightly-` prefix.

ARG ROC_TAG=nightly-2026-09-29-7f11a82

# --- build: compiler, frontend bundle, backend binary ---
FROM node:22-bookworm-slim AS build

ARG ROC_TAG
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl \
 && rm -rf /var/lib/apt/lists/*

# Statically linked, so it runs on any base image.
RUN curl -fsSL -o /tmp/roc.tar.gz \
      "https://github.com/roc-lang/nightlies/releases/download/${ROC_TAG}/roc_nightly-linux_x86_64-${ROC_TAG#nightly-}.tar.gz" \
 && mkdir -p /opt/roc \
 && tar -xzf /tmp/roc.tar.gz -C /opt/roc --strip-components=1 \
 && rm /tmp/roc.tar.gz \
 && ln -s /opt/roc/roc /usr/local/bin/roc \
 && roc version

WORKDIR /app
COPY roc-frontend/ ./roc-frontend/
COPY roc-backend/ ./roc-backend/

# dist.css first: Tailwind scans the sources. Then the WASM app (build.roc drops www/app.wasm up
# front and fails if roc does not write it back), then the backend binary.
RUN cd roc-frontend \
 && npm ci --omit=dev --no-audit --no-fund \
 && npx @tailwindcss/cli -i www/app.css -o www/dist.css --minify \
 # The compiler exits 2 when it emitted warnings (the release-bundle platforms trigger many); both
 # 0 and 2 mean the build itself succeeded.
 && (roc run build.roc || [ $? -eq 2 ])
RUN cd roc-backend && (roc build main.roc || [ $? -eq 2 ])

# --- run: the binary and the bundle, nothing else ---
FROM debian:bookworm-slim AS runtime

# ca-certificates for TLS to SurrealDB and Authentik; curl for the healthcheck below.
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=build /app/roc-backend/main /app/main
COPY --from=build /app/roc-frontend/www /app/www

# The binary defaults to loopback, which nothing outside this container can reach.
ENV BIND_HOST=0.0.0.0 \
    STATIC_DIR=/app/www \
    DEV_MODE=false

EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD curl -fsS http://127.0.0.1:8000/health || exit 1

ENTRYPOINT ["/app/main"]
