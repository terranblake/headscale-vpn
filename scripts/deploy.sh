#!/bin/bash

# Family Network Platform - Automated Deployment Script
# This script automates the complete deployment of the Family Network Platform

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_FILE="/var/log/family-network-deploy.log"
BACKUP_DIR="/backup/pre-deployment"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
    exit 1
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

# Check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        warning "Running as root - this is acceptable for deployment hosts but not recommended for development"
        log "Continuing deployment as root user..."
    fi
}

# Validate environment
validate_environment() {
    log "Validating deployment environment..."
    
    # Check required commands
    local required_commands=("docker" "docker-compose" "curl" "openssl" "git")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            error "Required command '$cmd' is not installed"
        fi
    done
    
    # Check Docker daemon
    if ! docker info &> /dev/null; then
        error "Docker daemon is not running or accessible"
    fi
    
    # Check available disk space (minimum 10GB)
    local available_space=$(df "$PROJECT_DIR" | awk 'NR==2 {print $4}')
    if [[ $available_space -lt 10485760 ]]; then  # 10GB in KB
        error "Insufficient disk space. At least 10GB required"
    fi
    
    # Check memory (minimum 4GB)
    local available_memory=$(free -m | awk 'NR==2{print $7}')
    if [[ $available_memory -lt 4096 ]]; then
        warning "Less than 4GB memory available. Performance may be affected"
    fi
    
    success "Environment validation completed"
}

# Create necessary directories
create_directories() {
    log "Creating necessary directories..."
    
    local directories=(
        "/var/log"
        "/backup"
        "/backup/certificates"
        "/backup/database"
        "/backup/config"
        "$BACKUP_DIR"
    )
    
    for dir in "${directories[@]}"; do
        sudo mkdir -p "$dir"
        sudo chown "$USER:$USER" "$dir" 2>/dev/null || true
    done
    
    success "Directories created"
}

# Backup existing configuration
backup_existing_config() {
    log "Backing up existing configuration..."
    
    if [[ -d "$PROJECT_DIR/config" ]]; then
        local backup_file="$BACKUP_DIR/config-backup-$(date +%Y%m%d_%H%M%S).tar.gz"
        tar -czf "$backup_file" -C "$PROJECT_DIR" config/
        log "Configuration backed up to $backup_file"
    fi
    
    # Backup existing Docker volumes
    if docker volume ls | grep -q "headscale-vpn"; then
        log "Backing up existing Docker volumes..."
        docker run --rm -v headscale-vpn_headscale-data:/data -v "$BACKUP_DIR:/backup" \
            alpine tar -czf "/backup/volumes-backup-$(date +%Y%m%d_%H%M%S).tar.gz" -C /data .
    fi
    
    success "Backup completed"
}

# Generate secure passwords and keys
generate_secrets() {
    log "Generating secure passwords and keys..."
    
    # Generate random passwords
    generate_password() {
        openssl rand -base64 32 | tr -d "=+/" | cut -c1-25
    }
    
    # Create secrets file
    cat > "$PROJECT_DIR/.env.secrets" << EOF
# Generated secrets for Family Network Platform
# Generated on: $(date)

# Database passwords
HEADSCALE_DB_PASSWORD=$(generate_password)
POSTGRES_PASSWORD=$(generate_password)

# Service passwords
GRAFANA_ADMIN_PASSWORD=$(generate_password)
STREAMYFIN_ADMIN_PASSWORD=$(generate_password)

# API keys and tokens
HEADSCALE_API_KEY=$(openssl rand -hex 32)
PROMETHEUS_API_KEY=$(openssl rand -hex 16)

# Encryption keys
DATABASE_ENCRYPTION_KEY=$(openssl rand -hex 32)
SESSION_SECRET=$(openssl rand -hex 32)
EOF
    
    chmod 600 "$PROJECT_DIR/.env.secrets"
    
    # Generate Headscale private key
    if [[ ! -f "$PROJECT_DIR/config/headscale/private.key" ]]; then
        mkdir -p "$PROJECT_DIR/config/headscale"
        docker run --rm headscale/headscale:latest generate private-key > "$PROJECT_DIR/config/headscale/private.key"
        chmod 600 "$PROJECT_DIR/config/headscale/private.key"
    fi
    
    success "Secrets generated and stored securely"
}

