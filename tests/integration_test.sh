#!/bin/bash
# Integration tests for headscale-vpn deployment

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}Headscale VPN Integration Tests${NC}"
echo "=================================="

# Test configuration
HEADSCALE_URL=${HEADSCALE_URL:-http://localhost:8080}
TEST_USER="test-user"
TIMEOUT=300  # 5 minutes

# Helper functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

wait_for_service() {
    local service_name="$1"
    local check_command="$2"
    local timeout="$3"
    
    log_info "Waiting for $service_name to be ready..."
    local count=0
    while ! eval "$check_command" >/dev/null 2>&1; do
        if [ $count -ge $timeout ]; then
            log_error "$service_name failed to start within $timeout seconds"
            return 1
        fi
        sleep 1
        ((count++))
    done
    log_info "$service_name is ready"
}

# Test 1: Check if all containers are running
test_containers_running() {
    log_info "Testing container status..."
    
    local required_containers=("headscale" "headscale-db" "headscale-ui" "vpn-exit-node")
    
    for container in "${required_containers[@]}"; do
        if ! docker ps | grep -q "$container"; then
            log_error "Container $container is not running"
            return 1
        fi
    done
    
    log_info "All required containers are running"
}

# Test 2: Check Headscale API health
test_headscale_health() {
    log_info "Testing Headscale health endpoint..."
    
    wait_for_service "Headscale" "curl -s $HEADSCALE_URL/health" 60
    
    local response=$(curl -s "$HEADSCALE_URL/health")
    if [[ "$response" != *"ok"* ]]; then
        log_error "Headscale health check failed: $response"
        return 1
    fi
    
    log_info "Headscale health check passed"
}

# Test 3: Test user creation
test_user_creation() {
    log_info "Testing user creation..."
    
    # Clean up any existing test user
    docker exec headscale headscale users delete "$TEST_USER" 2>/dev/null || true
    
    # Create test user
    if ! docker exec headscale headscale users create "$TEST_USER"; then
        log_error "Failed to create test user"
        return 1
    fi
    
    # Verify user exists
    if ! docker exec headscale headscale users list | grep -q "$TEST_USER"; then
        log_error "Test user not found in user list"
        return 1
    fi
    
    log_info "User creation test passed"
}

# Test 4: Test pre-auth key generation
test_preauth_key() {
    log_info "Testing pre-auth key generation..."
    
    local key=$(docker exec headscale headscale preauthkeys create --user "$TEST_USER" --output json | jq -r '.key')
    
    if [[ -z "$key" || "$key" == "null" ]]; then
        log_error "Failed to generate pre-auth key"
        return 1
    fi
    
    # Verify key exists in list
    if ! docker exec headscale headscale preauthkeys list | grep -q "$key"; then
        log_error "Generated key not found in key list"
        return 1
    fi
    
    log_info "Pre-auth key generation test passed"
}

# Test 5: Test VPN exit node connectivity
test_vpn_exit_node() {
    log_info "Testing VPN exit node..."
    
    # Wait for VPN exit node to be ready
    wait_for_service "VPN Exit Node" "docker exec vpn-exit-node tailscale status" 120
    
    # Check if exit node is advertising routes
    local status=$(docker exec vpn-exit-node tailscale status --json)
    if ! echo "$status" | jq -r '.Self.Online' | grep -q "true"; then
        log_error "VPN exit node is not online"
        return 1
    fi
    
    log_info "VPN exit node test passed"
}

# Cleanup function
cleanup() {
    log_info "Cleaning up test resources..."
    docker exec headscale headscale users delete "$TEST_USER" 2>/dev/null || true
}

# Main test execution
main() {
    local failed_tests=0
    
    # Change to project directory
    cd "$PROJECT_DIR"
    
    # Run tests
    local tests=(
        "test_containers_running"
        "test_headscale_health"
        "test_user_creation"
        "test_preauth_key"
        "test_vpn_exit_node"
    )
    
    for test in "${tests[@]}"; do
        echo
        if ! $test; then
            log_error "Test $test failed"
            ((failed_tests++))
        else
            log_info "Test $test passed"
        fi
    done
    
    # Cleanup
    cleanup
    
    # Summary
    echo
    echo "=================================="
    if [ $failed_tests -eq 0 ]; then
        log_info "All tests passed! ✅"
        exit 0
    else
        log_error "$failed_tests test(s) failed ❌"
        exit 1
    fi
}

# Run tests
main "$@"