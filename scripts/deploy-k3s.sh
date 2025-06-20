#!/bin/bash

# K3s Deployment Script for Headscale VPN
# This script sets up a K3s cluster with Traefik and deploys the VPN services

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
K8S_DIR="$PROJECT_ROOT/k8s"
CONFIG_DIR="$PROJECT_ROOT/config"

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if running as root (required for K3s installation)
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root for K3s installation"
        exit 1
    fi
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
    required_vars=("DOMAIN" "POSTGRES_PASSWORD" "ACME_EMAIL")
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log_error "Required environment variable $var is not set"
            exit 1
        fi
    done
    
    log_success "Environment variables loaded"
}

# Install K3s with Traefik
install_k3s() {
    log_info "Installing K3s with Traefik..."
    
    if command -v k3s &> /dev/null; then
        log_warning "K3s is already installed"
        return 0
    fi
    
    # Install K3s with Traefik enabled
    curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable=servicelb --disable=local-storage" sh -
    
    # Wait for K3s to be ready
    log_info "Waiting for K3s to be ready..."
    local retries=30
    while ! k3s kubectl get nodes &>/dev/null && [[ $retries -gt 0 ]]; do
        sleep 2
        ((retries--))
    done
    
    if [[ $retries -eq 0 ]]; then
        log_error "K3s failed to start within timeout"
        exit 1
    fi
    
    log_success "K3s installed and running"
}

# Setup kubectl access
setup_kubectl() {
    log_info "Setting up kubectl access..."
    
    # Copy K3s kubeconfig for easier access
    mkdir -p ~/.kube
    cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
    chmod 600 ~/.kube/config
    
    # Create alias for easier access
    echo "alias kubectl='k3s kubectl'" >> ~/.bashrc
    
    log_success "kubectl access configured"
}

# Create namespace
create_namespace() {
    log_info "Creating namespace..."
    k3s kubectl apply -f "$K8S_DIR/namespace.yaml"
    log_success "Namespace created"
}

# Deploy secrets
deploy_secrets() {
    log_info "Deploying secrets..."
    
    # Substitute environment variables in secrets.yaml
    envsubst < "$K8S_DIR/secrets.yaml" | k3s kubectl apply -f -
    
    log_success "Secrets deployed"
}

# Deploy configmap
deploy_configmap() {
    log_info "Deploying configmap..."
    k3s kubectl apply -f "$K8S_DIR/configmap.yaml"
    log_success "Configmap deployed"
}

# Deploy storage
deploy_storage() {
    log_info "Deploying storage..."
    k3s kubectl apply -f "$K8S_DIR/storage.yaml"
    log_success "Storage deployed"
}

# Deploy database
deploy_database() {
    log_info "Deploying PostgreSQL database..."
    k3s kubectl apply -f "$K8S_DIR/database.yaml"
    
    # Wait for database to be ready
    log_info "Waiting for database to be ready..."
    k3s kubectl wait --for=condition=ready pod -l app=postgres -n headscale-vpn --timeout=300s
    
    log_success "Database deployed and ready"
}

# Deploy headscale
deploy_headscale() {
    log_info "Deploying Headscale..."
    
    # Create config volume from host files
    k3s kubectl create configmap headscale-files \
        --from-file="$CONFIG_DIR/headscale/" \
        -n headscale-vpn \
        --dry-run=client -o yaml | k3s kubectl apply -f -
    
    # Deploy headscale
    k3s kubectl apply -f "$K8S_DIR/headscale.yaml"
    
    # Wait for headscale to be ready
    log_info "Waiting for Headscale to be ready..."
    k3s kubectl wait --for=condition=ready pod -l app=headscale -n headscale-vpn --timeout=300s
    
    log_success "Headscale deployed and ready"
}

# Deploy VPN exit node
deploy_vpn_exit() {
    log_info "Deploying VPN exit node..."
    k3s kubectl apply -f "$K8S_DIR/vpn-exit-node.yaml"
    
    # Wait for vpn exit node to be ready
    log_info "Waiting for VPN exit node to be ready..."
    k3s kubectl wait --for=condition=ready pod -l app=vpn-exit-node -n headscale-vpn --timeout=300s
    
    log_success "VPN exit node deployed and ready"
}

# Deploy ingress
deploy_ingress() {
    log_info "Deploying ingress..."
    
    # Substitute environment variables in ingress.yaml
    envsubst < "$K8S_DIR/ingress.yaml" | k3s kubectl apply -f -
    
    log_success "Ingress deployed"
}

# Health check
health_check() {
    log_info "Performing health check..."
    
    # Check all pods are running
    local failed_pods
    failed_pods=$(k3s kubectl get pods -n headscale-vpn --no-headers | grep -v Running | wc -l)
    
    if [[ $failed_pods -gt 0 ]]; then
        log_error "Some pods are not running:"
        k3s kubectl get pods -n headscale-vpn
        return 1
    fi
    
    # Check services
    log_info "Services status:"
    k3s kubectl get services -n headscale-vpn
    
    # Check ingress
    log_info "Ingress status:"
    k3s kubectl get ingress -n headscale-vpn
    
    log_success "All services are healthy"
}

# Display access information
display_access_info() {
    log_success "Deployment completed successfully!"
    echo
    echo "=== Access Information ==="
    echo "Headscale Web UI: https://headscale.$DOMAIN"
    echo "Traefik Dashboard: https://traefik.$DOMAIN"
    echo
    echo "=== Useful Commands ==="
    echo "View pods: k3s kubectl get pods -n headscale-vpn"
    echo "View services: k3s kubectl get services -n headscale-vpn"
    echo "View logs: k3s kubectl logs -f deployment/headscale -n headscale-vpn"
    echo "Create user: k3s kubectl exec -it deployment/headscale -n headscale-vpn -- headscale users create <username>"
    echo
}

# Main deployment function
main() {
    log_info "Starting K3s deployment for Headscale VPN..."
    
    check_root
    load_environment
    install_k3s
    setup_kubectl
    create_namespace
    deploy_secrets
    deploy_configmap
    deploy_storage
    deploy_database
    deploy_headscale
    deploy_vpn_exit
    deploy_ingress
    health_check
    display_access_info
    
    log_success "K3s deployment completed successfully!"
}

# Run main function
main "$@"
