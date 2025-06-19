# Configuration Guide
## Complete Configuration Reference for Family Network Platform

### 🎯 Configuration Overview

This guide provides detailed configuration instructions for all components of the family network platform, from VPN server setup to service configuration.

---

## 🔧 Headscale Configuration

### Core Server Configuration
```yaml
# config/headscale.yaml

# Server settings
server_url: https://vpn.yourdomain.com:8080
listen_addr: 0.0.0.0:8080
metrics_listen_addr: 0.0.0.0:9090
grpc_listen_addr: 0.0.0.0:50443

# Database configuration
db_type: postgres
db_host: postgres
db_port: 5432
db_name: headscale
db_user: headscale
db_pass: your_secure_password

# Logging
log_level: info
disable_check_updates: true

# Private key for signing
private_key_path: /etc/headscale/private.key

# Noise protocol settings
noise:
  private_key_path: /etc/headscale/noise_private.key

# Prefixes for IP allocation
ip_prefixes:
  - fd7a:115c:a1e0::/48
  - 100.64.0.0/10

# Derp configuration
derp:
  server:
    enabled: false
  urls:
    - https://controlplane.tailscale.com/derpmap/default
  auto_update_enabled: true
  update_frequency: 24h
```

### DNS Configuration
```yaml
# DNS settings in headscale.yaml
dns_config:
  magic_dns: true
  base_domain: family.local
  nameservers:
    - 1.1.1.1
    - 8.8.8.8
  search_domains:
    - family.local
  extra_records:
    # Core services
    - name: streamyfin.family.local
      type: A
      value: "192.168.1.100"
    - name: photos.family.local
      type: A
      value: "192.168.1.101"
    - name: docs.family.local
      type: A
      value: "192.168.1.102"
    
    # Wildcard support (if DNS server supports it)
    - name: "*.family.local"
      type: A
      value: "192.168.1.1"  # Router/reverse proxy IP
```

### ACL Configuration
```yaml
# Access Control Lists
acls:
  - action: accept
    src:
      - "group:family"
    dst:
      - "192.168.1.0/24:*"
      - "group:servers:*"

groups:
  group:family:
    - "tag:family-member"
  group:servers:
    - "tag:home-server"

tagOwners:
  tag:family-member:
    - "autogroup:admin"
  tag:home-server:
    - "autogroup:admin"

# SSH access rules
ssh:
  - action: accept
    src:
      - "autogroup:admin"
    dst:
      - "autogroup:self"
    users:
      - "autogroup:nonroot"
```

---

## 🐳 Docker Compose Configuration

### Main Services Stack
```yaml
# docker-compose.yml
version: '3.8'

services:
  # Database
  postgres:
    image: postgres:15-alpine
    environment:
      POSTGRES_DB: ${POSTGRES_DB}
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    volumes:
      - postgres_data:/var/lib/postgresql/data
    networks:
      - headscale-net
    restart: unless-stopped

  # VPN Server
  headscale:
    image: headscale/headscale:latest
    command: headscale serve
    volumes:
      - ./config:/etc/headscale:ro
      - headscale_data:/var/lib/headscale
    ports:
      - "8080:8080"
      - "9090:9090"
      - "50443:50443"
    depends_on:
      - postgres
    networks:
      - headscale-net
    restart: unless-stopped
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.headscale.rule=Host(`vpn.${DOMAIN}`)"
      - "traefik.http.routers.headscale.tls.certresolver=letsencrypt"

  # Reverse Proxy
  traefik:
    image: traefik:v3.0
    command:
      - "--api.dashboard=true"
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      - "--certificatesresolvers.letsencrypt.acme.email=${ACME_EMAIL}"
      - "--certificatesresolvers.letsencrypt.acme.storage=/acme.json"
      - "--certificatesresolvers.letsencrypt.acme.httpchallenge.entrypoint=web"
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - traefik_acme:/acme.json
    networks:
      - headscale-net
    restart: unless-stopped

  # Media Server
  streamyfin:
    image: jellyfin/jellyfin:latest
    environment:
      - JELLYFIN_PublishedServerUrl=https://streamyfin.${DOMAIN}
    volumes:
      - streamyfin_config:/config
      - streamyfin_cache:/cache
      - ${MEDIA_PATH}:/media:ro
    networks:
      - headscale-net
    restart: unless-stopped
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.streamyfin.rule=Host(`streamyfin.${DOMAIN}`)"
      - "traefik.http.routers.streamyfin.tls.certresolver=letsencrypt"

volumes:
  postgres_data:
  headscale_data:
  traefik_acme:
  streamyfin_config:
  streamyfin_cache:

networks:
  headscale-net:
    driver: bridge
```

