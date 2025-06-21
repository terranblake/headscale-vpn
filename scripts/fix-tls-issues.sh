#!/bin/bash

# Automatic TLS Issue Fix Script
# This script attempts to automatically fix common TLS certificate issues

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_debug() { echo -e "${PURPLE}[DEBUG]${NC} $1"; }
log_section() { echo -e "${CYAN}[SECTION]${NC} $1"; }

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
K8S_DIR="$PROJECT_ROOT/k8s"

# Global variables
DOMAIN=""
ACME_EMAIL=""
DRY_RUN=false
FORCE_RENEWAL=false

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --force-renewal)
                FORCE_RENEWAL=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Show help
show_help() {
    echo "TLS Issue Fix Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --dry-run         Show what would be done without making changes"
    echo "  --force-renewal   Force certificate renewal even if not needed"
    echo "  -h, --help        Show this help message"
    echo ""
    echo "This script automatically fixes common TLS certificate issues:"
    echo "  - Removes conflicting TLS secrets from ingress"
    echo "  - Ensures proper ACME configuration"
    echo "  - Cleans up old certificates"
    echo "  - Restarts Traefik if needed"
}

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
    
    # Validate required variables
    local required_vars=("DOMAIN" "ACME_EMAIL")
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log_error "Required environment variable $var is not set"
            exit 1
        fi
    done
    
    DOMAIN="${DOMAIN}"
    ACME_EMAIL="${ACME_EMAIL}"
    
    log_success "Environment variables loaded"
    log_info "Domain: $DOMAIN"
    log_info "ACME Email: $ACME_EMAIL"
}

# Execute command with dry-run support
execute_cmd() {
    local cmd="$1"
    local description="$2"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would execute: $description"
        log_debug "[DRY-RUN] Command: $cmd"
    else
        log_info "Executing: $description"
        eval "$cmd"
    fi
}

# Fix ingress configuration
fix_ingress_config() {
    log_section "1. FIXING INGRESS CONFIGURATION"
    
    # Check if ingress exists
    if ! k3s kubectl get ingress -n headscale-vpn headscale-ingress &>/dev/null; then
        log_error "Headscale ingress not found - cannot fix"
        return 1
    fi
    
    # Check for TLS secret in ingress
    local tls_secret
    tls_secret=$(k3s kubectl get ingress -n headscale-vpn headscale-ingress -o jsonpath='{.spec.tls[0].secretName}' 2>/dev/null || echo "")
    
    if [[ -n "$tls_secret" ]]; then
        log_warning "Found conflicting TLS secret in ingress: $tls_secret"
        
        # Remove the secretName from ingress
        execute_cmd "k3s kubectl patch ingress headscale-ingress -n headscale-vpn --type='json' -p='[{\"op\": \"remove\", \"path\": \"/spec/tls/0/secretName\"}]'" \
                   "Remove conflicting TLS secretName from ingress"
        
        log_success "Removed conflicting TLS secret from ingress"
    else
        log_success "Ingress TLS configuration is correct (no conflicting secret)"
    fi
    
    # Check cert resolver annotation
    local cert_resolver
    cert_resolver=$(k3s kubectl get ingress -n headscale-vpn headscale-ingress -o jsonpath='{.metadata.annotations.traefik\.ingress\.kubernetes\.io/router\.tls\.certresolver}' 2>/dev/null || echo "")
    
    if [[ "$cert_resolver" != "letsencrypt" ]]; then
        log_warning "Cert resolver annotation is incorrect: '$cert_resolver'"
        
        execute_cmd "k3s kubectl annotate ingress headscale-ingress -n headscale-vpn traefik.ingress.kubernetes.io/router.tls.certresolver=letsencrypt --overwrite" \
                   "Set correct cert resolver annotation"
        
        log_success "Fixed cert resolver annotation"
    else
        log_success "Cert resolver annotation is correct"
    fi
    
    # Ensure TLS is enabled
    local tls_enabled
    tls_enabled=$(k3s kubectl get ingress -n headscale-vpn headscale-ingress -o jsonpath='{.metadata.annotations.traefik\.ingress\.kubernetes\.io/router\.tls}' 2>/dev/null || echo "")
    
    if [[ "$tls_enabled" != "true" ]]; then
        log_warning "TLS is not enabled in ingress annotations"
        
        execute_cmd "k3s kubectl annotate ingress headscale-ingress -n headscale-vpn traefik.ingress.kubernetes.io/router.tls=true --overwrite" \
                   "Enable TLS in ingress annotations"
        
        log_success "Enabled TLS in ingress"
    else
        log_success "TLS is properly enabled in ingress"
    fi
    
    # Add HTTPS redirect if missing
    local https_redirect
    https_redirect=$(k3s kubectl get ingress -n headscale-vpn headscale-ingress -o jsonpath='{.metadata.annotations.traefik\.ingress\.kubernetes\.io/redirect-to-https}' 2>/dev/null || echo "")
    
    if [[ "$https_redirect" != "true" ]]; then
        log_info "Adding HTTPS redirect annotation"
        
        execute_cmd "k3s kubectl annotate ingress headscale-ingress -n headscale-vpn traefik.ingress.kubernetes.io/redirect-to-https=true --overwrite" \
                   "Add HTTPS redirect annotation"
        
        log_success "Added HTTPS redirect"
    else
        log_success "HTTPS redirect is already configured"
    fi
    
    echo ""
}

