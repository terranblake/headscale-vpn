#!/bin/bash

# Family Network Platform - Environment Validation Script
# Validates system requirements and configuration before deployment

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Validation results
VALIDATION_PASSED=true
WARNINGS=()
ERRORS=()

# Logging functions
info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    WARNINGS+=("$1")
}

error() {
    echo -e "${RED}[FAIL]${NC} $1"
    ERRORS+=("$1")
    VALIDATION_PASSED=false
}

# Check system requirements
check_system_requirements() {
    info "Checking system requirements..."
    
    # Check operating system
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        if [[ "$ID" == "ubuntu" ]]; then
            local version_major=$(echo "$VERSION_ID" | cut -d. -f1)
            if [[ $version_major -ge 20 ]]; then
                success "Operating System: Ubuntu $VERSION_ID (supported)"
            else
                warning "Operating System: Ubuntu $VERSION_ID (older version, may have compatibility issues)"
            fi
        else
            warning "Operating System: $PRETTY_NAME (not Ubuntu, may have compatibility issues)"
        fi
    else
        warning "Cannot determine operating system"
    fi
    
    # Check architecture
    local arch=$(uname -m)
    if [[ "$arch" == "x86_64" ]]; then
        success "Architecture: $arch (supported)"
    else
        warning "Architecture: $arch (may have limited Docker image support)"
    fi
    
    # Check kernel version
    local kernel_version=$(uname -r)
    local kernel_major=$(echo "$kernel_version" | cut -d. -f1)
    local kernel_minor=$(echo "$kernel_version" | cut -d. -f2)
    
    if [[ $kernel_major -gt 5 ]] || [[ $kernel_major -eq 5 && $kernel_minor -ge 4 ]]; then
        success "Kernel Version: $kernel_version (supported)"
    else
        warning "Kernel Version: $kernel_version (older kernel, may affect WireGuard performance)"
    fi
}

# Check hardware requirements
check_hardware_requirements() {
    info "Checking hardware requirements..."
    
    # Check CPU cores
    local cpu_cores=$(nproc)
    if [[ $cpu_cores -ge 4 ]]; then
        success "CPU Cores: $cpu_cores (sufficient)"
    elif [[ $cpu_cores -ge 2 ]]; then
        warning "CPU Cores: $cpu_cores (minimum met, but 4+ recommended for optimal performance)"
    else
        error "CPU Cores: $cpu_cores (insufficient, minimum 2 cores required)"
    fi
    
    # Check total memory
    local total_memory_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local total_memory_gb=$((total_memory_kb / 1024 / 1024))
    
    if [[ $total_memory_gb -ge 8 ]]; then
        success "Total Memory: ${total_memory_gb}GB (sufficient)"
    elif [[ $total_memory_gb -ge 4 ]]; then
        warning "Total Memory: ${total_memory_gb}GB (minimum met, but 8GB+ recommended)"
    else
        error "Total Memory: ${total_memory_gb}GB (insufficient, minimum 4GB required)"
    fi
    
    # Check available memory
    local available_memory_kb=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
    local available_memory_gb=$((available_memory_kb / 1024 / 1024))
    
    if [[ $available_memory_gb -ge 2 ]]; then
        success "Available Memory: ${available_memory_gb}GB (sufficient)"
    else
        warning "Available Memory: ${available_memory_gb}GB (low, may affect performance)"
    fi
    
    # Check disk space
    local available_space_kb=$(df "$PROJECT_DIR" | awk 'NR==2 {print $4}')
    local available_space_gb=$((available_space_kb / 1024 / 1024))
    
    if [[ $available_space_gb -ge 100 ]]; then
        success "Available Disk Space: ${available_space_gb}GB (sufficient)"
    elif [[ $available_space_gb -ge 50 ]]; then
        warning "Available Disk Space: ${available_space_gb}GB (minimum met, but 100GB+ recommended)"
    else
        error "Available Disk Space: ${available_space_gb}GB (insufficient, minimum 50GB required)"
    fi
}

# Check required software
check_required_software() {
    info "Checking required software..."
    
    # Required commands and their minimum versions
    local required_software=(
        "docker:20.10.0"
        "docker-compose:1.29.0"
        "curl:7.0.0"
        "openssl:1.1.0"
        "git:2.0.0"
        "make:4.0"
    )
    
    for software in "${required_software[@]}"; do
        local cmd="${software%:*}"
        local min_version="${software#*:}"
        
        if command -v "$cmd" &> /dev/null; then
            local version=""
            case "$cmd" in
                "docker")
                    version=$(docker --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
                    ;;
                "docker-compose")
                    version=$(docker-compose --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
                    ;;
                "curl")
                    version=$(curl --version | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
                    ;;
                "openssl")
                    version=$(openssl version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
                    ;;
                "git")
                    version=$(git --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
                    ;;
                "make")
                    version=$(make --version | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
                    ;;
            esac
            
            if [[ -n "$version" ]]; then
                success "$cmd: $version (installed)"
            else
                warning "$cmd: installed but version could not be determined"
            fi
        else
            error "$cmd: not installed (required)"
        fi
    done
}

