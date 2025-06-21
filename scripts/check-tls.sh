#!/bin/bash

# TLS Certificate Troubleshooting Script
# This script helps diagnose TLS certificate issues with Traefik and Let's Encrypt

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Load environment variables
load_environment() {
    log_info "Loading environment variables..."
    
    if [[ ! -f "$PROJECT_ROOT/.env" ]]; then
        log_error ".env file not found at $PROJECT_ROOT/.env"
        exit 1
    fi
    
    # Source the .env file
    set -a
    source "$PROJECT_ROOT/.env"
    set +a
    
    log_success "Environment variables loaded"
}

# Check Traefik status
check_traefik_status() {
    log_info "Checking Traefik status..."
    
    # Check if Traefik pod is running
    if ! k3s kubectl get pods -n traefik -l app.kubernetes.io/name=traefik --no-headers | grep -q Running; then
        log_error "Traefik pod is not running"
        k3s kubectl get pods -n traefik -l app.kubernetes.io/name=traefik
        return 1
    fi
    
    log_success "Traefik pod is running"
    
    # Get Traefik pod name
    local traefik_pod
    traefik_pod=$(k3s kubectl get pods -n traefik -l app.kubernetes.io/name=traefik -o jsonpath='{.items[0].metadata.name}')
    
    # Check Traefik logs for ACME-related messages
    log_info "Checking Traefik logs for ACME activity..."
    k3s kubectl logs -n traefik "$traefik_pod" --tail=50 | grep -i "acme\|certificate\|letsencrypt" || log_warning "No ACME activity found in recent logs"
}

