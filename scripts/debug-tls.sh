#!/bin/bash

# Comprehensive TLS Debug Script for Traefik + Let's Encrypt
# This script performs deep diagnostics to pinpoint TLS certificate issues

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
DEBUG_OUTPUT_FILE="/tmp/tls-debug-$(date +%Y%m%d-%H%M%S).log"

# Global variables
DOMAIN=""
ACME_EMAIL=""
TRAEFIK_POD=""
HEADSCALE_POD=""

# Initialize debug log
init_debug_log() {
    echo "TLS Debug Report - $(date)" > "$DEBUG_OUTPUT_FILE"
    echo "=======================================" >> "$DEBUG_OUTPUT_FILE"
    echo "" >> "$DEBUG_OUTPUT_FILE"
    log_info "Debug output will be saved to: $DEBUG_OUTPUT_FILE"
}

# Load environment variables
load_environment() {
    log_section "1. ENVIRONMENT VALIDATION"
    
    if [[ ! -f "$PROJECT_ROOT/.env" ]]; then
        log_error ".env file not found at $PROJECT_ROOT/.env"
        echo "ERROR: .env file missing" >> "$DEBUG_OUTPUT_FILE"
        exit 1
    fi
    
    # Source the .env file
    set -a
    source "$PROJECT_ROOT/.env"
    set +a
    
    # Validate required variables
    local required_vars=("DOMAIN" "ACME_EMAIL")
    local missing_vars=()
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            missing_vars+=("$var")
        fi
    done
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_error "Missing required environment variables: ${missing_vars[*]}"
        echo "ERROR: Missing variables: ${missing_vars[*]}" >> "$DEBUG_OUTPUT_FILE"
        exit 1
    fi
    
    DOMAIN="${DOMAIN}"
    ACME_EMAIL="${ACME_EMAIL}"
    
    log_success "Environment variables loaded"
    log_info "Domain: $DOMAIN"
    log_info "ACME Email: $ACME_EMAIL"
    
    {
        echo "Environment Variables:"
        echo "DOMAIN=$DOMAIN"
        echo "ACME_EMAIL=$ACME_EMAIL"
        echo ""
    } >> "$DEBUG_OUTPUT_FILE"
}

# Check system prerequisites
check_prerequisites() {
    log_section "2. SYSTEM PREREQUISITES"
    
    local missing_tools=()
    local tools=("k3s" "kubectl" "helm" "openssl" "curl" "jq" "dig")
    
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_warning "Missing tools: ${missing_tools[*]}"
        echo "WARNING: Missing tools: ${missing_tools[*]}" >> "$DEBUG_OUTPUT_FILE"
    else
        log_success "All required tools are available"
        echo "SUCCESS: All required tools available" >> "$DEBUG_OUTPUT_FILE"
    fi
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root for k3s access"
        echo "ERROR: Not running as root" >> "$DEBUG_OUTPUT_FILE"
        exit 1
    fi
    
    log_success "Running with proper permissions"
    echo ""
}