# Check Docker configuration
check_docker_configuration() {
    info "Checking Docker configuration..."
    
    # Check if Docker daemon is running
    if docker info &> /dev/null; then
        success "Docker daemon: running"
        
        # Check Docker version
        local docker_version=$(docker version --format '{{.Server.Version}}' 2>/dev/null)
        if [[ -n "$docker_version" ]]; then
            success "Docker server version: $docker_version"
        fi
        
        # Check if user can run Docker without sudo
        if docker ps &> /dev/null; then
            success "Docker permissions: user can run Docker commands"
        else
            error "Docker permissions: user cannot run Docker commands (add user to docker group)"
        fi
        
        # Check Docker storage driver
        local storage_driver=$(docker info --format '{{.Driver}}' 2>/dev/null)
        if [[ "$storage_driver" == "overlay2" ]]; then
            success "Docker storage driver: $storage_driver (recommended)"
        else
            warning "Docker storage driver: $storage_driver (overlay2 recommended)"
        fi
        
        # Check available Docker disk space
        local docker_space=$(docker system df --format 'table {{.Type}}\t{{.Size}}' | grep -E "Images|Containers|Local Volumes" | awk '{sum += $2} END {print sum}')
        if [[ -n "$docker_space" ]]; then
            info "Docker disk usage: checking available space"
        fi
        
    else
        error "Docker daemon: not running or not accessible"
    fi
    
    # Check Docker Compose
    if command -v docker-compose &> /dev/null; then
        if docker-compose version &> /dev/null; then
            local compose_version=$(docker-compose version --short 2>/dev/null)
            success "Docker Compose: $compose_version (working)"
        else
            error "Docker Compose: installed but not working"
        fi
    else
        error "Docker Compose: not installed"
    fi
}

