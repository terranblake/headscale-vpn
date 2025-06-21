#!/bin/bash

# ACME Challenge Fix Script
# Fixes the specific issue where ACME challenges return 403 Forbidden

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
K8S_DIR="$PROJECT_ROOT/k8s"

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
    
    if [[ -z "${DOMAIN:-}" ]]; then
        log_error "DOMAIN environment variable is not set"
        exit 1
    fi
    
    log_success "Environment variables loaded"
    log_info "Domain: $DOMAIN"
}

# Create separate ingress for ACME challenges
create_acme_ingress() {
    log_info "Creating separate ingress for ACME challenges..."
    
    cat > /tmp/acme-challenge-ingress.yaml << EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: acme-challenge-ingress
  namespace: headscale-vpn
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: web
    traefik.ingress.kubernetes.io/router.priority: "100"
spec:
  ingressClassName: traefik
  rules:
  - host: headscale.${DOMAIN}
    http:
      paths:
      - path: /.well-known/acme-challenge
        pathType: Prefix
        backend:
          service:
            name: traefik-acme-challenge
            port:
              number: 80
EOF

    # Apply the ACME challenge ingress
    envsubst < /tmp/acme-challenge-ingress.yaml | k3s kubectl apply -f -
    
    log_success "ACME challenge ingress created"
    rm -f /tmp/acme-challenge-ingress.yaml
}

# Create ACME challenge service
create_acme_service() {
    log_info "Creating ACME challenge service..."
    
    cat > /tmp/acme-challenge-service.yaml << EOF
apiVersion: v1
kind: Service
metadata:
  name: traefik-acme-challenge
  namespace: headscale-vpn
spec:
  type: ExternalName
  externalName: traefik.traefik.svc.cluster.local
  ports:
  - port: 80
    targetPort: 80
EOF

    k3s kubectl apply -f /tmp/acme-challenge-service.yaml
    
    log_success "ACME challenge service created"
    rm -f /tmp/acme-challenge-service.yaml
}

# Remove authentication from main ingress ACME path
fix_main_ingress() {
    log_info "Updating main ingress to exclude ACME path from authentication..."
    
    # Check if the main ingress has authentication middleware
    local auth_middleware
    auth_middleware=$(k3s kubectl get ingress -n headscale-vpn headscale-ingress -o jsonpath='{.metadata.annotations.traefik\.ingress\.kubernetes\.io/router\.middlewares}' 2>/dev/null || echo "")
    
    if [[ -n "$auth_middleware" ]]; then
        log_warning "Found authentication middleware on main ingress: $auth_middleware"
        
        # Remove middleware from main ingress temporarily
        k3s kubectl annotate ingress headscale-ingress -n headscale-vpn traefik.ingress.kubernetes.io/router.middlewares- || true
        
        log_success "Removed authentication middleware from main ingress"
        log_info "You may need to re-add authentication after certificates are obtained"
    else
        log_info "No authentication middleware found on main ingress"
    fi
}

