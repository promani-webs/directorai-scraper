# Etapa 1: Builder con soporte para Auto-Upgrade de Go
FROM golang:1.24-bookworm AS builder
WORKDIR /app
COPY . .
ENV CGO_ENABLED=0
# ESTA ES LA CLAVE: Permite descargar la versión de Go que pida el go.mod (1.25.x)
ENV GOTOOLCHAIN=auto 
RUN go mod download
RUN go build -ldflags="-w -s" -o /usr/local/bin/google-maps-scraper .

# Etapa 2: Runtime Oficial de Playwright (Estabilidad garantizada)
# Usamos una versión reciente que incluye dependencias de navegador
FROM mcr.microsoft.com/playwright:v1.50.0-jammy

# Instalamos certificados y limpiamos
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && rm -rf /var/lib/apt/lists/*

# Copiamos el binario compilado
COPY --from=builder /usr/local/bin/google-maps-scraper /usr/local/bin/google-maps-scraper

ENTRYPOINT ["google-maps-scraper"]