# Clean up conflicting TLS secrets
cleanup_tls_secrets() {
    log_section "2. CLEANING UP CONFLICTING TLS SECRETS"
    
    # List all TLS secrets in headscale-vpn namespace
    local tls_secrets
    tls_secrets=$(k3s kubectl get secrets -n headscale-vpn -o jsonpath='{.items[?(@.type=="kubernetes.io/tls")].metadata.name}' 2>/dev/null || echo "")
    
    if [[ -n "$tls_secrets" ]]; then
        log_warning "Found TLS secrets that may conflict with ACME: $tls_secrets"
        
        for secret in $tls_secrets; do
            # Check if this secret is referenced by any ingress
            local secret_used=false
            
            # Check all ingresses for this secret
            while IFS= read -r ingress_line; do
                if [[ -n "$ingress_line" ]] && echo "$ingress_line" | grep -q "$secret"; then
                    secret_used=true
                    break
                fi
            done < <(k3s kubectl get ingress --all-namespaces -o jsonpath='{.items[*].spec.tls[*].secretName}' 2>/dev/null || echo "")
            
            if [[ "$secret_used" == "false" ]]; then
                log_info "Removing unused TLS secret: $secret"
                execute_cmd "k3s kubectl delete secret -n headscale-vpn $secret" \
                           "Delete unused TLS secret: $secret"
            else
                log_warning "TLS secret $secret is still referenced by an ingress - not removing"
            fi
        done
    else
        log_success "No conflicting TLS secrets found"
    fi
    
    # Specifically check for common problematic secret names
    local problematic_secrets=("headscale-tls" "headscale-cert" "letsencrypt-cert")
    
    for secret in "${problematic_secrets[@]}"; do
        if k3s kubectl get secret -n headscale-vpn "$secret" &>/dev/null; then
            log_warning "Found problematic TLS secret: $secret"
            execute_cmd "k3s kubectl delete secret -n headscale-vpn $secret" \
                       "Delete problematic TLS secret: $secret"
        fi
    done
    
    echo ""
}

