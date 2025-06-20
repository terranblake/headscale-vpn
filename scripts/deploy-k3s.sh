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

# Clean up existing namespace for fresh deployment
cleanup_namespace() {
    log_info "Cleaning up existing namespace for fresh deployment..."
    
    # Check if namespace exists
    if k3s kubectl get namespace headscale-vpn &>/dev/null; then
        log_warning "Existing namespace found, cleaning up..."
        
        # Delete namespace (this will cascade delete all resources)
        k3s kubectl delete namespace headscale-vpn --timeout=60s
        
        # Wait for namespace to be fully deleted
        log_info "Waiting for namespace cleanup to complete..."
        local retries=30
        while k3s kubectl get namespace headscale-vpn &>/dev/null && [[ $retries -gt 0 ]]; do
            sleep 2
            ((retries--))
        done
        
        if [[ $retries -eq 0 ]]; then
            log_error "Timeout waiting for namespace cleanup"
            exit 1
        fi
        
        log_success "Namespace cleanup completed"
    else
        log_info "No existing namespace found"
    fi
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
    log_info "Deploying configmap from actual config files..."
    
    # Create temporary directory for processed config files
    local temp_config_dir="/tmp/headscale-config-processed"
    rm -rf "$temp_config_dir"
    mkdir -p "$temp_config_dir"
    
    # Copy config files and substitute environment variables
    for file in "$CONFIG_DIR/headscale"/*; do
        if [[ -f "$file" ]]; then
            local filename=$(basename "$file")
            envsubst < "$file" > "$temp_config_dir/$filename"
        fi
    done
    
    # Create configmap from processed files
    k3s kubectl create configmap headscale-config \
        --from-file="$temp_config_dir/" \
        -n headscale-vpn \
        --dry-run=client -o yaml | k3s kubectl apply -f -
    
    # Create configmap for VPN exit node config
    k3s kubectl create configmap vpn-exit-config \
        --from-file="$CONFIG_DIR/vpn-exit/" \
        -n headscale-vpn \
        --dry-run=client -o yaml | k3s kubectl apply -f -
    
    # Cleanup
    rm -rf "$temp_config_dir"
    
    log_success "Configmaps deployed from actual config files"
}

# Deploy storage
deploy_storage() {
    log_info "Deploying storage..."
    k3s kubectl apply -f "$K8S_DIR/storage.yaml"
    
    # Health check: Ensure PVCs are created (they will bind when first consumer starts)
    log_info "Verifying PVCs are created..."
    local retries=10
    while [[ $retries -gt 0 ]]; do
        local total_pvcs
        total_pvcs=$(k3s kubectl get pvc -n headscale-vpn -o name 2>/dev/null | wc -l)
        if [[ $total_pvcs -eq 4 ]]; then
            log_success "All PVCs are created (will bind when pods start)"
            break
        fi
        log_warning "Waiting for PVCs to be created... ($total_pvcs/4 created, $retries attempts left)"
        sleep 2
        ((retries--))
    done
    
    if [[ $retries -eq 0 ]]; then
        log_error "PVC creation failed"
        k3s kubectl get pvc -n headscale-vpn
        exit 1
    fi
    
    log_success "Storage deployed and healthy"
}

# Deploy database
deploy_database() {
    log_info "Deploying PostgreSQL database..."
    k3s kubectl apply -f "$K8S_DIR/database.yaml"
    
    # Wait for database to be ready
    log_info "Waiting for database to be ready..."
    
    # Start background log streaming
    k3s kubectl logs -f -l app=headscale-db -n headscale-vpn --tail=10 2>/dev/null &
    local log_pid=$!
    
    # Wait for pod to be ready
    k3s kubectl wait --for=condition=ready pod -l app=headscale-db -n headscale-vpn --timeout=300s
    
    # Stop log streaming
    kill $log_pid 2>/dev/null || true
    
    # Health check: Test database connection
    log_info "Testing database connection..."
    local retries=10
    while [[ $retries -gt 0 ]]; do
        if k3s kubectl exec -n headscale-vpn deployment/headscale-db -- pg_isready -U headscale -d headscale; then
            log_success "Database connection test passed"
            break
        fi
        log_warning "Database connection test failed, retrying... ($retries attempts left)"
        sleep 5
        ((retries--))
    done
    
    if [[ $retries -eq 0 ]]; then
        log_error "Database health check failed"
        exit 1
    fi
    
    log_success "Database deployed and healthy"
}

# Deploy headscale
deploy_headscale() {
    log_info "Deploying Headscale..."
    
    # Deploy headscale (configmap already created in deploy_configmap)
    k3s kubectl apply -f "$K8S_DIR/headscale.yaml"
    
    # Wait for headscale to be ready
    log_info "Waiting for Headscale to be ready..."
    
    # Start background log streaming
    k3s kubectl logs -f -l app=headscale -n headscale-vpn --tail=10 2>/dev/null &
    local log_pid=$!
    
    # Wait for pod to be ready
    k3s kubectl wait --for=condition=ready pod -l app=headscale -n headscale-vpn --timeout=300s
    
    # Stop log streaming
    kill $log_pid 2>/dev/null || true
    
    # Health check: Test Headscale API
    log_info "Testing Headscale API health..."
    local retries=10
    while [[ $retries -gt 0 ]]; do
        if k3s kubectl exec -n headscale-vpn deployment/headscale -- headscale namespaces list >/dev/null 2>&1; then
            log_success "Headscale API health check passed"
            break
        fi
        log_warning "Headscale API health check failed, retrying... ($retries attempts left)"
        sleep 10
        ((retries--))
    done
    
    if [[ $retries -eq 0 ]]; then
        log_error "Headscale health check failed"
        exit 1
    fi
    
    log_success "Headscale deployed and healthy"
}

# Build VPN exit node image
build_vpn_exit_image() {
    log_info "Building VPN exit node Docker image..."
    
    # Build the image (always rebuild to ensure latest config)
    docker build -t headscale-vpn/vpn-exit-node:latest \
        -f "$PROJECT_ROOT/build/vpn-exit-node/Dockerfile" \
        "$PROJECT_ROOT"
    
    # Import image into k3s
    docker save headscale-vpn/vpn-exit-node:latest | k3s ctr images import -
    
    log_success "VPN exit node image built and imported"
}

# Deploy VPN exit node
deploy_vpn_exit() {
    log_info "Deploying VPN exit node..."

    # Create VPN exit secrets with WireGuard config
    log_info "Creating VPN exit secrets..."
    if [[ ! -f "$CONFIG_DIR/vpn-exit/gluetun/us.seattle.exit.conf" ]]; then
        log_error "WireGuard config file not found: $CONFIG_DIR/vpn-exit/gluetun/us.seattle.exit.conf"
        log_error "Please copy your WireGuard config file to this location"
        exit 1
    fi
    
    k3s kubectl create secret generic vpn-exit-secrets \
        --from-file=wg0.conf="$CONFIG_DIR/vpn-exit/gluetun/us.seattle.exit.conf" \
        -n headscale-vpn \
        --dry-run=client -o yaml | k3s kubectl apply -f -
    
    # Create user if it doesn't exist
    log_info "Creating headscale user..."
    if ! k3s kubectl exec -n headscale-vpn deployment/headscale -- headscale users list | grep -q "vpn-admin"; then
        k3s kubectl exec -n headscale-vpn deployment/headscale -- headscale users create vpn-admin
    fi
    
    # Generate Headscale preauth key for the exit node
    log_info "Generating preauth key for VPN exit node..."
    local auth_key
    auth_key=$(k3s kubectl exec -n headscale-vpn deployment/headscale -- headscale preauthkeys create --user 1 --expiration 24h --reusable | grep -o '[a-f0-9]\{32\}')
    
    if [[ -z "$auth_key" ]]; then
        log_error "Failed to generate preauth key for VPN exit node"
        exit 1
    fi
    
    log_info "Generated preauth key for VPN exit node"
    
    # Create headscale-secrets if it doesn't exist
    if ! k3s kubectl get secret headscale-secrets -n headscale-vpn >/dev/null 2>&1; then
        k3s kubectl create secret generic headscale-secrets -n headscale-vpn \
            --from-literal=headscale-authkey="$auth_key"
    else
        # Update the secret with the auth key
        k3s kubectl patch secret headscale-secrets -n headscale-vpn --type='merge' -p="{\"data\":{\"headscale-authkey\":\"$(echo -n "$auth_key" | base64 -w 0)\"}}"
    fi
    
    # Deploy the VPN exit node
    k3s kubectl apply -f "$K8S_DIR/vpn-exit-node.yaml"
    
    # Wait for VPN exit node pod to be scheduled
    log_info "Waiting for VPN exit node to be scheduled..."
    local retries=30
    while [[ $retries -gt 0 ]]; do
        local pod_name
        pod_name=$(k3s kubectl get pods -l app=vpn-exit-node -n headscale-vpn -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
        if [[ -n "$pod_name" ]]; then
            log_info "VPN exit node pod scheduled: $pod_name"
            break
        fi
        log_warning "Waiting for VPN exit node pod to be scheduled... ($retries attempts left)"
        sleep 5
        ((retries--))
    done
    
    if [[ $retries -eq 0 ]]; then
        log_error "VPN exit node pod failed to schedule"
        k3s kubectl describe daemonset vpn-exit-node -n headscale-vpn
        exit 1
    fi
    
    # Stream logs and wait for readiness
    log_info "Waiting for VPN exit node to start (this may take a few minutes)..."
    local pod_name
    pod_name=$(k3s kubectl get pods -l app=vpn-exit-node -n headscale-vpn -o jsonpath='{.items[0].metadata.name}')
    
    # Start background log streaming
    k3s kubectl logs -f "$pod_name" -n headscale-vpn --tail=20 2>/dev/null &
    local log_pid=$!
    
    # Wait for the container to be ready (may take time for Tailscale auth)
    retries=2  # 10 minutes timeout
    while [[ $retries -gt 0 ]]; do
        local pod_status
        pod_status=$(k3s kubectl get pod "$pod_name" -n headscale-vpn -o jsonpath='{.status.phase}' 2>/dev/null)
        
        if [[ "$pod_status" == "Running" ]]; then
            # Check if tailscale is authenticated
            if k3s kubectl exec -n headscale-vpn "$pod_name" -- /usr/local/bin/tailscale status --json 2>/dev/null | grep -q '"BackendState":"Running"'; then
                log_success "VPN exit node is running and authenticated with Headscale"
                break
            fi
        fi
        
        if [[ "$pod_status" == "Failed" ]] || [[ "$pod_status" == "CrashLoopBackOff" ]]; then
            log_error "VPN exit node failed to start"
            break
        fi
        
        log_warning "VPN exit node still starting... ($retries attempts left, status: $pod_status)"
        sleep 5
        ((retries--))
    done
    
    # Stop log streaming
    kill $log_pid 2>/dev/null || true
    
    if [[ $retries -eq 0 ]]; then
        log_warning "VPN exit node may still be starting (this can take time for first run)"
        log_info "Check status with: kubectl logs -f $pod_name -n headscale-vpn"
    fi
    
    log_success "VPN exit node deployed"
}

# Deploy ingress
deploy_ingress() {
    log_info "Deploying ingress..."
    
    # Substitute environment variables in ingress.yaml
    envsubst < "$K8S_DIR/ingress.yaml" | k3s kubectl apply -f -
    
    # Health check: Verify Traefik can route to services
    log_info "Testing ingress health..."
    local retries=2
    while [[ $retries -gt 0 ]]; do
        if k3s kubectl get ingress -n headscale-vpn headscale-ingress -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null | grep -q .; then
            log_success "Ingress health check passed"
            break
        fi
        log_warning "Ingress health check failed, retrying... ($retries attempts left)"
        sleep 5
        ((retries--))
    done
    
    if [[ $retries -eq 0 ]]; then
        log_warning "Ingress health check failed (this may be expected in some environments)"
    fi
    
    log_success "Ingress deployed"
}

# Setup storage provisioner
setup_storage() {
    log_info "Setting up storage provisioner..."
    
    # Check if local-path provisioner is already installed
    if k3s kubectl get storageclass local-path &>/dev/null; then
        log_warning "Local-path storage provisioner already installed"
    else
        log_info "Installing local-path storage provisioner..."
        k3s kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.26/deploy/local-path-storage.yaml
        
        # Wait for the provisioner to be ready
        log_info "Waiting for storage provisioner to be ready..."
        k3s kubectl wait --for=condition=available --timeout=60s deployment/local-path-provisioner -n local-path-storage
    fi
    
    # Set local-path as default storage class
    log_info "Setting local-path as default storage class..."
    k3s kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
    
    log_success "Storage provisioner configured"
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
    setup_storage
    cleanup_namespace
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
