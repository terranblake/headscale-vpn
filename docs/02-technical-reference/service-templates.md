# Service Templates Guide

Comprehensive templates and patterns for adding new services to the Family Network Platform.

## Table of Contents

- [Service Template Overview](#service-template-overview)
- [Docker Compose Templates](#docker-compose-templates)
- [Traefik Configuration Templates](#traefik-configuration-templates)
- [DNS Configuration Templates](#dns-configuration-templates)
- [Monitoring Templates](#monitoring-templates)
- [Service-Specific Templates](#service-specific-templates)
- [Deployment Automation](#deployment-automation)

## Service Template Overview

### Template Structure

Each new service requires configuration in multiple areas:

```
New Service Addition:
├── docker-compose.yml          # Container definition
├── config/traefik/            # Reverse proxy configuration
├── config/headscale/          # DNS and routing
├── config/prometheus/         # Monitoring
└── docs/03-family-docs/       # Family documentation
```

### Naming Conventions

#### Service Names
- **Format:** `servicename.family.local`
- **Examples:** `photos.family.local`, `docs.family.local`, `calendar.family.local`
- **Container Names:** Match service name without domain (e.g., `photos`, `docs`)

#### Network Configuration
- **Internal Network:** `family-network`
- **Port Mapping:** Avoid external port exposure (use Traefik)
- **Volume Naming:** `servicename-data`, `servicename-config`

## Docker Compose Templates

### Basic Service Template

```yaml
# Template for adding a new service to docker-compose.yml
services:
  servicename:
    image: organization/servicename:latest
    container_name: servicename
    restart: unless-stopped
    networks:
      - family-network
    volumes:
      - servicename-data:/data
      - servicename-config:/config
      - /etc/localtime:/etc/localtime:ro
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=America/New_York
    labels:
      # Traefik configuration
      - "traefik.enable=true"
      - "traefik.http.routers.servicename.rule=Host(`servicename.family.local`)"
      - "traefik.http.routers.servicename.entrypoints=websecure"
      - "traefik.http.routers.servicename.tls.certresolver=letsencrypt"
      - "traefik.http.services.servicename.loadbalancer.server.port=8080"
      
      # Monitoring labels
      - "prometheus.io/scrape=true"
      - "prometheus.io/port=8080"
      - "prometheus.io/path=/metrics"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

volumes:
  servicename-data:
    driver: local
  servicename-config:
    driver: local
```

### Database-Backed Service Template

```yaml
# Template for services requiring a database
services:
  servicename:
    image: organization/servicename:latest
    container_name: servicename
    restart: unless-stopped
    networks:
      - family-network
    volumes:
      - servicename-data:/data
      - servicename-config:/config
    environment:
      - DATABASE_URL=postgresql://servicename:password@servicename-db:5432/servicename
      - REDIS_URL=redis://redis:6379
    depends_on:
      - servicename-db
      - redis
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.servicename.rule=Host(`servicename.family.local`)"
      - "traefik.http.routers.servicename.entrypoints=websecure"
      - "traefik.http.routers.servicename.tls.certresolver=letsencrypt"
      - "traefik.http.services.servicename.loadbalancer.server.port=3000"

  servicename-db:
    image: postgres:15-alpine
    container_name: servicename-db
    restart: unless-stopped
    networks:
      - family-network
    volumes:
      - servicename-db-data:/var/lib/postgresql/data
    environment:
      - POSTGRES_DB=servicename
      - POSTGRES_USER=servicename
      - POSTGRES_PASSWORD=secure_password_here
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U servicename"]
      interval: 30s
      timeout: 10s
      retries: 3

volumes:
  servicename-data:
  servicename-config:
  servicename-db-data:
```

### Media Service Template

```yaml
# Template for media/streaming services
services:
  mediaservice:
    image: organization/mediaservice:latest
    container_name: mediaservice
    restart: unless-stopped
    networks:
      - family-network
    volumes:
      - mediaservice-config:/config
      - /path/to/media:/media:ro
      - /path/to/downloads:/downloads
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=America/New_York
    devices:
      - /dev/dri:/dev/dri  # Hardware acceleration
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.mediaservice.rule=Host(`mediaservice.family.local`)"
      - "traefik.http.routers.mediaservice.entrypoints=websecure"
      - "traefik.http.routers.mediaservice.tls.certresolver=letsencrypt"
      - "traefik.http.services.mediaservice.loadbalancer.server.port=8096"
      
      # Large file upload support
      - "traefik.http.routers.mediaservice.middlewares=mediaservice-headers"
      - "traefik.http.middlewares.mediaservice-headers.headers.customrequestheaders.X-Forwarded-Proto=https"
      - "traefik.http.middlewares.mediaservice-headers.headers.customrequestheaders.X-Forwarded-For="

volumes:
  mediaservice-config:
```

## Traefik Configuration Templates

### Basic HTTP Service

```yaml
# config/traefik/dynamic/servicename.yml
http:
  routers:
    servicename:
      rule: "Host(`servicename.family.local`)"
      entryPoints:
        - websecure
      service: servicename
      tls:
        certResolver: letsencrypt
      middlewares:
        - default-headers
        - secure-headers

  services:
    servicename:
      loadBalancer:
        servers:
          - url: "http://servicename:8080"
        healthCheck:
          path: "/health"
          interval: "30s"
          timeout: "5s"

  middlewares:
    servicename-auth:
      basicAuth:
        users:
          - "admin:$2y$10$..."  # Generated password hash
```

### API Service with Rate Limiting

```yaml
# config/traefik/dynamic/api-service.yml
http:
  routers:
    api-service:
      rule: "Host(`api.family.local`)"
      entryPoints:
        - websecure
      service: api-service
      tls:
        certResolver: letsencrypt
      middlewares:
        - api-rate-limit
        - api-headers

  services:
    api-service:
      loadBalancer:
        servers:
          - url: "http://api-service:3000"

  middlewares:
    api-rate-limit:
      rateLimit:
        burst: 100
        average: 50
        period: "1m"
    
    api-headers:
      headers:
        customRequestHeaders:
          X-Forwarded-Proto: "https"
        customResponseHeaders:
          X-Content-Type-Options: "nosniff"
          X-Frame-Options: "DENY"
```

### WebSocket Service

```yaml
# config/traefik/dynamic/websocket-service.yml
http:
  routers:
    websocket-service:
      rule: "Host(`ws.family.local`)"
      entryPoints:
        - websecure
      service: websocket-service
      tls:
        certResolver: letsencrypt

  services:
    websocket-service:
      loadBalancer:
        servers:
          - url: "http://websocket-service:8080"
        sticky:
          cookie:
            name: "websocket-session"
            secure: true
            httpOnly: true
```

## DNS Configuration Templates

### Headscale DNS Configuration

```yaml
# Add to config/headscale/config.yaml
dns_config:
  override_local_dns: true
  nameservers:
    - 1.1.1.1
    - 8.8.8.8
  domains:
    - family.local
  magic_dns: true
  base_domain: family.local
  
  # Service-specific DNS entries
  extra_records:
    - name: "servicename.family.local"
      type: "A"
      value: "192.168.1.100"  # Traefik IP
    
    - name: "api.family.local"
      type: "A"
      value: "192.168.1.100"
    
    - name: "*.servicename.family.local"  # Wildcard for subdomains
      type: "A"
      value: "192.168.1.100"
```

### External DNS Configuration

```bash
# For external DNS providers (Cloudflare, Route53, etc.)
# Add A records pointing to your public IP

# Cloudflare API example
curl -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
  -H "Authorization: Bearer $CF_API_TOKEN" \
  -H "Content-Type: application/json" \
  --data '{
    "type": "A",
    "name": "servicename.family.local",
    "content": "YOUR_PUBLIC_IP",
    "ttl": 300,
    "proxied": false
  }'
```

## Monitoring Templates

### Prometheus Service Discovery

```yaml
# config/prometheus/prometheus.yml - Add to scrape_configs
scrape_configs:
  - job_name: 'servicename'
    static_configs:
      - targets: ['servicename:8080']
    metrics_path: '/metrics'
    scrape_interval: 30s
    scrape_timeout: 10s
    
  - job_name: 'servicename-health'
    static_configs:
      - targets: ['servicename:8080']
    metrics_path: '/health'
    scrape_interval: 15s
```

### Grafana Dashboard Template

```json
{
  "dashboard": {
    "title": "ServiceName Monitoring",
    "panels": [
      {
        "title": "Service Uptime",
        "type": "stat",
        "targets": [
          {
            "expr": "up{job=\"servicename\"}",
            "legendFormat": "Uptime"
          }
        ]
      },
      {
        "title": "Request Rate",
        "type": "graph",
        "targets": [
          {
            "expr": "rate(http_requests_total{job=\"servicename\"}[5m])",
            "legendFormat": "Requests/sec"
          }
        ]
      },
      {
        "title": "Response Time",
        "type": "graph",
        "targets": [
          {
            "expr": "histogram_quantile(0.95, rate(http_request_duration_seconds_bucket{job=\"servicename\"}[5m]))",
            "legendFormat": "95th percentile"
          }
        ]
      }
    ]
  }
}
```

### Alert Rules Template

```yaml
# config/prometheus/alerts/servicename.yml
groups:
  - name: servicename-alerts
    rules:
      - alert: ServiceNameDown
        expr: up{job="servicename"} == 0
        for: 5m
        labels:
          severity: critical
          service: servicename
        annotations:
          summary: "ServiceName is down"
          description: "ServiceName has been down for more than 5 minutes"
          
      - alert: ServiceNameHighErrorRate
        expr: rate(http_requests_total{job="servicename",status=~"5.."}[5m]) > 0.1
        for: 2m
        labels:
          severity: warning
          service: servicename
        annotations:
          summary: "High error rate on ServiceName"
          description: "ServiceName error rate is {{ $value }} errors per second"
          
      - alert: ServiceNameHighLatency
        expr: histogram_quantile(0.95, rate(http_request_duration_seconds_bucket{job="servicename"}[5m])) > 2
        for: 5m
        labels:
          severity: warning
          service: servicename
        annotations:
          summary: "High latency on ServiceName"
          description: "ServiceName 95th percentile latency is {{ $value }}s"
```

## Service-Specific Templates

### Photo Management Service (PhotoPrism)

```yaml
# PhotoPrism service template
services:
  photos:
    image: photoprism/photoprism:latest
    container_name: photos
    restart: unless-stopped
    networks:
      - family-network
    volumes:
      - photos-storage:/photoprism/storage
      - photos-originals:/photoprism/originals
      - photos-import:/photoprism/import
    environment:
      PHOTOPRISM_ADMIN_PASSWORD: "secure_password"
      PHOTOPRISM_SITE_URL: "https://photos.family.local/"
      PHOTOPRISM_SITE_TITLE: "Family Photos"
      PHOTOPRISM_SITE_CAPTION: "Browse Your Life"
      PHOTOPRISM_DATABASE_DRIVER: "mysql"
      PHOTOPRISM_DATABASE_SERVER: "photos-db:3306"
      PHOTOPRISM_DATABASE_NAME: "photoprism"
      PHOTOPRISM_DATABASE_USER: "photoprism"
      PHOTOPRISM_DATABASE_PASSWORD: "photoprism_password"
    depends_on:
      - photos-db
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.photos.rule=Host(`photos.family.local`)"
      - "traefik.http.routers.photos.entrypoints=websecure"
      - "traefik.http.routers.photos.tls.certresolver=letsencrypt"
      - "traefik.http.services.photos.loadbalancer.server.port=2342"

  photos-db:
    image: mariadb:10.9
    container_name: photos-db
    restart: unless-stopped
    networks:
      - family-network
    volumes:
      - photos-db-data:/var/lib/mysql
    environment:
      MARIADB_AUTO_UPGRADE: "1"
      MARIADB_INITDB_SKIP_TZINFO: "1"
      MARIADB_DATABASE: "photoprism"
      MARIADB_USER: "photoprism"
      MARIADB_PASSWORD: "photoprism_password"
      MARIADB_ROOT_PASSWORD: "root_password"

volumes:
  photos-storage:
  photos-originals:
  photos-import:
  photos-db-data:
```

### Document Management Service (Nextcloud)

```yaml
# Nextcloud service template
services:
  docs:
    image: nextcloud:latest
    container_name: docs
    restart: unless-stopped
    networks:
      - family-network
    volumes:
      - docs-data:/var/www/html
      - docs-config:/var/www/html/config
      - docs-apps:/var/www/html/custom_apps
      - docs-themes:/var/www/html/themes
    environment:
      MYSQL_HOST: docs-db
      MYSQL_DATABASE: nextcloud
      MYSQL_USER: nextcloud
      MYSQL_PASSWORD: nextcloud_password
      NEXTCLOUD_ADMIN_USER: admin
      NEXTCLOUD_ADMIN_PASSWORD: admin_password
      NEXTCLOUD_TRUSTED_DOMAINS: docs.family.local
      OVERWRITEPROTOCOL: https
    depends_on:
      - docs-db
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.docs.rule=Host(`docs.family.local`)"
      - "traefik.http.routers.docs.entrypoints=websecure"
      - "traefik.http.routers.docs.tls.certresolver=letsencrypt"
      - "traefik.http.services.docs.loadbalancer.server.port=80"
      - "traefik.http.routers.docs.middlewares=docs-headers"
      - "traefik.http.middlewares.docs-headers.headers.customrequestheaders.X-Forwarded-Proto=https"

  docs-db:
    image: mariadb:10.9
    container_name: docs-db
    restart: unless-stopped
    networks:
      - family-network
    volumes:
      - docs-db-data:/var/lib/mysql
    environment:
      MARIADB_ROOT_PASSWORD: root_password
      MARIADB_DATABASE: nextcloud
      MARIADB_USER: nextcloud
      MARIADB_PASSWORD: nextcloud_password

volumes:
  docs-data:
  docs-config:
  docs-apps:
  docs-themes:
  docs-db-data:
```

### Home Automation Service (Home Assistant)

```yaml
# Home Assistant service template
services:
  homeassistant:
    image: homeassistant/home-assistant:latest
    container_name: homeassistant
    restart: unless-stopped
    networks:
      - family-network
    volumes:
      - homeassistant-config:/config
      - /etc/localtime:/etc/localtime:ro
    environment:
      - TZ=America/New_York
    privileged: true
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.homeassistant.rule=Host(`home.family.local`)"
      - "traefik.http.routers.homeassistant.entrypoints=websecure"
      - "traefik.http.routers.homeassistant.tls.certresolver=letsencrypt"
      - "traefik.http.services.homeassistant.loadbalancer.server.port=8123"

volumes:
  homeassistant-config:
```

## Deployment Automation

### Service Addition Script Template

```bash
#!/bin/bash
# scripts/add-service.sh

SERVICE_NAME="$1"
SERVICE_TYPE="$2"  # basic, database, media, etc.

if [ -z "$SERVICE_NAME" ] || [ -z "$SERVICE_TYPE" ]; then
    echo "Usage: $0 <service-name> <service-type>"
    echo "Service types: basic, database, media, photos, docs, homeassistant"
    exit 1
fi

echo "Adding service: $SERVICE_NAME (type: $SERVICE_TYPE)"

# Create service directory structure
mkdir -p "config/$SERVICE_NAME"
mkdir -p "docs/03-family-docs/services"

# Generate docker-compose service definition
case $SERVICE_TYPE in
    "basic")
        generate_basic_service "$SERVICE_NAME"
        ;;
    "database")
        generate_database_service "$SERVICE_NAME"
        ;;
    "media")
        generate_media_service "$SERVICE_NAME"
        ;;
    *)
        echo "Unknown service type: $SERVICE_TYPE"
        exit 1
        ;;
esac

# Add DNS configuration
add_dns_config "$SERVICE_NAME"

# Add Traefik configuration
add_traefik_config "$SERVICE_NAME"

# Add monitoring configuration
add_monitoring_config "$SERVICE_NAME"

# Generate family documentation
generate_family_docs "$SERVICE_NAME"

echo "Service $SERVICE_NAME added successfully!"
echo "Next steps:"
echo "1. Review generated configuration files"
echo "2. Update any service-specific settings"
echo "3. Run: docker-compose up -d $SERVICE_NAME"
echo "4. Test: curl -I https://$SERVICE_NAME.family.local"
```

### Configuration Generator Functions

```bash
# Function to generate basic service configuration
generate_basic_service() {
    local service_name="$1"
    
    cat >> docker-compose.yml << EOF

  $service_name:
    image: organization/$service_name:latest
    container_name: $service_name
    restart: unless-stopped
    networks:
      - family-network
    volumes:
      - ${service_name}-data:/data
      - ${service_name}-config:/config
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=America/New_York
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.$service_name.rule=Host(\`$service_name.family.local\`)"
      - "traefik.http.routers.$service_name.entrypoints=websecure"
      - "traefik.http.routers.$service_name.tls.certresolver=letsencrypt"
      - "traefik.http.services.$service_name.loadbalancer.server.port=8080"

volumes:
  ${service_name}-data:
  ${service_name}-config:
EOF
}

# Function to add DNS configuration
add_dns_config() {
    local service_name="$1"
    
    # Add to headscale config
    cat >> config/headscale/config.yaml << EOF
    - name: "$service_name.family.local"
      type: "A"
      value: "192.168.1.100"
EOF
}

# Function to add Traefik configuration
add_traefik_config() {
    local service_name="$1"
    
    cat > "config/traefik/dynamic/$service_name.yml" << EOF
http:
  routers:
    $service_name:
      rule: "Host(\`$service_name.family.local\`)"
      entryPoints:
        - websecure
      service: $service_name
      tls:
        certResolver: letsencrypt
      middlewares:
        - default-headers

  services:
    $service_name:
      loadBalancer:
        servers:
          - url: "http://$service_name:8080"
        healthCheck:
          path: "/health"
          interval: "30s"
EOF
}

# Function to add monitoring configuration
add_monitoring_config() {
    local service_name="$1"
    
    # Add Prometheus scrape config
    cat >> config/prometheus/prometheus.yml << EOF
  - job_name: '$service_name'
    static_configs:
      - targets: ['$service_name:8080']
    metrics_path: '/metrics'
    scrape_interval: 30s
EOF

    # Create alert rules
    cat > "config/prometheus/alerts/$service_name.yml" << EOF
groups:
  - name: $service_name-alerts
    rules:
      - alert: ${service_name^}Down
        expr: up{job="$service_name"} == 0
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "$service_name is down"
EOF
}
```

### Service Validation Script

```bash
#!/bin/bash
# scripts/validate-service.sh

SERVICE_NAME="$1"

if [ -z "$SERVICE_NAME" ]; then
    echo "Usage: $0 <service-name>"
    exit 1
fi

echo "Validating service: $SERVICE_NAME"

# Check if service is running
if ! docker ps | grep -q "$SERVICE_NAME"; then
    echo "❌ Service $SERVICE_NAME is not running"
    exit 1
fi

# Check HTTP response
if curl -I --max-time 10 "https://$SERVICE_NAME.family.local" 2>/dev/null | grep -q "200 OK"; then
    echo "✅ HTTP response OK"
else
    echo "❌ HTTP response failed"
fi

# Check DNS resolution
if nslookup "$SERVICE_NAME.family.local" >/dev/null 2>&1; then
    echo "✅ DNS resolution OK"
else
    echo "❌ DNS resolution failed"
fi

# Check Traefik routing
if docker logs traefik 2>&1 | grep -q "$SERVICE_NAME"; then
    echo "✅ Traefik routing configured"
else
    echo "❌ Traefik routing not found"
fi

# Check monitoring
if curl -s "http://localhost:9090/api/v1/targets" | grep -q "$SERVICE_NAME"; then
    echo "✅ Prometheus monitoring configured"
else
    echo "❌ Prometheus monitoring not configured"
fi

echo "Service validation complete"
```

## Quick Reference

### Adding a New Service Checklist

1. **Choose Service Type:**
   - Basic web service
   - Database-backed service
   - Media/streaming service
   - Specialized service (photos, docs, etc.)

2. **Configuration Steps:**
   ```bash
   # Use automation script
   ./scripts/add-service.sh myservice basic
   
   # Or manual steps:
   # 1. Add to docker-compose.yml
   # 2. Create Traefik config
   # 3. Add DNS entry
   # 4. Configure monitoring
   # 5. Create family documentation
   ```

3. **Deployment:**
   ```bash
   docker-compose up -d myservice
   ```

4. **Validation:**
   ```bash
   ./scripts/validate-service.sh myservice
   ```

5. **Testing:**
   ```bash
   curl -I https://myservice.family.local
   ```

### Common Service Ports

| Service Type | Default Port | Protocol |
|-------------|-------------|----------|
| Web App | 8080 | HTTP |
| API Service | 3000 | HTTP |
| Database | 5432/3306 | TCP |
| Media Server | 8096 | HTTP |
| File Server | 80/443 | HTTP/HTTPS |
| Chat Service | 8008 | HTTP |

### Template Variables

Replace these variables when using templates:

- `servicename` - Service name (lowercase, no spaces)
- `ServiceName` - Service name (title case)
- `8080` - Service internal port
- `organization` - Docker image organization
- `secure_password` - Generated secure password
- `192.168.1.100` - Traefik/gateway IP address

---

These templates provide a standardized approach to adding new services to the Family Network Platform. Use the automation scripts when possible, and customize the templates based on specific service requirements.