# Check network configuration
check_network_configuration() {
    info "Checking network configuration..."
    
    # Check if required ports are available
    local required_ports=(80 443 8080 8096 9090 3000 41641)
    local occupied_ports=()
    
    for port in "${required_ports[@]}"; do
        if ss -tuln | grep -q ":$port "; then
            occupied_ports+=("$port")
        fi
    done
    
    if [[ ${#occupied_ports[@]} -eq 0 ]]; then
        success "Required ports: all available"
    else
        warning "Required ports: ports ${occupied_ports[*]} are already in use"
    fi
    
    # Check internet connectivity
    if curl -s --max-time 10 https://google.com &> /dev/null; then
        success "Internet connectivity: available"
    else
        error "Internet connectivity: not available (required for Docker images and SSL certificates)"
    fi
    
    # Check DNS resolution
    if nslookup google.com &> /dev/null; then
        success "DNS resolution: working"
    else
        error "DNS resolution: not working"
    fi
    
    # Check if firewall is configured
    if command -v ufw &> /dev/null; then
        local ufw_status=$(sudo ufw status | head -1)
        if [[ "$ufw_status" == *"active"* ]]; then
            success "Firewall: UFW is active"
        else
            warning "Firewall: UFW is not active (recommended for security)"
        fi
    else
        warning "Firewall: UFW not installed (recommended for security)"
    fi
}

# Check file permissions and ownership
check_file_permissions() {
    info "Checking file permissions and ownership..."
    
    # Check project directory permissions
    if [[ -r "$PROJECT_DIR" && -w "$PROJECT_DIR" && -x "$PROJECT_DIR" ]]; then
        success "Project directory: readable and writable"
    else
        error "Project directory: insufficient permissions"
    fi
    
    # Check if running as root (should not be)
    if [[ $EUID -eq 0 ]]; then
        error "Running as root: deployment should not be run as root user"
    else
        success "User permissions: not running as root (good)"
    fi
    
    # Check sudo access
    if sudo -n true 2>/dev/null; then
        success "Sudo access: available without password"
    elif sudo -v 2>/dev/null; then
        success "Sudo access: available with password"
    else
        warning "Sudo access: not available (may be needed for some operations)"
    fi
    
    # Check Docker socket permissions
    if [[ -S /var/run/docker.sock ]]; then
        if [[ -r /var/run/docker.sock && -w /var/run/docker.sock ]]; then
            success "Docker socket: accessible"
        else
            error "Docker socket: not accessible (add user to docker group)"
        fi
    else
        error "Docker socket: not found"
    fi
}

# Check configuration files
check_configuration_files() {
    info "Checking configuration files..."
    
    # Check if example files exist
    local example_files=(
        ".env.example"
        "docker-compose.yml"
        "Makefile"
    )
    
    for file in "${example_files[@]}"; do
        if [[ -f "$PROJECT_DIR/$file" ]]; then
            success "Configuration file: $file exists"
        else
            warning "Configuration file: $file not found"
        fi
    done
    
    # Check docker-compose.yml syntax
    if [[ -f "$PROJECT_DIR/docker-compose.yml" ]]; then
        if docker-compose -f "$PROJECT_DIR/docker-compose.yml" config &> /dev/null; then
            success "Docker Compose syntax: valid"
        else
            error "Docker Compose syntax: invalid"
        fi
    fi
    
    # Check if config directories exist
    local config_dirs=(
        "config"
        "scripts"
        "docs"
    )
    
    for dir in "${config_dirs[@]}"; do
        if [[ -d "$PROJECT_DIR/$dir" ]]; then
            success "Directory: $dir exists"
        else
            warning "Directory: $dir not found"
        fi
    done
}

# Check security requirements
check_security_requirements() {
    info "Checking security requirements..."
    
    # Check if SSH is properly configured
    if [[ -f /etc/ssh/sshd_config ]]; then
        local permit_root=$(grep "^PermitRootLogin" /etc/ssh/sshd_config | awk '{print $2}')
        if [[ "$permit_root" == "no" ]]; then
            success "SSH security: root login disabled"
        else
            warning "SSH security: root login enabled (should be disabled)"
        fi
        
        local password_auth=$(grep "^PasswordAuthentication" /etc/ssh/sshd_config | awk '{print $2}')
        if [[ "$password_auth" == "no" ]]; then
            success "SSH security: password authentication disabled"
        else
            warning "SSH security: password authentication enabled (key-based auth recommended)"
        fi
    fi
    
    # Check for automatic updates
    if [[ -f /etc/apt/apt.conf.d/50unattended-upgrades ]]; then
        success "Security updates: automatic updates configured"
    else
        warning "Security updates: automatic updates not configured"
    fi
    
    # Check if fail2ban is installed
    if command -v fail2ban-client &> /dev/null; then
        success "Intrusion prevention: fail2ban installed"
    else
        warning "Intrusion prevention: fail2ban not installed (recommended)"
    fi
}

# Generate validation report
generate_validation_report() {
    echo
    echo "=================================="
    echo "Environment Validation Summary"
    echo "=================================="
    echo
    
    if [[ $VALIDATION_PASSED == true ]]; then
        success "Overall Status: PASSED - Environment is ready for deployment"
    else
        error "Overall Status: FAILED - Environment has critical issues"
    fi
    
    echo
    echo "Summary:"
    echo "- Errors: ${#ERRORS[@]}"
    echo "- Warnings: ${#WARNINGS[@]}"
    
    if [[ ${#ERRORS[@]} -gt 0 ]]; then
        echo
        echo "Critical Issues (must be fixed):"
        for error in "${ERRORS[@]}"; do
            echo "  ❌ $error"
        done
    fi
    
    if [[ ${#WARNINGS[@]} -gt 0 ]]; then
        echo
        echo "Warnings (recommended to fix):"
        for warning in "${WARNINGS[@]}"; do
            echo "  ⚠️  $warning"
        done
    fi
    
    echo
    echo "Next Steps:"
    if [[ $VALIDATION_PASSED == true ]]; then
        echo "✅ Environment validation passed"
        echo "✅ You can proceed with deployment: ./scripts/deploy.sh"
    else
        echo "❌ Fix critical issues before deployment"
        echo "❌ Re-run validation: ./scripts/validate-environment.sh"
    fi
    
    echo
    echo "For help with issues, see: docs/02-technical-reference/troubleshooting.md"
}

# Main validation function
main() {
    echo "Family Network Platform - Environment Validation"
    echo "================================================"
    echo
    
    check_system_requirements
    check_hardware_requirements
    check_required_software
    check_docker_configuration
    check_network_configuration
    check_file_permissions
    check_configuration_files
    check_security_requirements
    
    generate_validation_report
    
    # Exit with appropriate code
    if [[ $VALIDATION_PASSED == true ]]; then
        exit 0
    else
        exit 1
    fi
}

# Handle script arguments
case "${1:-full}" in
    "full")
        main
        ;;
    "system")
        check_system_requirements
        check_hardware_requirements
        ;;
    "software")
        check_required_software
        check_docker_configuration
        ;;
    "network")
        check_network_configuration
        ;;
    "security")
        check_security_requirements
        ;;
    "config")
        check_configuration_files
        ;;
    *)
        echo "Usage: $0 [full|system|software|network|security|config]"
        echo "  full     - Complete validation (default)"
        echo "  system   - System and hardware requirements"
        echo "  software - Required software and Docker"
        echo "  network  - Network configuration and connectivity"
        echo "  security - Security configuration"
        echo "  config   - Configuration files"
        exit 1
        ;;
esac