#!/bin/bash
# Health check script for headscale-vpn deployment

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
HEADSCALE_URL=${HEADSCALE_URL:-http://localhost:8080}
CHECK_INTERVAL=${CHECK_INTERVAL:-30}
LOG_FILE=${LOG_FILE:-/var/log/headscale-health.log}

log_with_timestamp() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

check_container_health() {
    local container_name="$1"
    local status=$(docker inspect --format='{{.State.Health.Status}}' "$container_name" 2>/dev/null || echo "not_found")
    
    case "$status" in
        "healthy")
            echo -e "${GREEN}✓${NC} $container_name: healthy"
            return 0
            ;;
        "unhealthy")
            echo -e "${RED}✗${NC} $container_name: unhealthy"
            return 1
            ;;
        "starting")
            echo -e "${YELLOW}⚠${NC} $container_name: starting"
            return 1
            ;;
        "not_found")
            echo -e "${RED}✗${NC} $container_name: not found"
            return 1
            ;;
        *)
            echo -e "${YELLOW}?${NC} $container_name: unknown status ($status)"
            return 1
            ;;
    esac
}

check_headscale_api() {
    if curl -s --max-time 10 "$HEADSCALE_URL/health" >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} Headscale API: accessible"
        return 0
    else
        echo -e "${RED}✗${NC} Headscale API: not accessible"
        return 1
    fi
}

check_database() {
    if docker exec headscale-db pg_isready -U headscale >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} Database: ready"
        return 0
    else
        echo -e "${RED}✗${NC} Database: not ready"
        return 1
    fi
}

check_vpn_connection() {
    if docker exec vpn-exit-node pgrep openvpn >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} VPN Connection: active"
        return 0
    else
        echo -e "${RED}✗${NC} VPN Connection: inactive"
        return 1
    fi
}

check_tailscale_status() {
    local container="$1"
    local status=$(docker exec "$container" tailscale status --json 2>/dev/null | jq -r '.BackendState' 2>/dev/null || echo "unknown")
    
    if [[ "$status" == "Running" ]]; then
        echo -e "${GREEN}✓${NC} $container Tailscale: running"
        return 0
    else
        echo -e "${RED}✗${NC} $container Tailscale: $status"
        return 1
    fi
}

perform_health_check() {
    local failed_checks=0
    
    echo "Headscale VPN Health Check - $(date)"
    echo "=================================="
    
    # Check container health
    local containers=("headscale" "headscale-db" "headscale-ui" "vpn-exit-node")
    for container in "${containers[@]}"; do
        if ! check_container_health "$container"; then
            ((failed_checks++))
        fi
    done
    
    # Check proxy gateway if running
    if docker ps | grep -q "proxy-gateway"; then
        if ! check_container_health "proxy-gateway"; then
            ((failed_checks++))
        fi
        if ! check_tailscale_status "proxy-gateway"; then
            ((failed_checks++))
        fi
    fi
    
    # Check services
    if ! check_headscale_api; then
        ((failed_checks++))
    fi
    
    if ! check_database; then
        ((failed_checks++))
    fi
    
    if ! check_vpn_connection; then
        ((failed_checks++))
    fi
    
    if ! check_tailscale_status "vpn-exit-node"; then
        ((failed_checks++))
    fi
    
    echo "=================================="
    if [ $failed_checks -eq 0 ]; then
        echo -e "${GREEN}All health checks passed ✅${NC}"
        log_with_timestamp "Health check passed - all services healthy"
        return 0
    else
        echo -e "${RED}$failed_checks health check(s) failed ❌${NC}"
        log_with_timestamp "Health check failed - $failed_checks issues detected"
        return 1
    fi
}

# Continuous monitoring mode
monitor_mode() {
    echo "Starting continuous health monitoring (interval: ${CHECK_INTERVAL}s)"
    echo "Logs will be written to: $LOG_FILE"
    
    while true; do
        perform_health_check
        echo
        sleep "$CHECK_INTERVAL"
    done
}

# Main execution
case "${1:-check}" in
    "check")
        perform_health_check
        ;;
    "monitor")
        monitor_mode
        ;;
    *)
        echo "Usage: $0 [check|monitor]"
        echo "  check   - Perform a single health check"
        echo "  monitor - Continuous monitoring mode"
        exit 1
        ;;
esac