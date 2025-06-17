#!/bin/bash
# Start mitmproxy for traffic inspection

set -e

echo "Starting mitmproxy..."

# Configuration
MITMPROXY_MODE=${MITMPROXY_MODE:-transparent}
MITMPROXY_PORT=${MITMPROXY_PORT:-8080}
WEB_PORT=8081

# Create mitmproxy configuration
cat > /root/.mitmproxy/config.yaml << EOF
# mitmproxy configuration
web_port: ${WEB_PORT}
listen_port: ${MITMPROXY_PORT}
mode: ${MITMPROXY_MODE}

# Logging
confdir: /root/.mitmproxy
flow_detail: 2

# SSL/TLS
ssl_insecure: true
certs:
  - /root/.mitmproxy/mitmproxy-ca-cert.pem

# Scripts and addons
scripts:
  - /etc/proxy-config/logging_addon.py
  - /etc/proxy-config/bypass_addon.py
EOF

# Create logging addon
cat > /etc/proxy-config/logging_addon.py << 'EOF'
"""
Enhanced logging addon for mitmproxy
"""
import logging
from mitmproxy import http
from mitmproxy import ctx

class RequestLogger:
    def request(self, flow: http.HTTPFlow) -> None:
        """Log all HTTP requests"""
        ctx.log.info(f"Request: {flow.request.method} {flow.request.pretty_url}")
        
        # Log headers for debugging
        for header, value in flow.request.headers.items():
            ctx.log.debug(f"  {header}: {value}")
    
    def response(self, flow: http.HTTPFlow) -> None:
        """Log HTTP responses"""
        if flow.response:
            ctx.log.info(f"Response: {flow.response.status_code} for {flow.request.pretty_url}")

addons = [RequestLogger()]
EOF

# Create bypass addon
cat > /etc/proxy-config/bypass_addon.py << 'EOF'
"""
Bypass addon for direct connections
"""
import re
from mitmproxy import http
from mitmproxy import ctx

class BypassFilter:
    def __init__(self):
        # Load bypass patterns from environment
        import os
        bypass_domains = os.getenv('BYPASS_DOMAINS', '').split(',')
        self.bypass_patterns = [
            re.compile(domain.strip().replace('*', '.*'))
            for domain in bypass_domains if domain.strip()
        ]
    
    def request(self, flow: http.HTTPFlow) -> None:
        """Check if request should bypass proxy"""
        host = flow.request.pretty_host
        
        for pattern in self.bypass_patterns:
            if pattern.match(host):
                ctx.log.info(f"Bypassing proxy for {host}")
                # Mark for direct connection
                flow.request.headers["X-Proxy-Bypass"] = "true"
                return

addons = [BypassFilter()]
EOF

# Start mitmproxy based on mode
case "$MITMPROXY_MODE" in
    transparent)
        echo "Starting mitmproxy in transparent mode"
        exec mitmdump \
            --mode transparent \
            --listen-port "$MITMPROXY_PORT" \
            --web-port "$WEB_PORT" \
            --set confdir=/root/.mitmproxy \
            --scripts /etc/proxy-config/logging_addon.py \
            --scripts /etc/proxy-config/bypass_addon.py
        ;;
    regular)
        echo "Starting mitmproxy in regular proxy mode"
        exec mitmdump \
            --mode regular \
            --listen-port "$MITMPROXY_PORT" \
            --web-port "$WEB_PORT" \
            --set confdir=/root/.mitmproxy \
            --scripts /etc/proxy-config/logging_addon.py \
            --scripts /etc/proxy-config/bypass_addon.py
        ;;
    upstream)
        echo "Starting mitmproxy in upstream mode"
        exec mitmdump \
            --mode "upstream:http://proxy-upstream:8080" \
            --listen-port "$MITMPROXY_PORT" \
            --web-port "$WEB_PORT" \
            --set confdir=/root/.mitmproxy \
            --scripts /etc/proxy-config/logging_addon.py \
            --scripts /etc/proxy-config/bypass_addon.py
        ;;
    *)
        echo "Unknown mitmproxy mode: $MITMPROXY_MODE"
        exit 1
        ;;
esac
