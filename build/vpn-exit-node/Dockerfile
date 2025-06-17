# VPN Exit Node - Routes mesh traffic through commercial VPN
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
FROM ubuntu:22.04

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    openvpn \
    iptables \
    iproute2 \
    curl \
    wget \
    unzip \
    dnsutils \
    systemd-resolved \
    supervisor \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Copy tailscale binaries from builder
COPY --from=tailscale-builder /src/tailscaled /usr/local/bin/
COPY --from=tailscale-builder /src/tailscale /usr/local/bin/

# Create tailscale user and directories
RUN useradd -r -s /bin/false tailscale
RUN mkdir -p /var/lib/tailscale /var/run/tailscale /etc/tailscale
RUN chown -R tailscale:tailscale /var/lib/tailscale /var/run/tailscale

# Download NordVPN configuration files
RUN mkdir -p /etc/openvpn/nordvpn
RUN wget -qO /tmp/nordvpn.zip https://downloads.nordcdn.com/configs/archives/servers/ovpn.zip
RUN unzip -q /tmp/nordvpn.zip -d /etc/openvpn/nordvpn/
RUN rm /tmp/nordvpn.zip

# Copy configuration files
COPY config/ /etc/vpn-exit/
COPY scripts/ /usr/local/bin/
COPY supervisord.conf /etc/supervisor/conf.d/

# Make scripts executable
RUN chmod +x /usr/local/bin/*.sh

# Set up networking
RUN echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
RUN echo 'net.ipv6.conf.all.forwarding=1' >> /etc/sysctl.conf

# Create bypass configuration
RUN mkdir -p /etc/vpn-bypass

# Expose ports
EXPOSE 41641/udp

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD /usr/local/bin/tailscale status --json | grep -q '"BackendState":"Running"' || exit 1

# Start supervisor
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
