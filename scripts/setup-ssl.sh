#!/bin/bash

# Family Network Platform - SSL Certificate Setup Script
# Automates SSL certificate generation and management

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CERT_DIR="/etc/letsencrypt"
BACKUP_DIR="/backup/certificates"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Load environment variables
load_environment() {
    if [[ -f "$PROJECT_DIR/.env" ]]; then
        source "$PROJECT_DIR/.env"
    else
        error "Environment file not found. Run deployment script first."
    fi
    
    # Set defaults if not provided
    DOMAIN=${DOMAIN:-"family.local"}
    ACME_EMAIL=${ACME_EMAIL:-"admin@$DOMAIN"}
    ACME_CA_SERVER=${ACME_CA_SERVER:-"https://acme-v02.api.letsencrypt.org/directory"}
}

# Check prerequisites
check_prerequisites() {
    log "Checking SSL setup prerequisites..."
    
    # Check if running as root for certbot
    if [[ $EUID -ne 0 ]] && [[ "${1:-}" != "traefik" ]]; then
        error "SSL certificate setup requires root privileges (except for Traefik mode)"
    fi
    
    # Check internet connectivity
    if ! curl -s --max-time 10 https://google.com &> /dev/null; then
        error "Internet connectivity required for SSL certificate generation"
    fi
    
    # Check DNS resolution for domain
    local test_domain="$DOMAIN"
    if ! nslookup "$test_domain" &> /dev/null; then
        warning "DNS resolution for $test_domain failed. Ensure DNS is configured."
    fi
    
    success "Prerequisites check completed"
}

# Install certbot if needed
install_certbot() {
    log "Installing certbot..."
    
    if command -v certbot &> /dev/null; then
        success "Certbot already installed"
        return
    fi
    
    # Install certbot based on OS
    if [[ -f /etc/debian_version ]]; then
        apt update
        apt install -y certbot python3-certbot-nginx python3-certbot-apache
    elif [[ -f /etc/redhat-release ]]; then
        yum install -y certbot python3-certbot-nginx python3-certbot-apache
    else
        # Install via snap as fallback
        if command -v snap &> /dev/null; then
            snap install --classic certbot
            ln -sf /snap/bin/certbot /usr/bin/certbot
        else
            error "Cannot install certbot. Please install manually."
        fi
    fi
    
    success "Certbot installed successfully"
}

# Generate certificates using certbot (standalone mode)
generate_certificates_standalone() {
    log "Generating SSL certificates using certbot standalone mode..."
    
    local domains=(
        "$DOMAIN"
        "headscale.$DOMAIN"
        "streamyfin.$DOMAIN"
        "photos.$DOMAIN"
        "docs.$DOMAIN"
        "grafana.$DOMAIN"
        "prometheus.$DOMAIN"
    )
    
    # Stop services that might use port 80
    log "Stopping services temporarily..."
    docker-compose -f "$PROJECT_DIR/docker-compose.yml" stop traefik 2>/dev/null || true
    
    # Generate certificate for all domains
    local domain_args=""
    for domain in "${domains[@]}"; do
        domain_args="$domain_args -d $domain"
    done
    
    certbot certonly \
        --standalone \
        --email "$ACME_EMAIL" \
        --agree-tos \
        --no-eff-email \
        --expand \
        $domain_args
    
    # Restart services
    log "Restarting services..."
    docker-compose -f "$PROJECT_DIR/docker-compose.yml" start traefik 2>/dev/null || true
    
    success "SSL certificates generated successfully"
}

# Setup Traefik automatic SSL
setup_traefik_ssl() {
    log "Setting up Traefik automatic SSL certificates..."
    
    # Ensure Traefik configuration directory exists
    mkdir -p "$PROJECT_DIR/config/traefik"
    
    # Create Traefik SSL configuration
    cat > "$PROJECT_DIR/config/traefik/ssl.yml" << EOF
# Traefik SSL Configuration
tls:
  options:
    default:
      sslProtocols:
        - "TLSv1.2"
        - "TLSv1.3"
      cipherSuites:
        - "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384"
        - "TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305"
        - "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256"
        - "TLS_RSA_WITH_AES_256_GCM_SHA384"
        - "TLS_RSA_WITH_AES_128_GCM_SHA256"
      curvePreferences:
        - "CurveP521"
        - "CurveP384"
      minVersion: "VersionTLS12"

certificatesResolvers:
  letsencrypt:
    acme:
      email: $ACME_EMAIL
      storage: /data/acme.json
      caServer: $ACME_CA_SERVER
      httpChallenge:
        entryPoint: web
      # Alternative: DNS challenge (uncomment and configure for your DNS provider)
      # dnsChallenge:
      #   provider: cloudflare
      #   resolvers:
      #     - "1.1.1.1:53"
      #     - "8.8.8.8:53"
EOF
    
    # Update main Traefik configuration to include SSL
    if [[ -f "$PROJECT_DIR/config/traefik/traefik.yml" ]]; then
        # Add certificatesResolvers if not present
        if ! grep -q "certificatesResolvers" "$PROJECT_DIR/config/traefik/traefik.yml"; then
            cat >> "$PROJECT_DIR/config/traefik/traefik.yml" << EOF

certificatesResolvers:
  letsencrypt:
    acme:
      email: $ACME_EMAIL
      storage: /data/acme.json
      httpChallenge:
        entryPoint: web
EOF
        fi
    fi
    
    # Create acme.json file with correct permissions
    local acme_file="$PROJECT_DIR/data/traefik/acme.json"
    mkdir -p "$(dirname "$acme_file")"
    touch "$acme_file"
    chmod 600 "$acme_file"
    
    # Restart Traefik to apply SSL configuration
    log "Restarting Traefik to apply SSL configuration..."
    docker-compose -f "$PROJECT_DIR/docker-compose.yml" restart traefik
    
    success "Traefik SSL configuration completed"
}

