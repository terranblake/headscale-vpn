#!/bin/bash

# ACME Challenge Diagnostic Script
# Specifically diagnoses why ACME HTTP-01 challenges are failing

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
    if [[ -z "${DOMAIN:-}" ]]; then
        log_error "DOMAIN environment variable is not set"
        exit 1
    fi
    
    log_success "Environment variables loaded"
    log_info "Domain: $DOMAIN"
}

# Test ACME challenge path accessibility
test_acme_challenge_path() {
    log_section "1. TESTING ACME CHALLENGE PATH ACCESSIBILITY"
    
    local target_domain="headscale.$DOMAIN"
    local test_path="/.well-known/acme-challenge/test-$(date +%s)"
    
    log_info "Testing ACME challenge path: http://$target_domain$test_path"
    
    # Test from external perspective (what Let's Encrypt sees)
    log_info "Testing external accessibility..."
    local external_response
    if external_response=$(curl -s -I "http://$target_domain$test_path" 2>&1); then
        log_info "External response received:"
        echo "$external_response"
        
        if echo "$external_response" | grep -q "403 Forbidden"; then
            log_error "❌ ACME challenge path returns 403 Forbidden"
            log_error "This is why Let's Encrypt cannot complete the challenge"
        elif echo "$external_response" | grep -q "404 Not Found"; then
            log_success "✅ ACME challenge path is accessible (404 is expected for non-existent challenge)"
        else
            log_warning "⚠️ Unexpected response for ACME challenge path"
        fi
    else
        log_error "❌ Cannot reach ACME challenge path externally"
        echo "Error: $external_response"
    fi
    
    echo ""
}

