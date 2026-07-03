# syntax=docker/dockerfile:1.7
# Base runtime with all Chromium system deps + Playwright driver preinstalled.
# Using MCR image avoids any apt-get update against archive.ubuntu.com,
# which is intermittently unreliable (400 Bad Request / mirror outages).
ARG PLAYWRIGHT_IMAGE=mcr.microsoft.com/playwright:v1.57.0-jammy

# ---------- Builder (Go) ----------
FROM golang:1.26.2-bookworm AS builder
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
# ship, so runtime reuses it verbatim (no network at container start).
#
# playwright-go (v0.57xx) espera EXACTAMENTE esta estructura y ejecuta
# `<DIR>/node <DIR>/package/cli.js ...`:
#
#     $HOME/.cache/ms-playwright-go/<VERSION>/
#     |- node          <- binario node (playwright-go NO usa el del sistema)
#     `- package/      <- paquete npm 'playwright' (incluye cli.js)
#
# IMPORTANTE - por que NO descargamos el zip del driver:
# El zip oficial `playwright-<VER>-linux.zip` DEJO de publicarse a partir de
# 1.57.0 (1.56.0 existe; 1.57.0 da 404 en cdn.playwright.dev, azureedge,
# akamai y verizon - los unicos hosts que usa playwright-go). Por eso el
# metodo `curl` quedo roto sin arreglo posible via URL.
#
# Historial de bugs a NO repetir:
#   - Copiar SOLO `package/` sin `node`  -> runtime: "fork/exec .../node:
#     no such file or directory".
#   - Copiar SOLO `node` sin `package/cli.js` -> playwright-go intenta
#     DESCARGAR el driver (404) y aborta.
# Aqui aportamos AMBOS desde la propia imagen de Playwright (self-contained).
FROM ${PLAYWRIGHT_IMAGE} AS playwright-deps
# MCR Playwright images default to non-root 'pwuser' since ~v1.25.
# Force root so writes to /root/.cache/ work.
USER root
ENV PLAYWRIGHT_BROWSERS_PATH=/ms-playwright \
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1

RUN set -eux; \
    DRIVER_VER=1.57.0; \
    DRIVER_DIR=/root/.cache/ms-playwright-go/$DRIVER_VER; \
    mkdir -p "$DRIVER_DIR"; \
    # 1) package/  (paquete playwright con cli.js). La imagen MCR NO lo trae
    #    preinstalado globalmente, asi que lo instalamos desde npm (sin
    #    descargar navegadores: ya estan en /ms-playwright).
    if [ -d /ms-playwright-node ]; then \
        cp -a /ms-playwright-node "$DRIVER_DIR/package"; \
    elif [ -d "$(npm root -g 2>/dev/null)/playwright" ]; then \
        cp -a "$(npm root -g)/playwright" "$DRIVER_DIR/package"; \
    else \
        npm i -g --silent "playwright@${DRIVER_VER}"; \
        cp -a "$(npm root -g)/playwright" "$DRIVER_DIR/package"; \
    fi; \
    # 2) node  (playwright-go ejecuta <DIR>/node, no el del sistema). Copiamos
    #    el binario node de la propia imagen (compatible con esta version).
    cp "$(command -v node)" "$DRIVER_DIR/node"; \
    chmod +x "$DRIVER_DIR/node"; \
    # 3) Validacion en build (mejor fallar aqui que en runtime).
    test -x "$DRIVER_DIR/node"; \
    test -f "$DRIVER_DIR/package/cli.js"; \
    "$DRIVER_DIR/node" "$DRIVER_DIR/package/cli.js" --version

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
