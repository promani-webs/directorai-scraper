# Build stage for Playwright dependencies
FROM ubuntu:22.04 AS playwright-deps
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/browsers
#ENV PLAYWRIGHT_DRIVER_PATH=/opt/
RUN export PATH=$PATH:/usr/local/go/bin:/root/go/bin \
    && apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl wget \
    && wget -q https://go.dev/dl/go1.25.6.linux-amd64.tar.gz \
    && tar -C /usr/local -xzf go1.25.6.linux-amd64.tar.gz \
    && rm go1.25.6.linux-amd64.tar.gz \
    && wget -q https://nodejs.org/dist/v20.18.0/node-v20.18.0-linux-x64.tar.gz \
    && tar -C /usr/local --strip-components=1 -xzf node-v20.18.0-linux-x64.tar.gz \
    && rm node-v20.18.0-linux-x64.tar.gz \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && go install github.com/playwright-community/playwright-go/cmd/playwright@v0.5200.1 \
    && mkdir -p /opt/browsers \
    && playwright install chromium --with-deps

# Build stage
FROM golang:1.25.6-bookworm AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -ldflags="-w -s" -o /usr/bin/google-maps-scraper

# Final stage
FROM ubuntu:22.04
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/browsers
ENV PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1

# Install only the necessary dependencies in a single layer
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    libnss3 \
    libnspr4 \
    libatk1.0-0 \
    libatk-bridge2.0-0 \
    libcups2 \
    libdrm2 \
    libdbus-1-3 \
    libxkbcommon0 \
    libgbm1 \
    libasound2 \
    libpangocairo-1.0-0 \
    libxcomposite1 \
    libxdamage1 \
    libxfixes3 \
    libxrandr2 \
    libxcursor1 \
    libxi6 \
    libxtst6 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY --from=playwright-deps /opt/browsers /opt/browsers
COPY --from=playwright-deps /root/.cache/ms-playwright-go /root/.cache/ms-playwright-go

RUN chmod -R 755 /opt/browsers \
    && chmod -R 755 /root/.cache/ms-playwright-go

COPY --from=builder /usr/bin/google-maps-scraper /usr/bin/

ENTRYPOINT ["google-maps-scraper"]