# Verify SSL certificates
verify_certificates() {
    log "Verifying SSL certificates..."
    
    local domains=(
        "headscale.$DOMAIN"
        "streamyfin.$DOMAIN"
        "photos.$DOMAIN"
        "docs.$DOMAIN"
        "grafana.$DOMAIN"
    )
    
    local failed_domains=()
    
    for domain in "${domains[@]}"; do
        log "Checking certificate for $domain..."
        
        # Wait for service to be ready
        sleep 5
        
        # Check if certificate is valid
        if openssl s_client -connect "$domain:443" -servername "$domain" < /dev/null 2>/dev/null | openssl x509 -noout -dates &> /dev/null; then
            local expiry_date=$(openssl s_client -connect "$domain:443" -servername "$domain" < /dev/null 2>/dev/null | openssl x509 -noout -dates | grep notAfter | cut -d= -f2)
            success "Certificate for $domain is valid (expires: $expiry_date)"
        else
            warning "Certificate verification failed for $domain"
            failed_domains+=("$domain")
        fi
    done
    
    if [[ ${#failed_domains[@]} -eq 0 ]]; then
        success "All SSL certificates verified successfully"
    else
        warning "Certificate verification failed for: ${failed_domains[*]}"
    fi
}

# Backup certificates
backup_certificates() {
    log "Backing up SSL certificates..."
    
    local backup_file="$BACKUP_DIR/ssl-backup-$(date +%Y%m%d_%H%M%S).tar.gz"
    mkdir -p "$BACKUP_DIR"
    
    # Backup Let's Encrypt certificates
    if [[ -d "$CERT_DIR" ]]; then
        tar -czf "$backup_file" -C "$CERT_DIR" .
        success "Certificates backed up to $backup_file"
    fi
    
    # Backup Traefik certificates
    if [[ -f "$PROJECT_DIR/data/traefik/acme.json" ]]; then
        cp "$PROJECT_DIR/data/traefik/acme.json" "$BACKUP_DIR/traefik-acme-$(date +%Y%m%d_%H%M%S).json"
        success "Traefik certificates backed up"
    fi
}

# Restore certificates from backup
restore_certificates() {
    local backup_file="$1"
    
    if [[ ! -f "$backup_file" ]]; then
        error "Backup file not found: $backup_file"
    fi
    
    log "Restoring SSL certificates from $backup_file..."
    
    # Create backup of current certificates
    if [[ -d "$CERT_DIR" ]]; then
        mv "$CERT_DIR" "$CERT_DIR.backup.$(date +%Y%m%d_%H%M%S)"
    fi
    
    # Restore certificates
    mkdir -p "$CERT_DIR"
    tar -xzf "$backup_file" -C "$CERT_DIR"
    
    # Restart services
    docker-compose -f "$PROJECT_DIR/docker-compose.yml" restart traefik
    
    success "SSL certificates restored successfully"
}

# Setup certificate renewal
setup_certificate_renewal() {
    log "Setting up automatic certificate renewal..."
    
    # Create renewal script
    cat > /usr/local/bin/renew-family-certs.sh << 'EOF'
#!/bin/bash

# Family Network Platform Certificate Renewal Script
LOG_FILE="/var/log/family-cert-renewal.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

log "Starting certificate renewal check..."

# Renew certificates
if certbot renew --quiet --no-self-upgrade; then
    log "Certificate renewal successful"
    
    # Restart Traefik to reload certificates
    cd /path/to/headscale-vpn
    docker-compose restart traefik
    log "Traefik restarted"
else
    log "Certificate renewal failed"
    exit 1
fi

log "Certificate renewal check completed"
EOF
    
    chmod +x /usr/local/bin/renew-family-certs.sh
    
    # Update script path
    sed -i "s|/path/to/headscale-vpn|$PROJECT_DIR|g" /usr/local/bin/renew-family-certs.sh
    
    # Setup cron job for automatic renewal
    local cron_job="0 2 * * 0 /usr/local/bin/renew-family-certs.sh"
    
    # Add to crontab if not already present
    if ! crontab -l 2>/dev/null | grep -q "renew-family-certs.sh"; then
        (crontab -l 2>/dev/null; echo "$cron_job") | crontab -
        success "Automatic certificate renewal configured (weekly check)"
    else
        success "Automatic certificate renewal already configured"
    fi
}

# Check certificate expiration
check_certificate_expiration() {
    log "Checking certificate expiration dates..."
    
    local domains=(
        "headscale.$DOMAIN"
        "streamyfin.$DOMAIN"
        "photos.$DOMAIN"
        "docs.$DOMAIN"
        "grafana.$DOMAIN"
    )
    
    local warning_days=30
    local expiring_soon=()
    
    for domain in "${domains[@]}"; do
        if openssl s_client -connect "$domain:443" -servername "$domain" < /dev/null 2>/dev/null | openssl x509 -noout -dates &> /dev/null; then
            local expiry_date=$(openssl s_client -connect "$domain:443" -servername "$domain" < /dev/null 2>/dev/null | openssl x509 -noout -dates | grep notAfter | cut -d= -f2)
            local expiry_epoch=$(date -d "$expiry_date" +%s)
            local current_epoch=$(date +%s)
            local days_until_expiry=$(( (expiry_epoch - current_epoch) / 86400 ))
            
            if [[ $days_until_expiry -lt $warning_days ]]; then
                warning "Certificate for $domain expires in $days_until_expiry days"
                expiring_soon+=("$domain")
            else
                success "Certificate for $domain expires in $days_until_expiry days"
            fi
        else
            warning "Could not check certificate for $domain"
        fi
    done
    
    if [[ ${#expiring_soon[@]} -gt 0 ]]; then
        warning "Certificates expiring soon: ${expiring_soon[*]}"
        log "Consider running certificate renewal: certbot renew"
    fi
}

# Generate self-signed certificates for development
generate_self_signed_certificates() {
    log "Generating self-signed certificates for development..."
    
    local cert_dir="$PROJECT_DIR/config/ssl"
    mkdir -p "$cert_dir"
    
    local domains=(
        "$DOMAIN"
        "headscale.$DOMAIN"
        "streamyfin.$DOMAIN"
        "photos.$DOMAIN"
        "docs.$DOMAIN"
        "grafana.$DOMAIN"
    )
    
    # Create certificate configuration
    cat > "$cert_dir/cert.conf" << EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
C = US
ST = State
L = City
O = Family Network
CN = $DOMAIN

[v3_req]
keyUsage = keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
EOF
    
    # Add all domains to SAN
    local i=1
    for domain in "${domains[@]}"; do
        echo "DNS.$i = $domain" >> "$cert_dir/cert.conf"
        ((i++))
    done
    
    # Generate private key
    openssl genrsa -out "$cert_dir/family.key" 2048
    
    # Generate certificate
    openssl req -new -x509 -key "$cert_dir/family.key" -out "$cert_dir/family.crt" -days 365 -config "$cert_dir/cert.conf" -extensions v3_req
    
    # Set appropriate permissions
    chmod 600 "$cert_dir/family.key"
    chmod 644 "$cert_dir/family.crt"
    
    success "Self-signed certificates generated in $cert_dir"
    warning "Self-signed certificates are for development only. Use Let's Encrypt for production."
}

# Main SSL setup function
main() {
    local mode="${1:-traefik}"
    
    log "Starting SSL certificate setup (mode: $mode)..."
    
    load_environment
    check_prerequisites "$mode"
    
    case "$mode" in
        "traefik")
            setup_traefik_ssl
            sleep 30  # Wait for Traefik to generate certificates
            verify_certificates
            ;;
        "certbot")
            install_certbot
            generate_certificates_standalone
            setup_certificate_renewal
            verify_certificates
            ;;
        "self-signed")
            generate_self_signed_certificates
            ;;
        "backup")
            backup_certificates
            ;;
        "restore")
            if [[ -z "${2:-}" ]]; then
                error "Backup file required for restore mode"
            fi
            restore_certificates "$2"
            ;;
        "check")
            check_certificate_expiration
            ;;
        "renew")
            if command -v certbot &> /dev/null; then
                certbot renew
                docker-compose -f "$PROJECT_DIR/docker-compose.yml" restart traefik
            else
                error "Certbot not installed"
            fi
            ;;
        *)
            error "Invalid mode. Use: traefik, certbot, self-signed, backup, restore, check, or renew"
            ;;
    esac
    
    success "SSL certificate setup completed"
}

# Handle script arguments
if [[ $# -eq 0 ]]; then
    echo "Family Network Platform - SSL Certificate Setup"
    echo "Usage: $0 <mode> [options]"
    echo
    echo "Modes:"
    echo "  traefik     - Setup automatic SSL with Traefik (recommended)"
    echo "  certbot     - Generate certificates with certbot standalone"
    echo "  self-signed - Generate self-signed certificates (development only)"
    echo "  backup      - Backup existing certificates"
    echo "  restore     - Restore certificates from backup file"
    echo "  check       - Check certificate expiration dates"
    echo "  renew       - Manually renew certificates"
    echo
    echo "Examples:"
    echo "  $0 traefik                    # Setup Traefik automatic SSL"
    echo "  $0 certbot                    # Generate with certbot"
    echo "  $0 backup                     # Backup certificates"
    echo "  $0 restore backup.tar.gz      # Restore from backup"
    echo "  $0 check                      # Check expiration"
    exit 1
fi

main "$@"