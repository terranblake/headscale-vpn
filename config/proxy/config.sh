# Proxy Gateway Configuration

# mitmproxy mode: transparent, regular, upstream
PROXY_MODE=transparent

# Ports
HTTP_PORT=8080
HTTPS_PORT=8443
WEB_UI_PORT=8081

# Logging level: error, warn, info, debug
LOG_LEVEL=info

# Certificate handling
GENERATE_CERTS=true
CERT_DOMAIN=*.local

# Bypass configuration (domains to not proxy)
PROXY_BYPASS_DOMAINS=(
    "*.local"
    "*.internal"
    "localhost"
)

# Traffic filtering
ENABLE_FILTERING=true
BLOCK_ADS=false
BLOCK_TRACKING=false
