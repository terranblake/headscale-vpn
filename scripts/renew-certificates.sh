#!/bin/bash

# Certificate Renewal Script
# This script forces renewal of Let's Encrypt certificates by clearing ACME storage

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

# Force certificate renewal
force_renewal() {
    log_warning "This will delete existing ACME certificates and force renewal"
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Operation cancelled"
        exit 0
    fi
    
    log_info "Starting certificate renewal process..."
    
    # Scale down Traefik to ensure clean shutdown
    log_info "Scaling down Traefik..."
    k3s kubectl scale deployment -n traefik traefik --replicas=0
    
    # Wait for Traefik to shut down
    log_info "Waiting for Traefik to shut down..."
    k3s kubectl wait --for=delete pod -l app.kubernetes.io/name=traefik -n traefik --timeout=60s
    
    # Delete ACME storage PVC (this will delete the acme.json file)
    log_info "Deleting ACME storage..."
    if k3s kubectl get pvc -n traefik traefik-acme-storage &>/dev/null; then
        k3s kubectl delete pvc -n traefik traefik-acme-storage
        
        # Wait for PVC to be deleted
        log_info "Waiting for PVC deletion..."
        while k3s kubectl get pvc -n traefik traefik-acme-storage &>/dev/null; do
            sleep 2
        done
    else
        log_warning "ACME storage PVC not found"
    fi
    
    # Recreate ACME storage PVC
    log_info "Recreating ACME storage..."
    k3s kubectl apply -f "$(dirname "$(dirname "${BASH_SOURCE[0]}")")/k8s/traefik-config.yaml"
    
    # Scale Traefik back up
    log_info "Scaling Traefik back up..."
    k3s kubectl scale deployment -n traefik traefik --replicas=1
    
    # Wait for Traefik to be ready
    log_info "Waiting for Traefik to be ready..."
    k3s kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=traefik -n traefik --timeout=120s
    
    log_success "Certificate renewal process completed"
    log_info "New certificates should be requested automatically"
    log_info "Monitor progress with: k3s kubectl logs -f -n traefik -l app.kubernetes.io/name=traefik"
}

# Check if running with proper permissions
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root (for k3s access)"
    exit 1
fi

# Main function
main() {
    log_info "Let's Encrypt Certificate Renewal Tool"
    echo
    
    # Check if Traefik is running
    if ! k3s kubectl get deployment -n traefik traefik &>/dev/null; then
        log_error "Traefik deployment not found"
        exit 1
    fi
    
    force_renewal
}

# Run main function
main "$@"