### Environment Configuration
```env
# .env file
DOMAIN=family.local
EXTERNAL_DOMAIN=yourdomain.com

# Database
POSTGRES_DB=headscale
POSTGRES_USER=headscale
POSTGRES_PASSWORD=your_secure_password_here

# SSL
ACME_EMAIL=your-email@example.com

# Media paths
MEDIA_PATH=/path/to/your/media
PHOTOS_PATH=/path/to/your/photos

# Monitoring
GRAFANA_ADMIN_PASSWORD=your_grafana_password
PROMETHEUS_RETENTION=30d
```

---

## 📱 Client Configuration

### Universal VPN Client Setup
```bash
# For any Tailscale-compatible client:

# 1. Install Tailscale client for your platform
# Android: Google Play Store
# iOS: App Store  
# Windows: tailscale.com/download
# macOS: App Store or tailscale.com/download
# Linux: package manager or tailscale.com/download

# 2. Configure custom coordination server
tailscale up --login-server=https://vpn.yourdomain.com:8080

# 3. Use pre-auth key when prompted
# (Generated by admin using headscale preauthkeys create)
```

### On-Demand VPN Configuration
```json
{
  "name": "Family Services",
  "description": "Automatic VPN for family network access",
  "on_demand_rules": [
    {
      "action": "connect",
      "domains": [
        "*.family.local",
        "*.yourdomain.com"
      ]
    },
    {
      "action": "disconnect",
      "domains": ["*"],
      "except": ["*.family.local", "*.yourdomain.com"]
    }
  ],
  "split_tunneling": {
    "enabled": true,
    "include_routes": [
      "100.64.0.0/10",
      "192.168.1.0/24"
    ]
  }
}
```

### Mobile Configuration Profile Template
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>PayloadContent</key>
    <array>
        <dict>
            <key>PayloadType</key>
            <string>com.apple.vpn.managed</string>
            <key>PayloadIdentifier</key>
            <string>family.vpn.config</string>
            <key>UserDefinedName</key>
            <string>Family Network Access</string>
            <key>OnDemandEnabled</key>
            <integer>1</integer>
            <key>OnDemandRules</key>
            <array>
                <dict>
                    <key>Action</key>
                    <string>Connect</string>
                    <key>DNSDomainMatch</key>
                    <array>
                        <string>*.family.local</string>
                    </array>
                </dict>
                <dict>
                    <key>Action</key>
                    <string>Disconnect</string>
                </dict>
            </array>
        </dict>
    </array>
    <key>PayloadDisplayName</key>
    <string>Family Network Access</string>
    <key>PayloadIdentifier</key>
    <string>family.network.config</string>
    <key>PayloadType</key>
    <string>Configuration</string>
    <key>PayloadVersion</key>
    <integer>1</integer>
</dict>
</plist>
```

---

## 🎬 Service Configuration

### Streamyfin (Jellyfin) Configuration
```json
{
  "ServerName": "Family Media Server",
  "PublicPort": 443,
  "PublicHttpsPort": 443,
  "HttpServerPortNumber": 8096,
  "HttpsPortNumber": 8920,
  "EnableHttps": true,
  "RequireHttps": false,
  "CertificatePath": "/config/ssl/cert.pem",
  "CertificatePassword": "",
  "IsPortAuthorized": true,
  "AutoRunWebApp": true,
  "EnableRemoteAccess": true,
  "BaseUrl": "/",
  "KnownProxies": [
    "traefik"
  ],
  "EnableUPnP": false,
  "EnableMetrics": true
}
```

### Photo Service Configuration
```yaml
# PhotoPrism configuration
services:
  photoprism:
    image: photoprism/photoprism:latest
    environment:
      PHOTOPRISM_ADMIN_PASSWORD: "your_secure_password"
      PHOTOPRISM_SITE_URL: "https://photos.family.local"
      PHOTOPRISM_SITE_TITLE: "Family Photos"
      PHOTOPRISM_SITE_CAPTION: "Browse and share family memories"
      PHOTOPRISM_DATABASE_DRIVER: "mysql"
      PHOTOPRISM_DATABASE_SERVER: "mariadb:3306"
      PHOTOPRISM_DATABASE_NAME: "photoprism"
      PHOTOPRISM_DATABASE_USER: "photoprism"
      PHOTOPRISM_DATABASE_PASSWORD: "your_db_password"
    volumes:
      - "${PHOTOS_PATH}:/photoprism/originals"
      - "photoprism_storage:/photoprism/storage"
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.photos.rule=Host(`photos.family.local`)"
      - "traefik.http.routers.photos.tls.certresolver=letsencrypt"
