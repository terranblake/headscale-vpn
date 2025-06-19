FROM python:3.11-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    nmap \
    dnsutils \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies
COPY requirements.txt /tmp/
RUN pip install --no-cache-dir -r /tmp/requirements.txt

# Create app directory
WORKDIR /app

# Copy application files
COPY scripts/ ./scripts/
COPY config/ ./config/

# Create data directory
RUN mkdir -p /data

# Set permissions
RUN chmod +x scripts/*.py

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python scripts/health_check.py

# Run the service discovery daemon
CMD ["python", "scripts/discovery_daemon.py"]