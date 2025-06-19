#!/bin/bash

# Family Network Platform - Integration Test Suite
# Tests complete deployment and functionality

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
TEST_RESULTS_DIR="/tmp/family-network-tests"
TEST_LOG="$TEST_RESULTS_DIR/integration-test.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0
FAILED_TESTS=()

# Logging functions
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$TEST_LOG"
}

test_start() {
    ((TESTS_TOTAL++))
    echo -e "${BLUE}[TEST $TESTS_TOTAL]${NC} $1" | tee -a "$TEST_LOG"
}

test_pass() {
    ((TESTS_PASSED++))
    echo -e "${GREEN}[PASS]${NC} $1" | tee -a "$TEST_LOG"
}

test_fail() {
    ((TESTS_FAILED++))
    FAILED_TESTS+=("$1")
    echo -e "${RED}[FAIL]${NC} $1" | tee -a "$TEST_LOG"
}

test_skip() {
    echo -e "${YELLOW}[SKIP]${NC} $1" | tee -a "$TEST_LOG"
}

# Setup test environment
setup_test_environment() {
    log "Setting up test environment..."
    
    mkdir -p "$TEST_RESULTS_DIR"
    
    # Load environment variables
    if [[ -f "$PROJECT_DIR/.env" ]]; then
        source "$PROJECT_DIR/.env"
    fi
    
    # Set test defaults
    DOMAIN=${DOMAIN:-"family.local"}
    HEADSCALE_URL=${HEADSCALE_URL:-"http://localhost:8080"}
    
    log "Test environment setup completed"
}

# Test Docker environment
test_docker_environment() {
    test_start "Docker Environment"
    
    # Check Docker daemon
    if ! docker info &>/dev/null; then
        test_fail "Docker daemon not running"
        return
    fi
    
    # Check Docker Compose
    if ! docker-compose version &>/dev/null; then
        test_fail "Docker Compose not available"
        return
    fi
    
    # Check project directory
    if [[ ! -f "$PROJECT_DIR/docker-compose.yml" ]]; then
        test_fail "docker-compose.yml not found"
        return
    fi
    
    test_pass "Docker environment ready"
}

