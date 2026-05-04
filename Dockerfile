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
# ship, so runtime reuses it verbatim (no extra downloads, no apt).
FROM ${PLAYWRIGHT_IMAGE} AS playwright-deps
# MCR Playwright images default to non-root 'pwuser' since ~v1.25.
# Force root so apt-get / writes to /root/.cache/ / /etc/apt work.
USER root
ENV PLAYWRIGHT_BROWSERS_PATH=/ms-playwright
RUN set -eux; \
    printf 'Acquire::Retries "5";\nAcquire::http::Timeout "30";\nAcquire::https::Timeout "30";\nAcquire::ForceIPv4 "true";\n' \
      > /etc/apt/apt.conf.d/99-directorai-resilience

# Descargar el driver oficial de Playwright (zip que incluye binario `node`
# statically linked + carpeta `package/` con la librería).  La estructura
# que espera playwright-go es:
#
#     $HOME/.cache/ms-playwright-go/<VERSION>/
#     ├── node              <- binario node (NO el del sistema)
#     ├── package/          <- librería playwright npm (driver.js, etc.)
#     └── ... (browsers.json, etc.)
#
# El bug del Dockerfile previo era copiar SOLO la librería npm a `package/`
# sin incluir el binario `node`.  Resultado en runtime:
#
#     fork/exec /root/.cache/ms-playwright-go/1.57.0/node:
#         no such file or directory
#
# La forma correcta (la que usa `playwright-go` internamente cuando descarga
# al runtime) es bajar el zip oficial y extraerlo entero.  Lo hacemos en
# build time para que la imagen sea self-contained y no necesite red al
# arrancar el contenedor.
RUN set -eux; \
    DRIVER_VER=1.57.0; \
    DRIVER_DIR=/root/.cache/ms-playwright-go/$DRIVER_VER; \
    apt-get update; \
    apt-get install -y --no-install-recommends curl unzip ca-certificates; \
    rm -rf /var/lib/apt/lists/*; \
    mkdir -p "$DRIVER_DIR"; \
    cd /tmp; \
    # CDN principal de Playwright; mantenemos azureedge.net como mirror
    # de respaldo por si el primario falla en build time.
    for url in \
        "https://cdn.playwright.dev/builds/driver/playwright-${DRIVER_VER}-linux.zip" \
        "https://playwright.azureedge.net/builds/driver/playwright-${DRIVER_VER}-linux.zip"; do \
        if curl -fsSL --retry 5 --retry-delay 3 -o driver.zip "$url"; then break; fi; \
    done; \
    test -s driver.zip; \
    unzip -q driver.zip -d driver-extract; \
    # Tolerar dos layouts del zip:
    #   (A) raíz contiene `playwright/` (versiones antiguas)
    #   (B) los archivos `node`, `package/`, ... están en la raíz directamente
    if [ -d driver-extract/playwright ]; then \
        cp -a driver-extract/playwright/. "$DRIVER_DIR/"; \
    else \
        cp -a driver-extract/. "$DRIVER_DIR/"; \
    fi; \
    # Validación: los dos artefactos críticos deben existir.  Si no,
    # falla el build aquí (mejor que descubrirlo en runtime).
    test -x "$DRIVER_DIR/node"; \
    test -d "$DRIVER_DIR/package"; \
    rm -rf driver.zip driver-extract

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
