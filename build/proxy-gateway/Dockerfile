# Proxy Gateway - Optional traffic inspection with mitmproxy
# Built from source using open-source tailscaled

FROM golang:1.21-alpine AS tailscale-builder

# Install build dependencies
RUN apk add --no-cache git ca-certificates build-base linux-headers

# Clone and build tailscale from source
WORKDIR /src
RUN git clone https://github.com/tailscale/tailscale.git .
RUN git checkout $(git describe --tags --abbrev=0)  # Use latest stable tag

# Build tailscaled and tailscale CLI
RUN go mod download
RUN CGO_ENABLED=0 go build -ldflags="-s -w -X tailscale.com/version.longStamp=$(git describe --long --abbrev=9 --dirty --always)" -o tailscaled ./cmd/tailscaled
RUN CGO_ENABLED=0 go build -ldflags="-s -w -X tailscale.com/version.longStamp=$(git describe --long --abbrev=9 --dirty --always)" -o tailscale ./cmd/tailscale

# Runtime stage
FROM python:3.11-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    iptables \
    iproute2 \
    curl \
    supervisor \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Copy tailscale binaries from builder
COPY --from=tailscale-builder /src/tailscaled /usr/local/bin/
COPY --from=tailscale-builder /src/tailscale /usr/local/bin/

# Install mitmproxy and dependencies
RUN pip install --no-cache-dir \
    mitmproxy==10.1.5 \
    requests \
    pyyaml \
    dnspython

# Create tailscale user and directories
RUN useradd -r -s /bin/false tailscale
RUN mkdir -p /var/lib/tailscale /var/run/tailscale /etc/tailscale
RUN chown -R tailscale:tailscale /var/lib/tailscale /var/run/tailscale

# Create mitmproxy directories
RUN mkdir -p /root/.mitmproxy /var/log/mitmproxy

# Copy configuration files
COPY config/ /etc/proxy-config/
COPY scripts/ /usr/local/bin/
COPY supervisord.conf /etc/supervisor/conf.d/

# Make scripts executable
RUN chmod +x /usr/local/bin/*.sh

# Expose ports
EXPOSE 8080 8443

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD /usr/local/bin/tailscale status --json | grep -q '"BackendState":"Running"' || exit 1

# Start supervisor
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
