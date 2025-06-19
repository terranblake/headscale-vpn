FROM python:3.11-slim

# Install system dependencies for bridge functionality
RUN apt-get update && apt-get install -y \
    hostapd \
    dnsmasq \
    iptables \
    iproute2 \
    curl \
    avahi-daemon \
    avahi-utils \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies
COPY requirements.txt /tmp/
RUN pip install --no-cache-dir -r /tmp/requirements.txt

# Create app directory
WORKDIR /app

# Copy application files
COPY scripts/ ./scripts/
COPY config/ ./config/

# Create necessary directories
RUN mkdir -p /var/lib/dnsmasq /var/log /etc/hostapd

# Set permissions
RUN chmod +x scripts/*.py scripts/*.sh

# Expose ports for bridge services
EXPOSE 53/udp 67/udp 8080 80 443

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python scripts/health_check.py

# Start the TV bridge services
CMD ["./scripts/start-tv-bridge.sh"]