```

---

## 📊 Monitoring Configuration

### Prometheus Configuration
```yaml
# config/prometheus/prometheus.yml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  - "alert.rules.yml"

scrape_configs:
  - job_name: 'headscale'
    static_configs:
      - targets: ['headscale:9090']
    
  - job_name: 'traefik'
    static_configs:
      - targets: ['traefik:8080']
    
  - job_name: 'node-exporter'
    static_configs:
      - targets: ['node-exporter:9100']

alerting:
  alertmanagers:
    - static_configs:
        - targets:
          - alertmanager:9093
```

### Grafana Dashboard Configuration
```json
{
  "dashboard": {
    "title": "Family Network Overview",
    "panels": [
      {
        "title": "VPN Connections",
        "type": "stat",
        "targets": [
          {
            "expr": "headscale_nodes_total",
            "legendFormat": "Connected Devices"
          }
        ]
      },
      {
        "title": "Service Health",
        "type": "table",
        "targets": [
          {
            "expr": "up{job=~\"headscale|traefik|streamyfin\"}",
            "legendFormat": "{{job}}"
          }
        ]
      }
    ]
  }
}
```

---

## 🔒 Security Configuration

### Firewall Rules
```bash
# UFW firewall configuration
sudo ufw default deny incoming
sudo ufw default allow outgoing

# SSH access
sudo ufw allow ssh

# Web services
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# Headscale
sudo ufw allow 8080/tcp
sudo ufw allow 50443/tcp

# Monitoring (restrict to VPN network)
sudo ufw allow from 100.64.0.0/10 to any port 9090
sudo ufw allow from 100.64.0.0/10 to any port 3000

sudo ufw enable
```

### SSL/TLS Configuration
```yaml
# Traefik TLS configuration
tls:
  options:
    default:
      minVersion: "VersionTLS12"
      cipherSuites:
        - "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384"
        - "TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305"
        - "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256"
      curvePreferences:
        - "CurveP521"
        - "CurveP384"
```

### Backup Configuration
```bash
#!/bin/bash
# Backup script configuration

BACKUP_DIR="/backup/$(date +%Y%m%d_%H%M%S)"
RETENTION_DAYS=30

# What to backup
BACKUP_ITEMS=(
    "/opt/headscale-vpn/config"
    "/opt/headscale-vpn/data"
    "/opt/headscale-vpn/.env"
    "/opt/headscale-vpn/docker-compose.yml"
)

# Database backup
DB_BACKUP_CMD="docker exec postgres pg_dump -U headscale headscale"

# Encryption key for backups
BACKUP_ENCRYPTION_KEY="/etc/backup/encryption.key"
```

---

## 🔧 Advanced Configuration

### Custom Domain Setup
```bash
# DNS records needed for custom domain
# Replace yourdomain.com with your actual domain

# A Records:
vpn.yourdomain.com      → your_public_ip
*.family.yourdomain.com → your_public_ip

# Or CNAME if using dynamic DNS:
vpn.yourdomain.com      → your-ddns-hostname.duckdns.org
*.family.yourdomain.com → your-ddns-hostname.duckdns.org
```

### Load Balancing Configuration
```yaml
# For high availability setup
services:
  headscale-1:
    image: headscale/headscale:latest
    # ... configuration
    
  headscale-2:
    image: headscale/headscale:latest
    # ... configuration
    
  haproxy:
    image: haproxy:latest
    volumes:
      - ./haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro
    ports:
      - "8080:8080"
```

### Performance Tuning
```yaml
# Headscale performance settings
# In headscale.yaml:

# Increase connection limits
grpc_allow_insecure: false
grpc_timeout: 30s

# Database connection pooling
db_max_open_conns: 10
db_max_idle_conns: 5
db_conn_max_lifetime: 3600s

# Logging optimization
log_level: warn  # Reduce log verbosity in production
```

This configuration guide provides comprehensive settings for all components of the family network platform. Adjust values according to your specific requirements and environment.