# Check Traefik routing configuration
check_traefik_routing() {
    log_section "2. CHECKING TRAEFIK ROUTING CONFIGURATION"
    
    # Get Traefik pod
    local traefik_pod
    traefik_pod=$(k3s kubectl get pods -n traefik -l app.kubernetes.io/name=traefik -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [[ -z "$traefik_pod" ]]; then
        log_error "Traefik pod not found"
        return 1
    fi
    
    log_success "Found Traefik pod: $traefik_pod"
    
    # Check if Traefik is configured to handle ACME challenges
    log_info "Checking Traefik configuration for ACME challenge handling..."
    
    # Look for ACME-related configuration in Traefik logs
    local acme_logs
    acme_logs=$(k3s kubectl logs -n traefik "$traefik_pod" --tail=100 | grep -i "acme\|challenge" || echo "")
    
    if [[ -n "$acme_logs" ]]; then
        log_info "Found ACME-related log entries:"
        echo "$acme_logs"
    else
        log_warning "No ACME-related log entries found"
    fi
    
    # Check if there are any routing rules that might interfere
    log_info "Checking for routing conflicts..."
    
    # Get ingress configuration
    local ingress_config
    if ingress_config=$(k3s kubectl get ingress -n headscale-vpn headscale-ingress -o yaml 2>/dev/null); then
        log_info "Current ingress configuration:"
        echo "$ingress_config" | grep -A 10 -B 5 "paths:\|rules:"
    else
        log_error "Cannot retrieve ingress configuration"
    fi
    
    echo ""
}

# Check for middleware that might block ACME challenges
check_middleware_interference() {
    log_section "3. CHECKING FOR MIDDLEWARE INTERFERENCE"
    
    # Check for authentication middleware
    log_info "Checking for authentication middleware..."
    
    local auth_middleware
    auth_middleware=$(k3s kubectl get middleware -n headscale-vpn -o yaml 2>/dev/null || echo "")
    
    if [[ -n "$auth_middleware" ]]; then
        log_warning "Found middleware configuration:"
        echo "$auth_middleware" | grep -A 5 -B 5 "basicAuth\|forwardAuth\|digestAuth"
        
        log_error "❌ Authentication middleware may be blocking ACME challenges"
        log_info "ACME challenges need unrestricted access to /.well-known/acme-challenge/*"
    else
        log_success "✅ No authentication middleware found"
    fi
    
    # Check ingress annotations for middleware
    log_info "Checking ingress annotations for middleware..."
    
    local middleware_annotations
    middleware_annotations=$(k3s kubectl get ingress -n headscale-vpn headscale-ingress -o jsonpath='{.metadata.annotations}' 2>/dev/null | grep -i middleware || echo "")
    
    if [[ -n "$middleware_annotations" ]]; then
        log_warning "Found middleware annotations on ingress:"
        echo "$middleware_annotations"
        log_error "❌ Middleware on ingress may be blocking ACME challenges"
    else
        log_success "✅ No middleware annotations on ingress"
    fi
    
    echo ""
}

# Check network policies and firewall rules
check_network_policies() {
    log_section "4. CHECKING NETWORK POLICIES AND ACCESS CONTROLS"
    
    # Check for Kubernetes network policies
    log_info "Checking for Kubernetes network policies..."
    
    local network_policies
    network_policies=$(k3s kubectl get networkpolicies --all-namespaces -o wide 2>/dev/null || echo "")
    
    if [[ -n "$network_policies" ]] && [[ "$network_policies" != "No resources found" ]]; then
        log_warning "Found network policies that might affect traffic:"
        echo "$network_policies"
        log_warning "⚠️ Network policies may be blocking ACME challenge traffic"
    else
        log_success "✅ No network policies found that would block traffic"
    fi
    
    # Check for any IP restrictions in Traefik
    log_info "Checking for IP restrictions in Traefik configuration..."
    
    local traefik_pod
    traefik_pod=$(k3s kubectl get pods -n traefik -l app.kubernetes.io/name=traefik -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [[ -n "$traefik_pod" ]]; then
        # Look for IP whitelist or restriction configurations
        local ip_restrictions
        ip_restrictions=$(k3s kubectl logs -n traefik "$traefik_pod" --tail=200 | grep -i "whitelist\|blacklist\|ipallowlist\|rfc1918" || echo "")
        
        if [[ -n "$ip_restrictions" ]]; then
            log_error "❌ Found IP restriction logs in Traefik:"
            echo "$ip_restrictions"
            log_error "This explains the 'Rejected request from RFC1918 IP' error"
        else
            log_info "No IP restriction logs found in Traefik"
        fi
    fi
    
    echo ""
}

# Check Traefik entrypoints configuration
check_entrypoints_config() {
    log_section "5. CHECKING TRAEFIK ENTRYPOINTS CONFIGURATION"
    
    local traefik_pod
    traefik_pod=$(k3s kubectl get pods -n traefik -l app.kubernetes.io/name=traefik -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [[ -z "$traefik_pod" ]]; then
        log_error "Traefik pod not found"
        return 1
    fi
    
    # Check if HTTP entrypoint is properly configured
    log_info "Checking Traefik entrypoints configuration..."
    
    # Look for entrypoint configuration in logs
    local entrypoint_logs
    entrypoint_logs=$(k3s kubectl logs -n traefik "$traefik_pod" --tail=100 | grep -i "entrypoint\|listening" || echo "")
    
    if [[ -n "$entrypoint_logs" ]]; then
        log_info "Traefik entrypoint configuration:"
        echo "$entrypoint_logs"
        
        if echo "$entrypoint_logs" | grep -q ":80"; then
            log_success "✅ HTTP entrypoint (port 80) is configured"
        else
            log_error "❌ HTTP entrypoint (port 80) not found in configuration"
        fi
    else
        log_warning "No entrypoint configuration found in logs"
    fi
    
    # Check if Traefik is actually listening on port 80
    log_info "Checking if Traefik is listening on port 80..."
    
    if k3s kubectl exec -n traefik "$traefik_pod" -- netstat -tlnp 2>/dev/null | grep -q ":80"; then
        log_success "✅ Traefik is listening on port 80"
    else
        log_error "❌ Traefik is not listening on port 80"
    fi
    
    echo ""
}

# Test direct connection to Traefik
test_direct_traefik_connection() {
    log_section "6. TESTING DIRECT TRAEFIK CONNECTION"
    
    local target_domain="headscale.$DOMAIN"
    
    # Test connection to Traefik directly
    log_info "Testing direct connection to Traefik..."
    
    # Get the actual IP that the domain resolves to
    local resolved_ip
    resolved_ip=$(dig +short "$target_domain" | head -1)
    
    if [[ -n "$resolved_ip" ]]; then
        log_info "Domain $target_domain resolves to: $resolved_ip"
        
        # Test direct HTTP connection to the IP
        log_info "Testing direct HTTP connection to $resolved_ip:80..."
        
        local direct_response
        if direct_response=$(curl -s -I -H "Host: $target_domain" "http://$resolved_ip/.well-known/acme-challenge/test" 2>&1); then
            log_info "Direct connection response:"
            echo "$direct_response"
            
            if echo "$direct_response" | grep -q "403 Forbidden"; then
                log_error "❌ Direct connection also returns 403 Forbidden"
                log_error "This confirms the issue is in Traefik configuration, not network routing"
            fi
        else
            log_error "❌ Cannot connect directly to $resolved_ip:80"
            echo "Error: $direct_response"
        fi
    else
        log_error "❌ Cannot resolve domain $target_domain"
    fi
    
    echo ""
}

# Generate specific recommendations for ACME challenge issues
generate_acme_recommendations() {
    log_section "7. RECOMMENDATIONS FOR ACME CHALLENGE ISSUES"
    
    log_info "Based on the analysis, here are specific recommendations:"
    
    echo "🔧 IMMEDIATE FIXES:"
    echo ""
    echo "1. Remove authentication middleware from ACME challenge path:"
    echo "   - ACME challenges must be accessible without authentication"
    echo "   - Add path exclusion for /.well-known/acme-challenge/* in middleware"
    echo ""
    echo "2. Check Traefik configuration for IP restrictions:"
    echo "   - The 'RFC1918 IP' error suggests IP filtering is active"
    echo "   - Ensure Let's Encrypt IPs are not blocked"
    echo ""
    echo "3. Verify ingress path configuration:"
    echo "   - Ensure /.well-known/acme-challenge/* is not explicitly blocked"
    echo "   - Check for conflicting path rules"
    echo ""
    echo "🔍 DEBUGGING COMMANDS:"
    echo ""
    echo "# Check Traefik logs for ACME activity:"
    echo "k3s kubectl logs -f -n traefik -l app.kubernetes.io/name=traefik | grep -i acme"
    echo ""
    echo "# Test ACME challenge path:"
    echo "curl -v http://headscale.$DOMAIN/.well-known/acme-challenge/test"
    echo ""
    echo "# Check for middleware blocking challenges:"
    echo "k3s kubectl get middleware -n headscale-vpn -o yaml"
    echo ""
    echo "🚀 POTENTIAL SOLUTIONS:"
    echo ""
    echo "1. Modify ingress to exclude ACME path from authentication:"
    echo "   - Add a separate ingress rule for /.well-known/acme-challenge/*"
    echo "   - Ensure this rule has no authentication middleware"
    echo ""
    echo "2. Update Traefik configuration:"
    echo "   - Remove IP restrictions that block Let's Encrypt"
    echo "   - Ensure HTTP entrypoint is properly configured"
    echo ""
    echo "3. Use IngressRoute instead of Ingress:"
    echo "   - IngressRoute gives more control over ACME challenge handling"
    echo "   - Can explicitly configure challenge routing"
    
    echo ""
}

# Main function
main() {
    echo "======================================="
    echo "  ACME CHALLENGE DIAGNOSTIC SCRIPT"
    echo "======================================="
    echo ""
    
    load_environment
    test_acme_challenge_path
    check_traefik_routing
    check_middleware_interference
    check_network_policies
    check_entrypoints_config
    test_direct_traefik_connection
    generate_acme_recommendations
    
    log_success "ACME challenge diagnosis completed!"
    echo ""
    echo "======================================="
    echo "  DIAGNOSIS COMPLETE"
    echo "======================================="
}

# Check if running with proper permissions
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root (for k3s access)"
    exit 1
fi

# Run main function
main "$@"