# Test service deployment
test_service_deployment() {
    test_start "Service Deployment"
    
    cd "$PROJECT_DIR"
    
    # Deploy services
    log "Deploying services for testing..."
    if ! docker-compose up -d; then
        test_fail "Failed to deploy services"
        return
    fi
    
    # Wait for services to start
    sleep 30
    
    # Check if core services are running
    local required_services=("headscale" "traefik")
    local missing_services=()
    
    for service in "${required_services[@]}"; do
        if ! docker ps | grep -q "$service"; then
            missing_services+=("$service")
        fi
    done
    
    if [[ ${#missing_services[@]} -gt 0 ]]; then
        test_fail "Missing services: ${missing_services[*]}"
        return
    fi
    
    test_pass "All required services deployed"
}

# Test service health
test_service_health() {
    test_start "Service Health Checks"
    
    local services=(
        "headscale:8080:/health"
        "traefik:8080:/ping"
        "prometheus:9090/-/ready"
        "grafana:3000/api/health"
    )
    
    local unhealthy_services=()
    
    for service_info in "${services[@]}"; do
        local service="${service_info%%:*}"
        local port_path="${service_info#*:}"
        local port="${port_path%%/*}"
        local path="/${port_path#*/}"
        
        log "Checking health of $service..."
        
        # Wait for service to be ready
        local max_attempts=30
        local attempt=0
        local healthy=false
        
        while [[ $attempt -lt $max_attempts ]]; do
            if curl -f "http://localhost:$port$path" &>/dev/null; then
                healthy=true
                break
            fi
            
            ((attempt++))
            sleep 5
        done
        
        if [[ $healthy == true ]]; then
            log "$service is healthy"
        else
            unhealthy_services+=("$service")
        fi
    done
    
    if [[ ${#unhealthy_services[@]} -eq 0 ]]; then
        test_pass "All services are healthy"
    else
        test_fail "Unhealthy services: ${unhealthy_services[*]}"
    fi
}

# Test Headscale functionality
test_headscale_functionality() {
    test_start "Headscale Functionality"
    
    # Test Headscale API
    if ! curl -f "$HEADSCALE_URL/health" &>/dev/null; then
        test_fail "Headscale API not responding"
        return
    fi
    
    # Test user creation
    local test_user="test-user-$$"
    if docker exec headscale headscale users create "$test_user" &>/dev/null; then
        log "Test user created successfully"
        
        # Test pre-auth key generation
        if docker exec headscale headscale preauthkeys create --user "$test_user" --expiration 1h &>/dev/null; then
            log "Pre-auth key generated successfully"
        else
            test_fail "Failed to generate pre-auth key"
            return
        fi
        
        # Cleanup test user
        docker exec headscale headscale users delete "$test_user" &>/dev/null || true
    else
        test_fail "Failed to create test user"
        return
    fi
    
    test_pass "Headscale functionality working"
}

# Test network connectivity
test_network_connectivity() {
    test_start "Network Connectivity"
    
    # Test internal container communication
    if docker exec headscale ping -c 3 traefik &>/dev/null; then
        log "Internal container communication working"
    else
        test_fail "Internal container communication failed"
        return
    fi
    
    # Test external connectivity
    if docker exec headscale ping -c 3 8.8.8.8 &>/dev/null; then
        log "External connectivity working"
    else
        test_fail "External connectivity failed"
        return
    fi
    
    # Test DNS resolution
    if docker exec headscale nslookup google.com &>/dev/null; then
        log "DNS resolution working"
    else
        test_fail "DNS resolution failed"
        return
    fi
    
    test_pass "Network connectivity working"
}

# Test Traefik routing
test_traefik_routing() {
    test_start "Traefik Routing"
    
    # Test Traefik dashboard
    if curl -f http://localhost:8080/dashboard/ &>/dev/null; then
        log "Traefik dashboard accessible"
    else
        test_fail "Traefik dashboard not accessible"
        return
    fi
    
    # Test service routing (if services are configured)
    local test_routes=(
        "localhost:8080/ping"
    )
    
    for route in "${test_routes[@]}"; do
        if curl -f "http://$route" &>/dev/null; then
            log "Route $route working"
        else
            log "Route $route not working (may be expected)"
        fi
    done
    
    test_pass "Traefik routing functional"
}

# Test monitoring stack
test_monitoring_stack() {
    test_start "Monitoring Stack"
    
    # Test Prometheus
    if curl -f http://localhost:9090/-/ready &>/dev/null; then
        log "Prometheus ready"
        
        # Test metrics collection
        if curl -s http://localhost:9090/api/v1/query?query=up | grep -q '"status":"success"'; then
            log "Prometheus metrics collection working"
        else
            test_fail "Prometheus metrics collection failed"
            return
        fi
    else
        test_fail "Prometheus not ready"
        return
    fi
    
    # Test Grafana
    if curl -f http://localhost:3000/api/health &>/dev/null; then
        log "Grafana ready"
    else
        test_fail "Grafana not ready"
        return
    fi
    
    test_pass "Monitoring stack functional"
}

# Test SSL/TLS configuration
test_ssl_configuration() {
    test_start "SSL/TLS Configuration"
    
    # Check if Traefik SSL configuration exists
    if [[ -f "$PROJECT_DIR/config/traefik/traefik.yml" ]]; then
        if grep -q "certificatesResolvers" "$PROJECT_DIR/config/traefik/traefik.yml"; then
            log "SSL configuration found in Traefik"
        else
            test_fail "SSL configuration missing in Traefik"
            return
        fi
    else
        test_fail "Traefik configuration file not found"
        return
    fi
    
    # Check ACME configuration
    if [[ -f "$PROJECT_DIR/data/traefik/acme.json" ]]; then
        log "ACME configuration file exists"
    else
        log "ACME configuration file not found (expected for new deployment)"
    fi
    
    test_pass "SSL configuration present"
}

# Test backup functionality
test_backup_functionality() {
    test_start "Backup Functionality"
    
    # Test backup script existence
    if [[ -x "$PROJECT_DIR/scripts/backup.sh" ]]; then
        log "Backup script found and executable"
        
        # Test backup creation (dry run)
        if "$PROJECT_DIR/scripts/backup.sh" --dry-run &>/dev/null; then
            log "Backup script dry run successful"
        else
            test_fail "Backup script dry run failed"
            return
        fi
    else
        test_fail "Backup script not found or not executable"
        return
    fi
    
    test_pass "Backup functionality available"
}

# Test configuration validation
test_configuration_validation() {
    test_start "Configuration Validation"
    
    # Test Docker Compose syntax
    if docker-compose -f "$PROJECT_DIR/docker-compose.yml" config &>/dev/null; then
        log "Docker Compose configuration valid"
    else
        test_fail "Docker Compose configuration invalid"
        return
    fi
    
    # Test Headscale configuration
    if [[ -f "$PROJECT_DIR/config/headscale/config.yaml" ]]; then
        # Basic YAML syntax check
        if python3 -c "import yaml; yaml.safe_load(open('$PROJECT_DIR/config/headscale/config.yaml'))" &>/dev/null; then
            log "Headscale configuration syntax valid"
        else
            test_fail "Headscale configuration syntax invalid"
            return
        fi
    else
        test_fail "Headscale configuration file not found"
        return
    fi
    
    test_pass "Configuration validation passed"
}

# Test security configuration
test_security_configuration() {
    test_start "Security Configuration"
    
    # Check for secure defaults
    local security_issues=()
    
    # Check if containers are running as non-root (where applicable)
    local containers=$(docker ps --format "{{.Names}}")
    for container in $containers; do
        local user=$(docker exec "$container" whoami 2>/dev/null || echo "unknown")
        if [[ "$user" == "root" ]] && [[ "$container" != *"db"* ]]; then
            log "Warning: $container running as root"
        fi
    done
    
    # Check for exposed ports
    local exposed_ports=$(docker ps --format "{{.Ports}}" | grep -o "0.0.0.0:[0-9]*" | wc -l)
    if [[ $exposed_ports -gt 5 ]]; then
        security_issues+=("Many ports exposed: $exposed_ports")
    fi
    
    # Check for default passwords (basic check)
    if [[ -f "$PROJECT_DIR/.env" ]] && grep -q "password.*admin" "$PROJECT_DIR/.env"; then
        security_issues+=("Default passwords detected")
    fi
    
    if [[ ${#security_issues[@]} -eq 0 ]]; then
        test_pass "Security configuration acceptable"
    else
        test_fail "Security issues: ${security_issues[*]}"
    fi
}

# Test family service functionality
test_family_services() {
    test_start "Family Services"
    
    # Test Streamyfin (if deployed)
    if docker ps | grep -q "streamyfin"; then
        if curl -f http://localhost:8096 &>/dev/null; then
            log "Streamyfin accessible"
        else
            test_fail "Streamyfin not accessible"
            return
        fi
    else
        test_skip "Streamyfin not deployed"
    fi
    
    # Test other family services
    local family_services=("photos" "docs" "homeassistant")
    local available_services=0
    
    for service in "${family_services[@]}"; do
        if docker ps | grep -q "$service"; then
            ((available_services++))
            log "$service service is running"
        fi
    done
    
    if [[ $available_services -gt 0 ]]; then
        test_pass "Family services available ($available_services services)"
    else
        test_skip "No additional family services deployed"
    fi
}

# Test performance
test_performance() {
    test_start "Performance Tests"
    
    # Test response times
    local services=(
        "localhost:8080"
        "localhost:9090"
        "localhost:3000"
    )
    
    local slow_services=()
    
    for service in "${services[@]}"; do
        local response_time=$(curl -w "%{time_total}" -s -o /dev/null "http://$service" 2>/dev/null || echo "999")
        local response_time_ms=$(echo "$response_time * 1000" | bc 2>/dev/null || echo "999")
        
        if (( $(echo "$response_time > 5.0" | bc -l 2>/dev/null || echo 1) )); then
            slow_services+=("$service:${response_time_ms}ms")
        else
            log "$service responds in ${response_time_ms}ms"
        fi
    done
    
    # Test resource usage
    local memory_usage=$(docker stats --no-stream --format "table {{.Container}}\t{{.MemPerc}}" | grep -v CONTAINER | awk '{sum += $2} END {print sum}')
    
    if [[ -n "$memory_usage" ]] && (( $(echo "$memory_usage > 80" | bc -l 2>/dev/null || echo 0) )); then
        test_fail "High memory usage: ${memory_usage}%"
        return
    fi
    
    if [[ ${#slow_services[@]} -eq 0 ]]; then
        test_pass "Performance tests passed"
    else
        test_fail "Slow services: ${slow_services[*]}"
    fi
}

# Generate test report
generate_test_report() {
    local report_file="$TEST_RESULTS_DIR/integration-test-report.html"
    
    cat > "$report_file" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Family Network Platform - Integration Test Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background: #f0f0f0; padding: 20px; border-radius: 5px; }
        .summary { margin: 20px 0; }
        .pass { color: green; }
        .fail { color: red; }
        .skip { color: orange; }
        .test-results { margin: 20px 0; }
        .test-item { margin: 10px 0; padding: 10px; border-left: 4px solid #ddd; }
        .test-item.pass { border-left-color: green; }
        .test-item.fail { border-left-color: red; }
        .test-item.skip { border-left-color: orange; }
    </style>
</head>
<body>
    <div class="header">
        <h1>Family Network Platform - Integration Test Report</h1>
        <p>Generated: $(date)</p>
        <p>Test Environment: $(hostname)</p>
    </div>
    
    <div class="summary">
        <h2>Test Summary</h2>
        <p>Total Tests: $TESTS_TOTAL</p>
        <p class="pass">Passed: $TESTS_PASSED</p>
        <p class="fail">Failed: $TESTS_FAILED</p>
        <p>Success Rate: $(( TESTS_PASSED * 100 / TESTS_TOTAL ))%</p>
    </div>
    
    <div class="test-results">
        <h2>Test Results</h2>
EOF
    
    # Add failed tests if any
    if [[ ${#FAILED_TESTS[@]} -gt 0 ]]; then
        echo "<h3>Failed Tests</h3>" >> "$report_file"
        for test in "${FAILED_TESTS[@]}"; do
            echo "<div class=\"test-item fail\">❌ $test</div>" >> "$report_file"
        done
    fi
    
    cat >> "$report_file" << EOF
    </div>
    
    <div class="logs">
        <h2>Test Logs</h2>
        <pre>$(cat "$TEST_LOG")</pre>
    </div>
</body>
</html>
EOF
    
    log "Test report generated: $report_file"
}

# Cleanup test environment
cleanup_test_environment() {
    log "Cleaning up test environment..."
    
    # Remove test users
    docker exec headscale headscale users list | grep "test-user" | awk '{print $1}' | xargs -I {} docker exec headscale headscale users delete {} 2>/dev/null || true
    
    log "Test environment cleanup completed"
}

# Main test execution
main() {
    echo "Family Network Platform - Integration Test Suite"
    echo "================================================"
    echo
    
    setup_test_environment
    
    # Run all tests
    test_docker_environment
    test_service_deployment
    test_service_health
    test_headscale_functionality
    test_network_connectivity
    test_traefik_routing
    test_monitoring_stack
    test_ssl_configuration
    test_backup_functionality
    test_configuration_validation
    test_security_configuration
    test_family_services
    test_performance
    
    # Generate results
    echo
    echo "=================================="
    echo "Integration Test Results"
    echo "=================================="
    echo
    echo "Total Tests: $TESTS_TOTAL"
    echo "Passed: $TESTS_PASSED"
    echo "Failed: $TESTS_FAILED"
    echo "Success Rate: $(( TESTS_PASSED * 100 / TESTS_TOTAL ))%"
    
    if [[ ${#FAILED_TESTS[@]} -gt 0 ]]; then
        echo
        echo "Failed Tests:"
        for test in "${FAILED_TESTS[@]}"; do
            echo "  ❌ $test"
        done
    fi
    
    generate_test_report
    cleanup_test_environment
    
    # Exit with appropriate code
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo
        echo "✅ All tests passed! Deployment is ready for production."
        exit 0
    else
        echo
        echo "❌ Some tests failed. Please review and fix issues before production deployment."
        exit 1
    fi
}

# Handle script arguments
case "${1:-full}" in
    "full")
        main
        ;;
    "quick")
        setup_test_environment
        test_docker_environment
        test_service_deployment
        test_service_health
        echo "Quick tests completed: $TESTS_PASSED/$TESTS_TOTAL passed"
        ;;
    "security")
        setup_test_environment
        test_security_configuration
        test_ssl_configuration
        echo "Security tests completed: $TESTS_PASSED/$TESTS_TOTAL passed"
        ;;
    *)
        echo "Usage: $0 [full|quick|security]"
        echo "  full     - Complete integration test suite (default)"
        echo "  quick    - Quick deployment verification"
        echo "  security - Security-focused tests only"
        exit 1
        ;;
esac