# Alternative: Use IngressRoute for better control
create_ingressroute_with_acme() {
    log_info "Creating IngressRoute with proper ACME challenge handling..."
    
    cat > /tmp/headscale-ingressroute-fixed.yaml << EOF
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: headscale-ingressroute-fixed
  namespace: headscale-vpn
spec:
  entryPoints:
    - web
    - websecure
  routes:
    # ACME challenge route (no authentication)
    - match: Host(\`headscale.${DOMAIN}\`) && PathPrefix(\`/.well-known/acme-challenge\`)
      kind: Rule
      priority: 100
      services:
        - name: traefik-acme-challenge
          port: 80
    # Main application route (with authentication if needed)
    - match: Host(\`headscale.${DOMAIN}\`)
      kind: Rule
      priority: 50
      services:
        - name: headscale
          port: 8080
      # middlewares:
      #   - name: headscale-vpn-auth  # Uncomment if you want authentication
  tls:
    certResolver: letsencrypt
---
apiVersion: v1
kind: Service
metadata:
  name: traefik-acme-challenge
  namespace: headscale-vpn
spec:
  type: ExternalName
  externalName: traefik.traefik.svc.cluster.local
  ports:
  - port: 80
    targetPort: 80
EOF

    envsubst < /tmp/headscale-ingressroute-fixed.yaml | k3s kubectl apply -f -
    
    log_success "IngressRoute with ACME challenge handling created"
    rm -f /tmp/headscale-ingressroute-fixed.yaml
}

# Test ACME challenge path
test_acme_path() {
    log_info "Testing ACME challenge path accessibility..."
    
    local target_domain="headscale.$DOMAIN"
    
    # Wait a moment for changes to propagate
    sleep 5
    
    # Test the ACME challenge path
    local response
    if response=$(curl -s -I "http://$target_domain/.well-known/acme-challenge/test" 2>&1); then
        log_info "ACME challenge path response:"
        echo "$response"
        
        if echo "$response" | grep -q "404 Not Found"; then
            log_success "✅ ACME challenge path is now accessible (404 is expected for non-existent challenge)"
        elif echo "$response" | grep -q "403 Forbidden"; then
            log_error "❌ ACME challenge path still returns 403 Forbidden"
            return 1
        else
            log_info "ACME challenge path response received (may be OK)"
        fi
    else
        log_error "❌ Cannot reach ACME challenge path"
        echo "Error: $response"
        return 1
    fi
}

# Restart Traefik to pick up changes
restart_traefik() {
    log_info "Restarting Traefik to pick up configuration changes..."
    
    k3s kubectl rollout restart deployment -n traefik traefik
    
    log_info "Waiting for Traefik to be ready..."
    k3s kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=traefik -n traefik --timeout=120s
    
    log_success "Traefik restarted successfully"
}

# Force new certificate request
force_certificate_request() {
    log_info "Forcing new certificate request..."
    
    # Get Traefik pod
    local traefik_pod
    traefik_pod=$(k3s kubectl get pods -n traefik -l app.kubernetes.io/name=traefik -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [[ -n "$traefik_pod" ]]; then
        # Clear ACME storage to force new certificate request
        k3s kubectl exec -n traefik "$traefik_pod" -- rm -f /data/acme.json || true
        
        # Restart Traefik to trigger new certificate request
        restart_traefik
        
        log_success "Certificate request initiated"
        log_info "Monitor progress with: k3s kubectl logs -f -n traefik -l app.kubernetes.io/name=traefik | grep -i acme"
    else
        log_error "Cannot find Traefik pod"
        return 1
    fi
}

# Show usage
show_usage() {
    echo "ACME Challenge Fix Script"
    echo ""
    echo "Usage: $0 [OPTION]"
    echo ""
    echo "Options:"
    echo "  --ingress-route    Use IngressRoute approach (recommended)"
    echo "  --separate-ingress Use separate ingress for ACME challenges"
    echo "  --remove-auth      Remove authentication from main ingress"
    echo "  --test-only        Only test ACME challenge path"
    echo "  --force-cert       Force new certificate request"
    echo "  -h, --help         Show this help message"
    echo ""
    echo "If no option is specified, --ingress-route will be used."
}

# Main function
main() {
    local approach="ingressroute"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --ingress-route)
                approach="ingressroute"
                shift
                ;;
            --separate-ingress)
                approach="separate"
                shift
                ;;
            --remove-auth)
                approach="remove-auth"
                shift
                ;;
            --test-only)
                approach="test"
                shift
                ;;
            --force-cert)
                approach="force-cert"
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    echo "======================================="
    echo "  ACME CHALLENGE FIX SCRIPT"
    echo "======================================="
    echo ""
    
    load_environment
    
    case $approach in
        "ingressroute")
            log_info "Using IngressRoute approach..."
            create_ingressroute_with_acme
            restart_traefik
            test_acme_path
            force_certificate_request
            ;;
        "separate")
            log_info "Using separate ingress approach..."
            create_acme_service
            create_acme_ingress
            restart_traefik
            test_acme_path
            ;;
        "remove-auth")
            log_info "Removing authentication from main ingress..."
            fix_main_ingress
            restart_traefik
            test_acme_path
            ;;
        "test")
            log_info "Testing ACME challenge path only..."
            test_acme_path
            ;;
        "force-cert")
            log_info "Forcing certificate request..."
            force_certificate_request
            ;;
    esac
    
    if [[ "$approach" != "test" ]]; then
        log_success "ACME challenge fix completed!"
        echo ""
        echo "Next steps:"
        echo "1. Monitor certificate generation: k3s kubectl logs -f -n traefik -l app.kubernetes.io/name=traefik | grep -i acme"
        echo "2. Test ACME path: curl -I http://headscale.$DOMAIN/.well-known/acme-challenge/test"
        echo "3. Check certificate: openssl s_client -connect headscale.$DOMAIN:443 -servername headscale.$DOMAIN"
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

# Run main function
main "$@"