# Configure environment files
configure_environment() {
    log "Configuring environment files..."
    
    # Create main .env file if it doesn't exist
    if [[ ! -f "$PROJECT_DIR/.env" ]]; then
        cp "$PROJECT_DIR/.env.example" "$PROJECT_DIR/.env" 2>/dev/null || {
            cat > "$PROJECT_DIR/.env" << EOF
# Family Network Platform Environment Configuration

# Domain configuration
DOMAIN=family.local
HEADSCALE_URL=https://headscale.family.local

# Network configuration
NETWORK_SUBNET=192.168.100.0/24
HEADSCALE_IP=192.168.100.1

# Service configuration
STREAMYFIN_PORT=8096
GRAFANA_PORT=3000
PROMETHEUS_PORT=9090

# SSL configuration
ACME_EMAIL=admin@family.local
ACME_CA_SERVER=https://acme-v02.api.letsencrypt.org/directory

# Timezone
TZ=America/New_York
EOF
        }
    fi
    
    # Source secrets into environment
    if [[ -f "$PROJECT_DIR/.env.secrets" ]]; then
        cat "$PROJECT_DIR/.env.secrets" >> "$PROJECT_DIR/.env"
    fi
    
    success "Environment configuration completed"
}

# Configure Headscale
configure_headscale() {
    log "Configuring Headscale..."
    
    local config_file="$PROJECT_DIR/config/headscale/config.yaml"
    
    if [[ ! -f "$config_file" ]]; then
        mkdir -p "$(dirname "$config_file")"
        
        # Source environment variables
        source "$PROJECT_DIR/.env"
        
        cat > "$config_file" << EOF
server_url: ${HEADSCALE_URL:-https://headscale.family.local}
listen_addr: 0.0.0.0:8080
metrics_listen_addr: 127.0.0.1:9090

grpc_listen_addr: 0.0.0.0:50443
grpc_allow_insecure: false

private_key_path: /etc/headscale/private.key
noise:
  private_key_path: /etc/headscale/noise_private.key

ip_prefixes:
  - ${NETWORK_SUBNET:-192.168.100.0/24}

derp:
  server:
    enabled: true
    region_id: 999
    region_code: "family"
    region_name: "Family Network"
    stun_listen_addr: "0.0.0.0:3478"

disable_check_updates: true
ephemeral_node_inactivity_timeout: 30m
node_update_check_interval: 10s

db_type: sqlite3
db_path: /var/lib/headscale/db.sqlite

acme_url: ${ACME_CA_SERVER:-https://acme-v02.api.letsencrypt.org/directory}
acme_email: ${ACME_EMAIL:-admin@family.local}

tls_letsencrypt_hostname: headscale.family.local
tls_letsencrypt_cache_dir: /var/lib/headscale/cache

dns_config:
  override_local_dns: true
  nameservers:
    - 1.1.1.1
    - 8.8.8.8
  domains:
    - family.local
  magic_dns: true
  base_domain: family.local
  extra_records:
    - name: "streamyfin.family.local"
      type: "A"
      value: "${HEADSCALE_IP:-192.168.100.1}"
    - name: "photos.family.local"
      type: "A"
      value: "${HEADSCALE_IP:-192.168.100.1}"
    - name: "docs.family.local"
      type: "A"
      value: "${HEADSCALE_IP:-192.168.100.1}"
    - name: "grafana.family.local"
      type: "A"
      value: "${HEADSCALE_IP:-192.168.100.1}"

log_level: info
log_format: text

policy:
  path: /etc/headscale/acl.yaml
EOF
    fi
    
    # Create ACL configuration
    local acl_file="$PROJECT_DIR/config/headscale/acl.yaml"
    if [[ ! -f "$acl_file" ]]; then
        cat > "$acl_file" << 'EOF'
acls:
  - action: accept
    src: ["group:family"]
    dst: ["*:*"]

groups:
  group:family: []

hosts: {}

tagOwners: {}

autoApprovers:
  routes: {}
  exitNode: {}
EOF
    fi
    
    success "Headscale configuration completed"
}

# Configure Traefik
configure_traefik() {
    log "Configuring Traefik reverse proxy..."
    
    local traefik_dir="$PROJECT_DIR/config/traefik"
    mkdir -p "$traefik_dir/dynamic"
    
    # Main Traefik configuration
    cat > "$traefik_dir/traefik.yml" << EOF
global:
  checkNewVersion: false
  sendAnonymousUsage: false

api:
  dashboard: true
  insecure: false

entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entrypoint:
          to: websecure
          scheme: https
          permanent: true
  websecure:
    address: ":443"

providers:
  docker:
    endpoint: "unix:///var/run/docker.sock"
    exposedByDefault: false
    network: family-network
  file:
    directory: /etc/traefik/dynamic
    watch: true

certificatesResolvers:
  letsencrypt:
    acme:
      email: ${ACME_EMAIL:-admin@family.local}
      storage: /data/acme.json
      httpChallenge:
        entryPoint: web

log:
  level: INFO
  format: json

accessLog:
  format: json
  fields:
    defaultMode: keep
    names:
      ClientUsername: drop
    headers:
      defaultMode: keep
      names:
        User-Agent: keep
        Authorization: drop
        Cookie: drop

metrics:
  prometheus:
    addEntryPointsLabels: true
    addServicesLabels: true
EOF
    
    # Dynamic configuration for middlewares
    cat > "$traefik_dir/dynamic/middlewares.yml" << 'EOF'
http:
  middlewares:
    default-headers:
      headers:
        frameDeny: true
        sslRedirect: true
        browserXssFilter: true
        contentTypeNosniff: true
        forceSTSHeader: true
        stsIncludeSubdomains: true
        stsPreload: true
        stsSeconds: 31536000
        
    secure-headers:
      headers:
        customRequestHeaders:
          X-Forwarded-Proto: "https"
        customResponseHeaders:
          X-Content-Type-Options: "nosniff"
          X-Frame-Options: "SAMEORIGIN"
          X-XSS-Protection: "1; mode=block"
          Strict-Transport-Security: "max-age=31536000; includeSubDomains"
          
    admin-auth:
      basicAuth:
        users:
          - "admin:$2y$10$..."  # Will be updated with actual hash
EOF
    
    success "Traefik configuration completed"
}

# Configure monitoring
configure_monitoring() {
    log "Configuring monitoring stack..."
    
    local prometheus_dir="$PROJECT_DIR/config/prometheus"
    local grafana_dir="$PROJECT_DIR/config/grafana"
    
    mkdir -p "$prometheus_dir/alerts" "$grafana_dir/dashboards" "$grafana_dir/provisioning/dashboards" "$grafana_dir/provisioning/datasources"
    
    # Prometheus configuration
    cat > "$prometheus_dir/prometheus.yml" << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  - "/etc/prometheus/alerts/*.yml"

alerting:
  alertmanagers:
    - static_configs:
        - targets:
          - alertmanager:9093

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'headscale'
    static_configs:
      - targets: ['headscale:9090']
    metrics_path: '/metrics'

  - job_name: 'traefik'
    static_configs:
      - targets: ['traefik:8080']
    metrics_path: '/metrics'

  - job_name: 'node-exporter'
    static_configs:
      - targets: ['node-exporter:9100']

  - job_name: 'docker'
    static_configs:
      - targets: ['docker-exporter:9323']
EOF
    
    # Basic alert rules
    cat > "$prometheus_dir/alerts/basic.yml" << 'EOF'
groups:
  - name: basic-alerts
    rules:
      - alert: ServiceDown
        expr: up == 0
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Service {{ $labels.instance }} is down"
          
      - alert: HighMemoryUsage
        expr: (node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes * 100 > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High memory usage on {{ $labels.instance }}"
EOF
    
    # Grafana datasource configuration
    cat > "$grafana_dir/provisioning/datasources/prometheus.yml" << 'EOF'
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: true
EOF
    
    # Grafana dashboard provisioning
    cat > "$grafana_dir/provisioning/dashboards/default.yml" << 'EOF'
apiVersion: 1

providers:
  - name: 'default'
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    allowUiUpdates: true
    options:
      path: /etc/grafana/dashboards
EOF
    
    success "Monitoring configuration completed"
}

# Deploy services
deploy_services() {
    log "Deploying Family Network Platform services..."
    
    cd "$PROJECT_DIR"
    
    # Pull latest images
    log "Pulling Docker images..."
    docker-compose pull
    
    # Create networks
    log "Creating Docker networks..."
    docker network create family-network 2>/dev/null || true
    
    # Start core services first
    log "Starting core services..."
    docker-compose up -d headscale traefik
    
    # Wait for core services to be healthy
    log "Waiting for core services to be ready..."
    sleep 30
    
    # Verify core services
    local max_attempts=30
    local attempt=0
    
    while [[ $attempt -lt $max_attempts ]]; do
        if curl -f http://localhost:8080/health &>/dev/null; then
            success "Headscale is ready"
            break
        fi
        
        ((attempt++))
        log "Waiting for Headscale... (attempt $attempt/$max_attempts)"
        sleep 10
    done
    
    if [[ $attempt -eq $max_attempts ]]; then
        error "Headscale failed to start properly"
    fi
    
    # Start monitoring services
    log "Starting monitoring services..."
    docker-compose up -d prometheus grafana
    
    # Start family services
    log "Starting family services..."
    docker-compose up -d streamyfin
    
    # Wait for all services to be ready
    sleep 30
    
    success "All services deployed successfully"
}

# Configure initial users
configure_initial_users() {
    log "Configuring initial users..."
    
    # Create admin user
    docker exec -it headscale headscale users create admin 2>/dev/null || true
    
    # Generate pre-auth key for admin
    local admin_key=$(docker exec -it headscale headscale preauthkeys create --user admin --reusable --expiration 24h | grep -oE 'nodekey:[a-f0-9]+')
    
    if [[ -n "$admin_key" ]]; then
        log "Admin pre-auth key: $admin_key"
        echo "ADMIN_PREAUTH_KEY=$admin_key" >> "$PROJECT_DIR/.env.secrets"
    fi
    
    success "Initial users configured"
}

# Run health checks
run_health_checks() {
    log "Running deployment health checks..."
    
    local services=("headscale:8080" "traefik:8080" "prometheus:9090" "grafana:3000")
    local failed_services=()
    
    for service in "${services[@]}"; do
        local name="${service%:*}"
        local port="${service#*:}"
        
        if curl -f "http://localhost:$port/health" &>/dev/null || curl -f "http://localhost:$port" &>/dev/null; then
            success "$name is healthy"
        else
            warning "$name health check failed"
            failed_services+=("$name")
        fi
    done
    
    if [[ ${#failed_services[@]} -eq 0 ]]; then
        success "All health checks passed"
    else
        warning "Some services failed health checks: ${failed_services[*]}"
    fi
}

# Generate deployment report
generate_deployment_report() {
    log "Generating deployment report..."
    
    local report_file="$PROJECT_DIR/deployment-report-$(date +%Y%m%d_%H%M%S).txt"
    
    cat > "$report_file" << EOF
Family Network Platform Deployment Report
=========================================

Deployment Date: $(date)
Deployment User: $USER
Project Directory: $PROJECT_DIR

Services Status:
$(docker-compose ps)

Network Configuration:
$(docker network ls | grep family)

Volume Usage:
$(docker system df)

Service URLs:
- Headscale: http://localhost:8080
- Traefik Dashboard: http://localhost:8080/dashboard/
- Prometheus: http://localhost:9090
- Grafana: http://localhost:3000
- Streamyfin: http://localhost:8096

Generated Secrets:
- Secrets stored in: $PROJECT_DIR/.env.secrets
- Headscale private key: $PROJECT_DIR/config/headscale/private.key

Next Steps:
1. Configure DNS records for *.family.local
2. Set up family user accounts
3. Configure SSL certificates
4. Test VPN connectivity
5. Add family services

For support, see documentation in docs/
EOF
    
    log "Deployment report saved to: $report_file"
    success "Deployment completed successfully!"
}

# Main deployment function
main() {
    log "Starting Family Network Platform deployment..."
    
    check_root
    validate_environment
    create_directories
    backup_existing_config
    generate_secrets
    configure_environment
    configure_headscale
    configure_traefik
    configure_monitoring
    deploy_services
    configure_initial_users
    run_health_checks
    generate_deployment_report
    
    echo
    success "Family Network Platform deployed successfully!"
    echo
    echo "Next steps:"
    echo "1. Review the deployment report"
    echo "2. Configure your DNS records"
    echo "3. Create family user accounts with: make create-user USER=username"
    echo "4. Test connectivity with family devices"
    echo
    echo "For detailed documentation, see: docs/"
}

# Handle script arguments
case "${1:-deploy}" in
    "deploy")
        main
        ;;
    "validate")
        validate_environment
        ;;
    "backup")
        backup_existing_config
        ;;
    "health")
        run_health_checks
        ;;
    *)
        echo "Usage: $0 [deploy|validate|backup|health]"
        echo "  deploy   - Full deployment (default)"
        echo "  validate - Validate environment only"
        echo "  backup   - Backup existing configuration"
        echo "  health   - Run health checks only"
        exit 1
        ;;
esac