# Get pod names
get_pod_names() {
    log_section "3. KUBERNETES CLUSTER STATUS"
    
    # Check if k3s is running
    if ! systemctl is-active --quiet k3s; then
        log_error "K3s service is not running"
        echo "ERROR: K3s service not running" >> "$DEBUG_OUTPUT_FILE"
        exit 1
    fi
    
    log_success "K3s service is running"
    
    # Get Traefik pod
    TRAEFIK_POD=$(k3s kubectl get pods -n traefik -l app.kubernetes.io/name=traefik -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [[ -z "$TRAEFIK_POD" ]]; then
        log_error "Traefik pod not found"
        echo "ERROR: Traefik pod not found" >> "$DEBUG_OUTPUT_FILE"
    else
        log_success "Traefik pod found: $TRAEFIK_POD"
        echo "Traefik pod: $TRAEFIK_POD" >> "$DEBUG_OUTPUT_FILE"
    fi
    
    # Get Headscale pod
    HEADSCALE_POD=$(k3s kubectl get pods -n headscale-vpn -l app=headscale -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [[ -z "$HEADSCALE_POD" ]]; then
        log_error "Headscale pod not found"
        echo "ERROR: Headscale pod not found" >> "$DEBUG_OUTPUT_FILE"
    else
        log_success "Headscale pod found: $HEADSCALE_POD"
        echo "Headscale pod: $HEADSCALE_POD" >> "$DEBUG_OUTPUT_FILE"
    fi
    
    # Show all pods status
    log_info "All pods status:"
    {
        echo "All Pods Status:"
        k3s kubectl get pods --all-namespaces -o wide
        echo ""
    } >> "$DEBUG_OUTPUT_FILE"
    
    k3s kubectl get pods --all-namespaces -o wide
    echo ""
}

# Check DNS resolution
check_dns_resolution() {
    log_section "4. DNS RESOLUTION"
    
    local target_domain="headscale.$DOMAIN"
    local dns_success=false
    
    log_info "Testing DNS resolution for $target_domain"
    
    # Test with dig
    if command -v dig &> /dev/null; then
        log_debug "Using dig for DNS lookup..."
        local dig_result
        if dig_result=$(dig "$target_domain" +short 2>&1); then
            if [[ -n "$dig_result" ]]; then
                log_success "DNS resolution successful (dig): $dig_result"
                dns_success=true
                echo "DNS (dig): $dig_result" >> "$DEBUG_OUTPUT_FILE"
            else
                log_warning "DNS resolution returned empty result (dig)"
                echo "DNS (dig): Empty result" >> "$DEBUG_OUTPUT_FILE"
            fi
        else
            log_error "DNS resolution failed (dig): $dig_result"
            echo "DNS (dig): FAILED - $dig_result" >> "$DEBUG_OUTPUT_FILE"
        fi
    fi
    
    # Test with nslookup
    if command -v nslookup &> /dev/null; then
        log_debug "Using nslookup for DNS lookup..."
        local nslookup_result
        if nslookup_result=$(nslookup "$target_domain" 2>&1); then
            local ip_address
            ip_address=$(echo "$nslookup_result" | grep -A 1 "Name:" | grep "Address:" | awk '{print $2}' | head -1)
            if [[ -n "$ip_address" ]]; then
                log_success "DNS resolution successful (nslookup): $ip_address"
                dns_success=true
                echo "DNS (nslookup): $ip_address" >> "$DEBUG_OUTPUT_FILE"
            else
                log_warning "DNS resolution returned no IP (nslookup)"
                echo "DNS (nslookup): No IP found" >> "$DEBUG_OUTPUT_FILE"
            fi
        else
            log_error "DNS resolution failed (nslookup)"
            echo "DNS (nslookup): FAILED" >> "$DEBUG_OUTPUT_FILE"
        fi
    fi
    
    # Test with getent
    if command -v getent &> /dev/null; then
        log_debug "Using getent for DNS lookup..."
        local getent_result
        if getent_result=$(getent hosts "$target_domain" 2>&1); then
            local ip_address
            ip_address=$(echo "$getent_result" | awk '{print $1}')
            if [[ -n "$ip_address" ]]; then
                log_success "DNS resolution successful (getent): $ip_address"
                dns_success=true
                echo "DNS (getent): $ip_address" >> "$DEBUG_OUTPUT_FILE"
            fi
        else
            log_error "DNS resolution failed (getent)"
            echo "DNS (getent): FAILED" >> "$DEBUG_OUTPUT_FILE"
        fi
    fi
    
    if [[ "$dns_success" == "false" ]]; then
        log_error "DNS resolution failed with all methods"
        log_error "This will prevent Let's Encrypt ACME challenges from working"
        echo "CRITICAL: DNS resolution completely failed" >> "$DEBUG_OUTPUT_FILE"
    fi
    
    echo ""
}

# Check network connectivity
check_network_connectivity() {
    log_section "5. NETWORK CONNECTIVITY"
    
    local target_domain="headscale.$DOMAIN"
    
    # Test HTTP connectivity (port 80)
    log_info "Testing HTTP connectivity (port 80)..."
    if timeout 10 curl -s -I "http://$target_domain" &>/dev/null; then
        log_success "HTTP (port 80) is accessible"
        echo "HTTP (80): Accessible" >> "$DEBUG_OUTPUT_FILE"
    else
        log_error "HTTP (port 80) is not accessible"
        echo "HTTP (80): NOT accessible" >> "$DEBUG_OUTPUT_FILE"
    fi
    
    # Test HTTPS connectivity (port 443)
    log_info "Testing HTTPS connectivity (port 443)..."
    if timeout 10 curl -s -I "https://$target_domain" -k &>/dev/null; then
        log_success "HTTPS (port 443) is accessible"
        echo "HTTPS (443): Accessible" >> "$DEBUG_OUTPUT_FILE"
    else
        log_error "HTTPS (port 443) is not accessible"
        echo "HTTPS (443): NOT accessible" >> "$DEBUG_OUTPUT_FILE"
    fi
    
    # Test if ports are listening locally
    log_info "Checking local port bindings..."
    local port_80_status="CLOSED"
    local port_443_status="CLOSED"
    
    if ss -tlnp | grep -q ":80 "; then
        port_80_status="OPEN"
        log_success "Port 80 is listening locally"
    else
        log_error "Port 80 is not listening locally"
    fi
    
    if ss -tlnp | grep -q ":443 "; then
        port_443_status="OPEN"
        log_success "Port 443 is listening locally"
    else
        log_error "Port 443 is not listening locally"
    fi
    
    {
        echo "Local Ports:"
        echo "Port 80: $port_80_status"
        echo "Port 443: $port_443_status"
        echo ""
        echo "Detailed port information:"
        ss -tlnp | grep -E ":(80|443) "
        echo ""
    } >> "$DEBUG_OUTPUT_FILE"
    
    echo ""
}

# Analyze Traefik configuration
analyze_traefik_config() {
    log_section "6. TRAEFIK CONFIGURATION ANALYSIS"
    
    if [[ -z "$TRAEFIK_POD" ]]; then
        log_error "Cannot analyze Traefik config - pod not found"
        echo "ERROR: Traefik pod not available for analysis" >> "$DEBUG_OUTPUT_FILE"
        return 1
    fi
    
    # Check Traefik deployment
    log_info "Analyzing Traefik deployment..."
    {
        echo "Traefik Deployment:"
        k3s kubectl describe deployment -n traefik traefik
        echo ""
    } >> "$DEBUG_OUTPUT_FILE"
    
    # Check Traefik service
    log_info "Analyzing Traefik service..."
    {
        echo "Traefik Service:"
        k3s kubectl describe service -n traefik traefik
        echo ""
    } >> "$DEBUG_OUTPUT_FILE"
    
    # Check Traefik pod details
    log_info "Analyzing Traefik pod..."
    {
        echo "Traefik Pod Details:"
        k3s kubectl describe pod -n traefik "$TRAEFIK_POD"
        echo ""
    } >> "$DEBUG_OUTPUT_FILE"
    
    # Check Traefik configuration
    log_info "Extracting Traefik configuration..."
    if k3s kubectl exec -n traefik "$TRAEFIK_POD" -- cat /etc/traefik/traefik.yml &>/dev/null; then
        {
            echo "Traefik Configuration (traefik.yml):"
            k3s kubectl exec -n traefik "$TRAEFIK_POD" -- cat /etc/traefik/traefik.yml
            echo ""
        } >> "$DEBUG_OUTPUT_FILE"
    else
        echo "Traefik Configuration: Not accessible or doesn't exist" >> "$DEBUG_OUTPUT_FILE"
    fi
    
    # Check for dynamic configuration
    log_info "Checking Traefik dynamic configuration..."
    if k3s kubectl exec -n traefik "$TRAEFIK_POD" -- find /etc/traefik -name "*.yml" -o -name "*.yaml" 2>/dev/null; then
        {
            echo "Traefik Dynamic Configuration Files:"
            k3s kubectl exec -n traefik "$TRAEFIK_POD" -- find /etc/traefik -name "*.yml" -o -name "*.yaml" 2>/dev/null | while read -r file; do
                echo "=== $file ==="
                k3s kubectl exec -n traefik "$TRAEFIK_POD" -- cat "$file" 2>/dev/null || echo "Cannot read $file"
                echo ""
            done
        } >> "$DEBUG_OUTPUT_FILE"
    fi
    
    echo ""
}

# Check ACME storage and certificates
check_acme_storage() {
    log_section "7. ACME STORAGE AND CERTIFICATES"
    
    if [[ -z "$TRAEFIK_POD" ]]; then
        log_error "Cannot check ACME storage - Traefik pod not found"
        echo "ERROR: Traefik pod not available for ACME analysis" >> "$DEBUG_OUTPUT_FILE"
        return 1
    fi
    
    # Check ACME PVC
    log_info "Checking ACME PVC status..."
    local pvc_status
    pvc_status=$(k3s kubectl get pvc -n traefik traefik-acme-storage -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
    
    if [[ "$pvc_status" == "Bound" ]]; then
        log_success "ACME PVC is bound"
        echo "ACME PVC: Bound" >> "$DEBUG_OUTPUT_FILE"
    else
        log_error "ACME PVC is not bound (status: $pvc_status)"
        echo "ACME PVC: $pvc_status" >> "$DEBUG_OUTPUT_FILE"
        
        {
            echo "ACME PVC Details:"
            k3s kubectl describe pvc -n traefik traefik-acme-storage
            echo ""
        } >> "$DEBUG_OUTPUT_FILE"
    fi
    
    # Check ACME file
    log_info "Checking ACME storage file..."
    if k3s kubectl exec -n traefik "$TRAEFIK_POD" -- test -f /data/acme.json 2>/dev/null; then
        local acme_size
        acme_size=$(k3s kubectl exec -n traefik "$TRAEFIK_POD" -- stat -c%s /data/acme.json 2>/dev/null || echo "0")
        
        if [[ $acme_size -gt 10 ]]; then
            log_success "ACME file exists and has content ($acme_size bytes)"
            echo "ACME File: Exists ($acme_size bytes)" >> "$DEBUG_OUTPUT_FILE"
            
            # Parse ACME file content
            log_info "Analyzing ACME file content..."
            {
                echo "ACME File Content Analysis:"
                k3s kubectl exec -n traefik "$TRAEFIK_POD" -- cat /data/acme.json | jq . 2>/dev/null || echo "Cannot parse ACME JSON"
                echo ""
            } >> "$DEBUG_OUTPUT_FILE"
            
            # Extract certificate information
            if k3s kubectl exec -n traefik "$TRAEFIK_POD" -- cat /data/acme.json | jq -e '.letsencrypt.Certificates' &>/dev/null; then
                log_info "Found certificates in ACME storage:"
                k3s kubectl exec -n traefik "$TRAEFIK_POD" -- cat /data/acme.json | jq -r '.letsencrypt.Certificates[]? | "Domain: \(.domain.main), Store: \(.store)"' 2>/dev/null || log_warning "Could not parse certificate details"
            else
                log_warning "No certificates found in ACME storage"
                echo "ACME Certificates: None found" >> "$DEBUG_OUTPUT_FILE"
            fi
        else
            log_warning "ACME file exists but is empty or very small ($acme_size bytes)"
            echo "ACME File: Empty or small ($acme_size bytes)" >> "$DEBUG_OUTPUT_FILE"
        fi
    else
        log_error "ACME file does not exist"
        echo "ACME File: Does not exist" >> "$DEBUG_OUTPUT_FILE"
    fi
    
    # Check file permissions
    log_info "Checking ACME file permissions..."
    if k3s kubectl exec -n traefik "$TRAEFIK_POD" -- ls -la /data/ 2>/dev/null; then
        {
            echo "ACME Directory Permissions:"
            k3s kubectl exec -n traefik "$TRAEFIK_POD" -- ls -la /data/
            echo ""
        } >> "$DEBUG_OUTPUT_FILE"
    fi
    
    echo ""
}

# Analyze ingress configuration
analyze_ingress_config() {
    log_section "8. INGRESS CONFIGURATION ANALYSIS"
    
    # Check if ingress exists
    if ! k3s kubectl get ingress -n headscale-vpn headscale-ingress &>/dev/null; then
        log_error "Headscale ingress not found"
        echo "ERROR: Headscale ingress not found" >> "$DEBUG_OUTPUT_FILE"
        return 1
    fi
    
    log_success "Headscale ingress found"
    
    # Detailed ingress analysis
    {
        echo "Ingress Configuration:"
        k3s kubectl get ingress -n headscale-vpn headscale-ingress -o yaml
        echo ""
        
        echo "Ingress Description:"
        k3s kubectl describe ingress -n headscale-vpn headscale-ingress
        echo ""
    } >> "$DEBUG_OUTPUT_FILE"
    
    # Check ingress annotations
    log_info "Analyzing ingress annotations..."
    local cert_resolver
    cert_resolver=$(k3s kubectl get ingress -n headscale-vpn headscale-ingress -o jsonpath='{.metadata.annotations.traefik\.ingress\.kubernetes\.io/router\.tls\.certresolver}' 2>/dev/null || echo "")
    
    if [[ "$cert_resolver" == "letsencrypt" ]]; then
        log_success "Ingress is configured to use Let's Encrypt cert resolver"
        echo "Cert Resolver: letsencrypt (CORRECT)" >> "$DEBUG_OUTPUT_FILE"
    else
        log_error "Ingress is not configured to use Let's Encrypt cert resolver (found: '$cert_resolver')"
        echo "Cert Resolver: '$cert_resolver' (INCORRECT)" >> "$DEBUG_OUTPUT_FILE"
    fi
    
    # Check TLS configuration
    local tls_secret
    tls_secret=$(k3s kubectl get ingress -n headscale-vpn headscale-ingress -o jsonpath='{.spec.tls[0].secretName}' 2>/dev/null || echo "")
    
    if [[ -n "$tls_secret" ]]; then
        log_error "Ingress specifies TLS secret '$tls_secret' - this conflicts with ACME"
        echo "TLS Secret: '$tls_secret' (CONFLICTS WITH ACME)" >> "$DEBUG_OUTPUT_FILE"
        
        # Check if the secret exists
        if k3s kubectl get secret -n headscale-vpn "$tls_secret" &>/dev/null; then
            log_warning "TLS secret '$tls_secret' exists - this will override ACME certificates"
            {
                echo "Conflicting TLS Secret Details:"
                k3s kubectl describe secret -n headscale-vpn "$tls_secret"
                echo ""
            } >> "$DEBUG_OUTPUT_FILE"
        else
            log_warning "TLS secret '$tls_secret' does not exist but is referenced"
            echo "TLS Secret Status: Referenced but does not exist" >> "$DEBUG_OUTPUT_FILE"
        fi
    else
        log_success "Ingress does not specify TLS secret - ACME will handle certificates"
        echo "TLS Secret: None (CORRECT for ACME)" >> "$DEBUG_OUTPUT_FILE"
    fi
    
    # Check ingress class
    local ingress_class
    ingress_class=$(k3s kubectl get ingress -n headscale-vpn headscale-ingress -o jsonpath='{.spec.ingressClassName}' 2>/dev/null || echo "")
    
    if [[ "$ingress_class" == "traefik" ]]; then
        log_success "Ingress class is set to 'traefik'"
        echo "Ingress Class: traefik (CORRECT)" >> "$DEBUG_OUTPUT_FILE"
    else
        log_warning "Ingress class is '$ingress_class' (expected 'traefik')"
        echo "Ingress Class: '$ingress_class' (UNEXPECTED)" >> "$DEBUG_OUTPUT_FILE"
    fi
    
    echo ""
}

# Check Traefik logs for ACME activity
analyze_traefik_logs() {
    log_section "9. TRAEFIK LOGS ANALYSIS"
    
    if [[ -z "$TRAEFIK_POD" ]]; then
        log_error "Cannot analyze Traefik logs - pod not found"
        echo "ERROR: Traefik pod not available for log analysis" >> "$DEBUG_OUTPUT_FILE"
        return 1
    fi
    
    log_info "Analyzing Traefik logs for ACME activity..."
    
    # Get recent logs
    {
        echo "Recent Traefik Logs (last 100 lines):"
        k3s kubectl logs -n traefik "$TRAEFIK_POD" --tail=100
        echo ""
    } >> "$DEBUG_OUTPUT_FILE"
    
    # Look for ACME-specific messages
    log_info "Searching for ACME-related log entries..."
    local acme_logs
    acme_logs=$(k3s kubectl logs -n traefik "$TRAEFIK_POD" --tail=500 | grep -i "acme\|certificate\|letsencrypt\|challenge" || echo "")
    
    if [[ -n "$acme_logs" ]]; then
        log_success "Found ACME-related log entries:"
        echo "$acme_logs"
        {
            echo "ACME-Related Log Entries:"
            echo "$acme_logs"
            echo ""
        } >> "$DEBUG_OUTPUT_FILE"
    else
        log_warning "No ACME-related log entries found"
        echo "ACME Logs: None found" >> "$DEBUG_OUTPUT_FILE"
    fi
    
    # Look for error messages
    log_info "Searching for error messages..."
    local error_logs
    error_logs=$(k3s kubectl logs -n traefik "$TRAEFIK_POD" --tail=500 | grep -i "error\|fail\|denied\|refused" || echo "")
    
    if [[ -n "$error_logs" ]]; then
        log_warning "Found error messages in logs:"
        echo "$error_logs"
        {
            echo "Error Messages in Logs:"
            echo "$error_logs"
            echo ""
        } >> "$DEBUG_OUTPUT_FILE"
    else
        log_success "No error messages found in recent logs"
        echo "Error Messages: None found" >> "$DEBUG_OUTPUT_FILE"
    fi
    
    echo ""
}

# Test certificate directly
test_certificate_directly() {
    log_section "10. DIRECT CERTIFICATE TESTING"
    
    local target_domain="headscale.$DOMAIN"
    
    log_info "Testing TLS certificate for $target_domain..."
    
    # Test with openssl s_client
    if command -v openssl &> /dev/null; then
        log_info "Using openssl to test certificate..."
        
        local cert_info
        if cert_info=$(timeout 15 openssl s_client -connect "$target_domain:443" -servername "$target_domain" </dev/null 2>/dev/null); then
            log_success "TLS connection established"
            
            # Extract certificate details
            local cert_details
            if cert_details=$(echo "$cert_info" | openssl x509 -noout -text 2>/dev/null); then
                log_info "Certificate details extracted"
                
                # Get issuer
                local issuer
                issuer=$(echo "$cert_details" | grep "Issuer:" | head -1)
                log_info "Certificate issuer: $issuer"
                
                # Get subject
                local subject
                subject=$(echo "$cert_details" | grep "Subject:" | head -1)
                log_info "Certificate subject: $subject"
                
                # Get validity dates
                local not_before not_after
                not_before=$(echo "$cert_details" | grep "Not Before:" | head -1)
                not_after=$(echo "$cert_details" | grep "Not After:" | head -1)
                log_info "Certificate validity: $not_before"
                log_info "Certificate expires: $not_after"
                
                # Check if it's a Let's Encrypt certificate
                if echo "$issuer" | grep -qi "let's encrypt"; then
                    log_success "Certificate is issued by Let's Encrypt"
                    echo "Certificate Type: Let's Encrypt (CORRECT)" >> "$DEBUG_OUTPUT_FILE"
                else
                    log_warning "Certificate is NOT issued by Let's Encrypt"
                    echo "Certificate Type: NOT Let's Encrypt (ISSUE)" >> "$DEBUG_OUTPUT_FILE"
                fi
                
                {
                    echo "Certificate Details:"
                    echo "$issuer"
                    echo "$subject"
                    echo "$not_before"
                    echo "$not_after"
                    echo ""
                    echo "Full Certificate Details:"
                    echo "$cert_details"
                    echo ""
                } >> "$DEBUG_OUTPUT_FILE"
            else
                log_error "Could not extract certificate details"
                echo "Certificate Details: Could not extract" >> "$DEBUG_OUTPUT_FILE"
            fi
        else
            log_error "Could not establish TLS connection to $target_domain:443"
            echo "TLS Connection: FAILED" >> "$DEBUG_OUTPUT_FILE"
        fi
    else
        log_warning "openssl not available for certificate testing"
        echo "Certificate Testing: openssl not available" >> "$DEBUG_OUTPUT_FILE"
    fi
    
    # Test with curl
    if command -v curl &> /dev/null; then
        log_info "Testing certificate with curl..."
        
        local curl_output
        if curl_output=$(curl -I "https://$target_domain" -v 2>&1); then
            log_success "Curl connection successful"
            
            # Check for certificate information in curl output
            if echo "$curl_output" | grep -qi "let's encrypt"; then
                log_success "Curl confirms Let's Encrypt certificate"
                echo "Curl Certificate Check: Let's Encrypt confirmed" >> "$DEBUG_OUTPUT_FILE"
            else
                log_warning "Curl does not show Let's Encrypt certificate"
                echo "Curl Certificate Check: Let's Encrypt NOT confirmed" >> "$DEBUG_OUTPUT_FILE"
            fi
            
            {
                echo "Curl Output:"
                echo "$curl_output"
                echo ""
            } >> "$DEBUG_OUTPUT_FILE"
        else
            log_error "Curl connection failed"
            echo "Curl Connection: FAILED" >> "$DEBUG_OUTPUT_FILE"
        fi
    fi
    
    echo ""
}

# Check Kubernetes secrets
check_kubernetes_secrets() {
    log_section "11. KUBERNETES SECRETS ANALYSIS"
    
    log_info "Checking for TLS-related secrets..."
    
    # List all secrets in headscale-vpn namespace
    {
        echo "All Secrets in headscale-vpn namespace:"
        k3s kubectl get secrets -n headscale-vpn -o wide
        echo ""
    } >> "$DEBUG_OUTPUT_FILE"
    
    # Check for TLS secrets specifically
    local tls_secrets
    tls_secrets=$(k3s kubectl get secrets -n headscale-vpn -o jsonpath='{.items[?(@.type=="kubernetes.io/tls")].metadata.name}' 2>/dev/null || echo "")
    
    if [[ -n "$tls_secrets" ]]; then
        log_warning "Found TLS secrets that might conflict with ACME: $tls_secrets"
        echo "Conflicting TLS Secrets: $tls_secrets" >> "$DEBUG_OUTPUT_FILE"
        
        for secret in $tls_secrets; do
            log_info "Analyzing TLS secret: $secret"
            {
                echo "TLS Secret '$secret' Details:"
                k3s kubectl describe secret -n headscale-vpn "$secret"
                echo ""
            } >> "$DEBUG_OUTPUT_FILE"
        done
    else
        log_success "No conflicting TLS secrets found"
        echo "Conflicting TLS Secrets: None" >> "$DEBUG_OUTPUT_FILE"
    fi
    
    # Check for ACME-generated secrets
    local acme_secrets
    acme_secrets=$(k3s kubectl get secrets --all-namespaces -o jsonpath='{.items[?(@.metadata.annotations.cert-manager\.io/issuer-name)].metadata.name}' 2>/dev/null || echo "")
    
    if [[ -n "$acme_secrets" ]]; then
        log_info "Found ACME-generated secrets: $acme_secrets"
        echo "ACME Secrets: $acme_secrets" >> "$DEBUG_OUTPUT_FILE"
    else
        log_info "No ACME-generated secrets found"
        echo "ACME Secrets: None" >> "$DEBUG_OUTPUT_FILE"
    fi
    
    echo ""
}

# Check Traefik dashboard
check_traefik_dashboard() {
    log_section "12. TRAEFIK DASHBOARD ACCESS"
    
    if [[ -z "$TRAEFIK_POD" ]]; then
        log_error "Cannot check Traefik dashboard - pod not found"
        echo "ERROR: Traefik pod not available for dashboard check" >> "$DEBUG_OUTPUT_FILE"
        return 1
    fi
    
    log_info "Checking Traefik dashboard configuration..."
    
    # Check if dashboard is enabled
    local dashboard_enabled
    if k3s kubectl exec -n traefik "$TRAEFIK_POD" -- grep -r "dashboard.*true" /etc/traefik/ 2>/dev/null; then
        dashboard_enabled="true"
        log_success "Traefik dashboard is enabled"
        echo "Traefik Dashboard: Enabled" >> "$DEBUG_OUTPUT_FILE"
    else
        dashboard_enabled="false"
        log_warning "Traefik dashboard may not be enabled"
        echo "Traefik Dashboard: Not enabled or not found" >> "$DEBUG_OUTPUT_FILE"
    fi
    
    # Try to access dashboard API
    log_info "Testing Traefik API access..."
    if k3s kubectl port-forward -n traefik "$TRAEFIK_POD" 8080:8080 &>/dev/null & then
        local port_forward_pid=$!
        sleep 2
        
        if curl -s "http://localhost:8080/api/rawdata" &>/dev/null; then
            log_success "Traefik API is accessible"
            echo "Traefik API: Accessible" >> "$DEBUG_OUTPUT_FILE"
            
            # Get router information
            local routers
            if routers=$(curl -s "http://localhost:8080/api/http/routers" 2>/dev/null); then
                {
                    echo "Traefik HTTP Routers:"
                    echo "$routers" | jq . 2>/dev/null || echo "$routers"
                    echo ""
                } >> "$DEBUG_OUTPUT_FILE"
            fi
            
            # Get service information
            local services
            if services=$(curl -s "http://localhost:8080/api/http/services" 2>/dev/null); then
                {
                    echo "Traefik HTTP Services:"
                    echo "$services" | jq . 2>/dev/null || echo "$services"
                    echo ""
                } >> "$DEBUG_OUTPUT_FILE"
            fi
        else
            log_warning "Traefik API is not accessible"
            echo "Traefik API: Not accessible" >> "$DEBUG_OUTPUT_FILE"
        fi
        
        kill $port_forward_pid 2>/dev/null || true
    fi
    
    echo ""
}

# Generate recommendations
generate_recommendations() {
    log_section "13. RECOMMENDATIONS AND NEXT STEPS"
    
    log_info "Analyzing findings and generating recommendations..."
    
    local recommendations=()
    
    # Check for common issues and generate recommendations
    
    # DNS issues
    if ! dig "headscale.$DOMAIN" +short | grep -q .; then
        recommendations+=("🔴 CRITICAL: Fix DNS resolution for headscale.$DOMAIN - point it to your server's public IP")
    fi
    
    # Port accessibility
    if ! timeout 10 curl -s -I "http://headscale.$DOMAIN" &>/dev/null; then
        recommendations+=("🔴 CRITICAL: Ensure port 80 is accessible from the internet for ACME HTTP-01 challenge")
    fi
    
    if ! timeout 10 curl -s -I "https://headscale.$DOMAIN" -k &>/dev/null; then
        recommendations+=("🔴 CRITICAL: Ensure port 443 is accessible from the internet")
    fi
    
    # Traefik pod issues
    if [[ -z "$TRAEFIK_POD" ]]; then
        recommendations+=("🔴 CRITICAL: Traefik pod is not running - check deployment and logs")
    fi
    
    # ACME storage issues
    if [[ -n "$TRAEFIK_POD" ]] && ! k3s kubectl exec -n traefik "$TRAEFIK_POD" -- test -f /data/acme.json 2>/dev/null; then
        recommendations+=("🟡 WARNING: ACME storage file missing - certificates may need to be requested")
    fi
    
    # Ingress configuration issues
    local cert_resolver
    cert_resolver=$(k3s kubectl get ingress -n headscale-vpn headscale-ingress -o jsonpath='{.metadata.annotations.traefik\.ingress\.kubernetes\.io/router\.tls\.certresolver}' 2>/dev/null || echo "")
    if [[ "$cert_resolver" != "letsencrypt" ]]; then
        recommendations+=("🔴 CRITICAL: Ingress is not configured to use Let's Encrypt cert resolver")
    fi
    
    local tls_secret
    tls_secret=$(k3s kubectl get ingress -n headscale-vpn headscale-ingress -o jsonpath='{.spec.tls[0].secretName}' 2>/dev/null || echo "")
    if [[ -n "$tls_secret" ]]; then
        recommendations+=("🔴 CRITICAL: Remove secretName from ingress TLS config - it conflicts with ACME")
    fi
    
    # Certificate type check
    if command -v openssl &> /dev/null; then
        local cert_info
        if cert_info=$(timeout 15 openssl s_client -connect "headscale.$DOMAIN:443" -servername "headscale.$DOMAIN" </dev/null 2>/dev/null | openssl x509 -noout -issuer 2>/dev/null); then
            if ! echo "$cert_info" | grep -qi "let's encrypt"; then
                recommendations+=("🟡 WARNING: Current certificate is not from Let's Encrypt - may be self-signed")
            fi
        fi
    fi
    
    # Display recommendations
    if [[ ${#recommendations[@]} -gt 0 ]]; then
        log_warning "Found ${#recommendations[@]} issues that need attention:"
        {
            echo "RECOMMENDATIONS:"
            for rec in "${recommendations[@]}"; do
                echo "$rec"
            done
            echo ""
        } >> "$DEBUG_OUTPUT_FILE"
        
        for rec in "${recommendations[@]}"; do
            echo "$rec"
        done
    else
        log_success "No critical issues found - configuration appears correct"
        echo "RECOMMENDATIONS: No critical issues found" >> "$DEBUG_OUTPUT_FILE"
    fi
    
    # General troubleshooting steps
    log_info "General troubleshooting steps:"
    echo "1. Verify DNS points to your server's public IP address"
    echo "2. Ensure firewall allows ports 80 and 443 from the internet"
    echo "3. Check that no other services are using ports 80/443"
    echo "4. Monitor Traefik logs: k3s kubectl logs -f -n traefik -l app.kubernetes.io/name=traefik"
    echo "5. If needed, force certificate renewal: sudo ./scripts/renew-certificates.sh"
    echo "6. Check Let's Encrypt rate limits if requests are failing"
    
    {
        echo "GENERAL TROUBLESHOOTING STEPS:"
        echo "1. Verify DNS points to your server's public IP address"
        echo "2. Ensure firewall allows ports 80 and 443 from the internet"
        echo "3. Check that no other services are using ports 80/443"
        echo "4. Monitor Traefik logs: k3s kubectl logs -f -n traefik -l app.kubernetes.io/name=traefik"
        echo "5. If needed, force certificate renewal: sudo ./scripts/renew-certificates.sh"
        echo "6. Check Let's Encrypt rate limits if requests are failing"
        echo ""
    } >> "$DEBUG_OUTPUT_FILE"
    
    echo ""
}

# Main function
main() {
    echo "======================================="
    echo "  TLS COMPREHENSIVE DEBUG SCRIPT"
    echo "======================================="
    echo ""
    
    init_debug_log
    load_environment
    check_prerequisites
    get_pod_names
    check_dns_resolution
    check_network_connectivity
    analyze_traefik_config
    check_acme_storage
    analyze_ingress_config
    analyze_traefik_logs
    test_certificate_directly
    check_kubernetes_secrets
    check_traefik_dashboard
    generate_recommendations
    
    log_success "Debug analysis completed!"
    log_info "Full debug report saved to: $DEBUG_OUTPUT_FILE"
    echo ""
    echo "======================================="
    echo "  DEBUG ANALYSIS COMPLETE"
    echo "======================================="
}

# Check if running with proper permissions
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root (for k3s access)"
    exit 1
fi

# Run main function
main "$@"