# Check ACME storage
check_acme_storage() {
    log_info "Checking ACME storage..."
    
    # Check if ACME PVC exists and is bound
    local pvc_status
    pvc_status=$(k3s kubectl get pvc -n traefik traefik-acme-storage -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
    
    if [[ "$pvc_status" != "Bound" ]]; then
        log_error "ACME storage PVC is not bound (status: $pvc_status)"
        k3s kubectl get pvc -n traefik
        return 1
    fi
    
    log_success "ACME storage PVC is bound"
    
    # Check if acme.json file exists and has content
    local traefik_pod
    traefik_pod=$(k3s kubectl get pods -n traefik -l app.kubernetes.io/name=traefik -o jsonpath='{.items[0].metadata.name}')
    
    if k3s kubectl exec -n traefik "$traefik_pod" -- test -f /data/acme.json; then
        local acme_size
        acme_size=$(k3s kubectl exec -n traefik "$traefik_pod" -- stat -c%s /data/acme.json)
        if [[ $acme_size -gt 10 ]]; then
            log_success "ACME storage file exists and has content ($acme_size bytes)"
            
            # Show ACME file content (without private keys)
            log_info "ACME certificates summary:"
            k3s kubectl exec -n traefik "$traefik_pod" -- cat /data/acme.json | jq -r '.letsencrypt.Certificates[]? | "Domain: \(.domain.main), Expires: \(.certificate | @base64d | split("\n")[1] | split("=")[1])"' 2>/dev/null || log_warning "Could not parse ACME file"
        else
            log_warning "ACME storage file exists but is empty or very small ($acme_size bytes)"
        fi
    else
        log_warning "ACME storage file does not exist yet"
    fi
}

# Check ingress configuration
check_ingress_config() {
    log_info "Checking ingress configuration..."
    
    # Check if ingress exists
    if ! k3s kubectl get ingress -n headscale-vpn headscale-ingress &>/dev/null; then
        log_error "Headscale ingress not found"
        return 1
    fi
    
    # Show ingress details
    log_info "Ingress configuration:"
    k3s kubectl get ingress -n headscale-vpn headscale-ingress -o yaml | grep -A 20 "spec:"
    
    # Check ingress annotations
    log_info "Checking ingress annotations..."
    local cert_resolver
    cert_resolver=$(k3s kubectl get ingress -n headscale-vpn headscale-ingress -o jsonpath='{.metadata.annotations.traefik\.ingress\.kubernetes\.io/router\.tls\.certresolver}' 2>/dev/null || echo "")
    
    if [[ "$cert_resolver" == "letsencrypt" ]]; then
        log_success "Ingress is configured to use Let's Encrypt cert resolver"
    else
        log_error "Ingress is not configured to use Let's Encrypt cert resolver (found: '$cert_resolver')"
    fi
    
    # Check if TLS secret is specified (should not be for ACME)
    local tls_secret
    tls_secret=$(k3s kubectl get ingress -n headscale-vpn headscale-ingress -o jsonpath='{.spec.tls[0].secretName}' 2>/dev/null || echo "")
    
    if [[ -n "$tls_secret" ]]; then
        log_warning "Ingress specifies TLS secret '$tls_secret' - this may conflict with ACME"
    else
        log_success "Ingress does not specify TLS secret - ACME will handle certificate"
    fi
}

# Check certificate status
check_certificate_status() {
    log_info "Checking certificate status for headscale.${DOMAIN}..."
    
    # Try to get certificate info using openssl
    if command -v openssl &> /dev/null; then
        log_info "Testing TLS connection..."
        if timeout 10 openssl s_client -connect "headscale.${DOMAIN}:443" -servername "headscale.${DOMAIN}" </dev/null 2>/dev/null | openssl x509 -noout -text 2>/dev/null; then
            log_info "Certificate details:"
            timeout 10 openssl s_client -connect "headscale.${DOMAIN}:443" -servername "headscale.${DOMAIN}" </dev/null 2>/dev/null | openssl x509 -noout -issuer -subject -dates 2>/dev/null || log_warning "Could not retrieve certificate details"
        else
            log_warning "Could not establish TLS connection to headscale.${DOMAIN}:443"
        fi
    else
        log_warning "openssl not available for certificate testing"
    fi
}

# Check DNS resolution
check_dns() {
    log_info "Checking DNS resolution for headscale.${DOMAIN}..."
    
    if command -v nslookup &> /dev/null; then
        if nslookup "headscale.${DOMAIN}" &>/dev/null; then
            log_success "DNS resolution successful"
            nslookup "headscale.${DOMAIN}" | grep -A 2 "Name:"
        else
            log_error "DNS resolution failed for headscale.${DOMAIN}"
        fi
    elif command -v dig &> /dev/null; then
        if dig "headscale.${DOMAIN}" +short | grep -q .; then
            log_success "DNS resolution successful"
            dig "headscale.${DOMAIN}" +short
        else
            log_error "DNS resolution failed for headscale.${DOMAIN}"
        fi
    else
        log_warning "No DNS tools available for testing"
    fi
}

# Show troubleshooting tips
show_troubleshooting_tips() {
    echo
    log_info "Troubleshooting Tips:"
    echo "1. Ensure DNS points to your server's public IP"
    echo "2. Verify ports 80 and 443 are accessible from the internet"
    echo "3. Check that no other services are using ports 80/443"
    echo "4. Let's Encrypt rate limits: 5 failures per hour, 50 certificates per week"
    echo "5. Check Traefik logs: k3s kubectl logs -f -n traefik -l app.kubernetes.io/name=traefik"
    echo "6. Force certificate renewal by deleting ACME storage and restarting Traefik"
    echo
    log_info "Useful Commands:"
    echo "- View Traefik dashboard: kubectl port-forward -n traefik svc/traefik 9000:9000"
    echo "- Delete ACME storage: k3s kubectl delete pvc -n traefik traefik-acme-storage"
    echo "- Restart Traefik: k3s kubectl rollout restart deployment -n traefik traefik"
    echo "- Check ingress events: k3s kubectl describe ingress -n headscale-vpn headscale-ingress"
}

# Main function
main() {
    log_info "Starting TLS certificate troubleshooting..."
    echo
    
    load_environment
    echo
    
    check_traefik_status
    echo
    
    check_acme_storage
    echo
    
    check_ingress_config
    echo
    
    check_dns
    echo
    
    check_certificate_status
    echo
    
    show_troubleshooting_tips
    
    log_success "TLS troubleshooting completed"
}

# Run main function
main "$@"