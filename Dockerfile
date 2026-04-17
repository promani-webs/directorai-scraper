# syntax=docker/dockerfile:1.7
# Base runtime with all Chromium system deps + Playwright driver preinstalled.
# Using MCR image avoids any apt-get update against archive.ubuntu.com,
# which is intermittently unreliable (400 Bad Request / mirror outages).
ARG PLAYWRIGHT_IMAGE=mcr.microsoft.com/playwright:v1.52.0-jammy

# ---------- Builder (Go) ----------
FROM golang:1.26.1-bookworm AS builder
WORKDIR /app

# Resiliency for any apt call that may run during builder stage.
RUN set -eux; \
    printf 'Acquire::Retries "5";\nAcquire::http::Timeout "30";\nAcquire::https::Timeout "30";\nAcquire::ForceIPv4 "true";\n' \
      > /etc/apt/apt.conf.d/99-directorai-resilience

COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    go mod download
COPY . .
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 go build -ldflags="-w -s" -o /out/google-maps-scraper

# ---------- Playwright-go driver cache ----------
# Precompute the playwright-go driver cache on the same Playwright base we'll
# ship, so runtime reuses it verbatim (no extra downloads, no apt).
FROM ${PLAYWRIGHT_IMAGE} AS playwright-deps
# MCR Playwright images default to non-root 'pwuser' since ~v1.25.
# Force root so apt-get / writes to /root/.cache/ / /etc/apt work.
USER root
ENV PLAYWRIGHT_BROWSERS_PATH=/ms-playwright
RUN set -eux; \
    printf 'Acquire::Retries "5";\nAcquire::http::Timeout "30";\nAcquire::https::Timeout "30";\nAcquire::ForceIPv4 "true";\n' \
      > /etc/apt/apt.conf.d/99-directorai-resilience

# The MCR Playwright image already ships Node.js + the Playwright CLI and
# Chromium browsers at /ms-playwright. We just need to seed playwright-go's
# own cache location so the Go driver does not re-download anything at runtime.
RUN set -eux; \
    mkdir -p /root/.cache/ms-playwright-go/1.52.0; \
    if [ -d /ms-playwright-node ]; then \
        cp -a /ms-playwright-node /root/.cache/ms-playwright-go/1.52.0/package; \
    elif [ -d "$(npm root -g 2>/dev/null)/playwright" ]; then \
        cp -a "$(npm root -g)/playwright" /root/.cache/ms-playwright-go/1.52.0/package; \
    else \
        npm_root="$(npm root -g)"; \
        mkdir -p "$npm_root"; \
        npm i -g --silent playwright@1.52.0; \
        cp -a "$npm_root/playwright" /root/.cache/ms-playwright-go/1.52.0/package; \
    fi

# ---------- Final runtime ----------
FROM ${PLAYWRIGHT_IMAGE}
# Scraper espera encontrar el driver cache en $HOME/.cache/ms-playwright-go/
# Ejecutamos como root para que /root/.cache/ sea accesible y consistente
# con la ruta donde los copiamos.
USER root
ENV PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 \
    PLAYWRIGHT_BROWSERS_PATH=/ms-playwright \
    HOME=/root

COPY --from=playwright-deps /root/.cache/ms-playwright-go /root/.cache/ms-playwright-go
COPY --from=builder /out/google-maps-scraper /usr/bin/google-maps-scraper

ENTRYPOINT ["google-maps-scraper"]