# Fix Traefik configuration
fix_traefik_config() {
    log_section "3. FIXING TRAEFIK CONFIGURATION"
    
    # Check if Traefik deployment exists
    if ! k3s kubectl get deployment -n traefik traefik &>/dev/null; then
        log_error "Traefik deployment not found"
        return 1
    fi
    
    # Get Traefik pod
    local traefik_pod
    traefik_pod=$(k3s kubectl get pods -n traefik -l app.kubernetes.io/name=traefik -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [[ -z "$traefik_pod" ]]; then
        log_error "Traefik pod not found"
        return 1
    fi
    
    log_success "Found Traefik pod: $traefik_pod"
    
    # Check ACME storage
    if ! k3s kubectl exec -n traefik "$traefik_pod" -- test -f /data/acme.json 2>/dev/null; then
        log_warning "ACME storage file missing"
        
        # Check if ACME PVC exists
        if ! k3s kubectl get pvc -n traefik traefik-acme-storage &>/dev/null; then
            log_info "Creating ACME storage PVC"
            execute_cmd "k3s kubectl apply -f $K8S_DIR/traefik-config.yaml" \
                       "Create ACME storage PVC"
        fi
        
        # Restart Traefik to initialize ACME storage
        log_info "Restarting Traefik to initialize ACME storage"
        execute_cmd "k3s kubectl rollout restart deployment -n traefik traefik" \
                   "Restart Traefik deployment"
        
        if [[ "$DRY_RUN" == "false" ]]; then
            log_info "Waiting for Traefik to be ready..."
            k3s kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=traefik -n traefik --timeout=120s
        fi
    else
        log_success "ACME storage file exists"
        
        # Check ACME file size
        local acme_size
        acme_size=$(k3s kubectl exec -n traefik "$traefik_pod" -- stat -c%s /data/acme.json 2>/dev/null || echo "0")
        
        if [[ $acme_size -lt 10 ]]; then
            log_warning "ACME storage file is empty or very small ($acme_size bytes)"
            
            if [[ "$FORCE_RENEWAL" == "true" ]]; then
                log_info "Force renewal requested - clearing ACME storage"
                execute_cmd "k3s kubectl exec -n traefik $traefik_pod -- rm -f /data/acme.json" \
                           "Clear ACME storage file"
                
                execute_cmd "k3s kubectl rollout restart deployment -n traefik traefik" \
                           "Restart Traefik to trigger certificate request"
            fi
        else
            log_success "ACME storage file has content ($acme_size bytes)"
        fi
    fi
    
    echo ""
}

# Verify and fix Helm values
fix_helm_values() {
    log_section "4. FIXING TRAEFIK HELM VALUES"
    
    # Check if Helm release exists
    if ! helm list -n traefik | grep -q traefik; then
        log_error "Traefik Helm release not found"
        return 1
    fi
    
    log_success "Traefik Helm release found"
    
    # Update Traefik with corrected values
    log_info "Updating Traefik Helm release with corrected values"
    
    local temp_values="/tmp/traefik-values-fixed.yaml"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Process the values file with environment variables
        envsubst < "$K8S_DIR/traefik-values.yaml" > "$temp_values"
        
        # Update the Helm release
        helm upgrade traefik traefik/traefik \
            --namespace traefik \
            --values "$temp_values" \
            --wait --timeout=5m
        
        # Cleanup
        rm -f "$temp_values"
        
        log_success "Traefik Helm release updated"
    else
        log_info "[DRY-RUN] Would update Traefik Helm release with processed values"
    fi
    
    echo ""
}

# Force certificate renewal if needed
force_certificate_renewal() {
    log_section "5. CERTIFICATE RENEWAL"
    
    if [[ "$FORCE_RENEWAL" == "true" ]]; then
        log_warning "Force renewal requested"
        
        # Scale down Traefik
        execute_cmd "k3s kubectl scale deployment -n traefik traefik --replicas=0" \
                   "Scale down Traefik"
        
        if [[ "$DRY_RUN" == "false" ]]; then
            # Wait for Traefik to shut down
            log_info "Waiting for Traefik to shut down..."
            k3s kubectl wait --for=delete pod -l app.kubernetes.io/name=traefik -n traefik --timeout=60s
        fi
        
        # Delete ACME storage
        execute_cmd "k3s kubectl delete pvc -n traefik traefik-acme-storage" \
                   "Delete ACME storage PVC"
        
        if [[ "$DRY_RUN" == "false" ]]; then
            # Wait for PVC deletion
            log_info "Waiting for PVC deletion..."
            while k3s kubectl get pvc -n traefik traefik-acme-storage &>/dev/null; do
                sleep 2
            done
        fi
        
        # Recreate ACME storage
        execute_cmd "k3s kubectl apply -f $K8S_DIR/traefik-config.yaml" \
                   "Recreate ACME storage PVC"
        
        # Scale Traefik back up
        execute_cmd "k3s kubectl scale deployment -n traefik traefik --replicas=1" \
                   "Scale Traefik back up"
        
        if [[ "$DRY_RUN" == "false" ]]; then
            # Wait for Traefik to be ready
            log_info "Waiting for Traefik to be ready..."
            k3s kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=traefik -n traefik --timeout=120s
        fi
        
        log_success "Certificate renewal process completed"
    else
        log_info "Certificate renewal not requested (use --force-renewal to force)"
    fi
    
    echo ""
}

# Verify fixes
verify_fixes() {
    log_section "6. VERIFYING FIXES"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Skipping verification in dry-run mode"
        return 0
    fi
    
    local issues_found=0
    
    # Check ingress configuration
    log_info "Verifying ingress configuration..."
    
    local cert_resolver
    cert_resolver=$(k3s kubectl get ingress -n headscale-vpn headscale-ingress -o jsonpath='{.metadata.annotations.traefik\.ingress\.kubernetes\.io/router\.tls\.certresolver}' 2>/dev/null || echo "")
    
    if [[ "$cert_resolver" == "letsencrypt" ]]; then
        log_success "✓ Cert resolver is correctly set to 'letsencrypt'"
    else
        log_error "✗ Cert resolver is incorrect: '$cert_resolver'"
        ((issues_found++))
    fi
    
    local tls_secret
    tls_secret=$(k3s kubectl get ingress -n headscale-vpn headscale-ingress -o jsonpath='{.spec.tls[0].secretName}' 2>/dev/null || echo "")
    
    if [[ -z "$tls_secret" ]]; then
        log_success "✓ No conflicting TLS secret in ingress"
    else
        log_error "✗ Conflicting TLS secret still present: '$tls_secret'"
        ((issues_found++))
    fi
    
    # Check Traefik status
    log_info "Verifying Traefik status..."
    
    if k3s kubectl get pods -n traefik -l app.kubernetes.io/name=traefik --no-headers | grep -q Running; then
        log_success "✓ Traefik pod is running"
    else
        log_error "✗ Traefik pod is not running"
        ((issues_found++))
    fi
    
    # Check ACME storage
    local traefik_pod
    traefik_pod=$(k3s kubectl get pods -n traefik -l app.kubernetes.io/name=traefik -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [[ -n "$traefik_pod" ]] && k3s kubectl exec -n traefik "$traefik_pod" -- test -f /data/acme.json 2>/dev/null; then
        log_success "✓ ACME storage file exists"
    else
        log_warning "⚠ ACME storage file missing (will be created on first certificate request)"
    fi
    
    # Summary
    if [[ $issues_found -eq 0 ]]; then
        log_success "All fixes verified successfully!"
        log_info "Monitor certificate generation with: k3s kubectl logs -f -n traefik -l app.kubernetes.io/name=traefik"
    else
        log_error "Found $issues_found remaining issues"
        log_info "Run the debug script for detailed analysis: sudo ./scripts/debug-tls.sh"
    fi
    
    echo ""
}

# Main function
main() {
    echo "======================================="
    echo "  TLS AUTOMATIC FIX SCRIPT"
    echo "======================================="
    echo ""
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Running in DRY-RUN mode - no changes will be made"
        echo ""
    fi
    
    load_environment
    fix_ingress_config
    cleanup_tls_secrets
    fix_traefik_config
    fix_helm_values
    force_certificate_renewal
    verify_fixes
    
    log_success "TLS fix process completed!"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        log_info "Next steps:"
        echo "1. Monitor Traefik logs: k3s kubectl logs -f -n traefik -l app.kubernetes.io/name=traefik"
        echo "2. Test certificate: openssl s_client -connect headscale.$DOMAIN:443 -servername headscale.$DOMAIN"
        echo "3. Run debug script if issues persist: sudo ./scripts/debug-tls.sh"
    else
        log_info "Run without --dry-run to apply the fixes"
    fi
    
    echo ""
    echo "======================================="
    echo "  FIX PROCESS COMPLETE"
    echo "======================================="
}

# Check if running with proper permissions
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root (for k3s access)"
    exit 1
fi

# Parse arguments and run
parse_args "$@"
main