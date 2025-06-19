#!/bin/bash

# Family Network Platform - Database Initialization Script
# Initializes and configures databases for all services

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="/backup/database"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Load environment variables
load_environment() {
    if [[ -f "$PROJECT_DIR/.env" ]]; then
        source "$PROJECT_DIR/.env"
    fi
    
    if [[ -f "$PROJECT_DIR/.env.secrets" ]]; then
        source "$PROJECT_DIR/.env.secrets"
    fi
    
    # Set defaults
    POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)}
    HEADSCALE_DB_PASSWORD=${HEADSCALE_DB_PASSWORD:-$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)}
}

# Wait for database to be ready
wait_for_database() {
    local container_name="$1"
    local max_attempts=30
    local attempt=0
    
    log "Waiting for $container_name to be ready..."
    
    while [[ $attempt -lt $max_attempts ]]; do
        if docker exec "$container_name" pg_isready -U postgres &>/dev/null 2>&1 || \
           docker exec "$container_name" mysqladmin ping -h localhost &>/dev/null 2>&1; then
            success "$container_name is ready"
            return 0
        fi
        
        ((attempt++))
        log "Waiting for $container_name... (attempt $attempt/$max_attempts)"
        sleep 5
    done
    
    error "$container_name failed to become ready"
}

# Initialize Headscale database
init_headscale_database() {
    log "Initializing Headscale database..."
    
    # Check if Headscale is using SQLite or PostgreSQL
    local db_type="sqlite3"  # Default for Headscale
    
    if [[ -f "$PROJECT_DIR/config/headscale/config.yaml" ]]; then
        db_type=$(grep "db_type:" "$PROJECT_DIR/config/headscale/config.yaml" | awk '{print $2}' || echo "sqlite3")
    fi
    
    case "$db_type" in
        "sqlite3")
            init_headscale_sqlite
            ;;
        "postgres")
            init_headscale_postgres
            ;;
        *)
            warning "Unknown database type for Headscale: $db_type"
            ;;
    esac
}

# Initialize Headscale SQLite database
init_headscale_sqlite() {
    log "Initializing Headscale SQLite database..."
    
    # Ensure Headscale container is running
    if ! docker ps | grep -q "headscale"; then
        log "Starting Headscale container..."
        docker-compose -f "$PROJECT_DIR/docker-compose.yml" up -d headscale
        sleep 10
    fi
    
    # Initialize database
    docker exec headscale headscale db init || {
        warning "Database already initialized or initialization failed"
    }
    
    # Create initial admin user if it doesn't exist
    if ! docker exec headscale headscale users list | grep -q "admin"; then
        docker exec headscale headscale users create admin
        success "Admin user created"
    else
        success "Admin user already exists"
    fi
    
    success "Headscale SQLite database initialized"
}

# Initialize Headscale PostgreSQL database
init_headscale_postgres() {
    log "Initializing Headscale PostgreSQL database..."
    
    # Wait for PostgreSQL to be ready
    wait_for_database "headscale-db"
    
    # Create Headscale database and user
    docker exec headscale-db psql -U postgres -c "CREATE DATABASE IF NOT EXISTS headscale;" || true
    docker exec headscale-db psql -U postgres -c "CREATE USER headscale WITH PASSWORD '$HEADSCALE_DB_PASSWORD';" || true
    docker exec headscale-db psql -U postgres -c "GRANT ALL PRIVILEGES ON DATABASE headscale TO headscale;" || true
    
    # Initialize Headscale database
    docker exec headscale headscale db init || {
        warning "Database already initialized or initialization failed"
    }
    
    success "Headscale PostgreSQL database initialized"
}

# Initialize Grafana database
init_grafana_database() {
    log "Initializing Grafana database..."
    
    # Ensure Grafana container is running
    if ! docker ps | grep -q "grafana"; then
        log "Starting Grafana container..."
        docker-compose -f "$PROJECT_DIR/docker-compose.yml" up -d grafana
        sleep 15
    fi
    
    # Wait for Grafana to be ready
    local max_attempts=30
    local attempt=0
    
    while [[ $attempt -lt $max_attempts ]]; do
        if curl -f http://localhost:3000/api/health &>/dev/null; then
            success "Grafana is ready"
            break
        fi
        
        ((attempt++))
        log "Waiting for Grafana... (attempt $attempt/$max_attempts)"
        sleep 5
    done
    
    if [[ $attempt -eq $max_attempts ]]; then
        error "Grafana failed to become ready"
    fi
    
    # Set admin password if provided
    if [[ -n "${GRAFANA_ADMIN_PASSWORD:-}" ]]; then
        docker exec grafana grafana-cli admin reset-admin-password "$GRAFANA_ADMIN_PASSWORD" || {
            warning "Failed to set Grafana admin password"
        }
        success "Grafana admin password configured"
    fi
    
    success "Grafana database initialized"
}

# Initialize Prometheus database
init_prometheus_database() {
    log "Initializing Prometheus database..."
    
    # Ensure Prometheus container is running
    if ! docker ps | grep -q "prometheus"; then
        log "Starting Prometheus container..."
        docker-compose -f "$PROJECT_DIR/docker-compose.yml" up -d prometheus
        sleep 10
    fi
    
    # Wait for Prometheus to be ready
    local max_attempts=30
    local attempt=0
    
    while [[ $attempt -lt $max_attempts ]]; do
        if curl -f http://localhost:9090/-/ready &>/dev/null; then
            success "Prometheus is ready"
            break
        fi
        
        ((attempt++))
        log "Waiting for Prometheus... (attempt $attempt/$max_attempts)"
        sleep 5
    done
    
    if [[ $attempt -eq $max_attempts ]]; then
        error "Prometheus failed to become ready"
    fi
    
    success "Prometheus database initialized"
}

# Initialize service-specific databases
init_service_databases() {
    log "Initializing service-specific databases..."
    
    # Check for PhotoPrism database
    if docker ps | grep -q "photos-db"; then
        log "Initializing PhotoPrism database..."
        wait_for_database "photos-db"
        
        # PhotoPrism database is automatically initialized by the container
        success "PhotoPrism database ready"
    fi
    
    # Check for Nextcloud database
    if docker ps | grep -q "docs-db"; then
        log "Initializing Nextcloud database..."
        wait_for_database "docs-db"
        
        # Nextcloud database is automatically initialized by the container
        success "Nextcloud database ready"
    fi
    
    # Check for other service databases
    local service_dbs=$(docker ps --format "{{.Names}}" | grep -E ".*-db$" | grep -v -E "(photos-db|docs-db)")
    
    for db in $service_dbs; do
        log "Initializing $db database..."
        wait_for_database "$db"
        success "$db database ready"
    done
}

# Create database backup
backup_databases() {
    log "Creating database backup..."
    
    local backup_timestamp=$(date +%Y%m%d_%H%M%S)
    mkdir -p "$BACKUP_DIR"
    
    # Backup Headscale SQLite database
    if docker exec headscale test -f /var/lib/headscale/db.sqlite; then
        docker exec headscale cp /var/lib/headscale/db.sqlite /tmp/headscale-backup.sqlite
        docker cp headscale:/tmp/headscale-backup.sqlite "$BACKUP_DIR/headscale-$backup_timestamp.sqlite"
        docker exec headscale rm /tmp/headscale-backup.sqlite
        success "Headscale database backed up"
    fi
    
    # Backup PostgreSQL databases
    local postgres_containers=$(docker ps --format "{{.Names}}" | grep -E ".*-db$" | grep postgres || true)
    
    for container in $postgres_containers; do
        local db_name=$(echo "$container" | sed 's/-db$//')
        docker exec "$container" pg_dumpall -U postgres > "$BACKUP_DIR/${db_name}-postgres-$backup_timestamp.sql"
        success "$container database backed up"
    done
    
    # Backup MySQL/MariaDB databases
    local mysql_containers=$(docker ps --format "{{.Names}}" | grep -E ".*-db$" | grep -E "(mysql|mariadb)" || true)
    
    for container in $mysql_containers; do
        local db_name=$(echo "$container" | sed 's/-db$//')
        docker exec "$container" mysqldump --all-databases -u root -p"${MYSQL_ROOT_PASSWORD:-root}" > "$BACKUP_DIR/${db_name}-mysql-$backup_timestamp.sql"
        success "$container database backed up"
    done
    
    # Backup Grafana database
    if docker ps | grep -q "grafana"; then
        docker exec grafana sqlite3 /var/lib/grafana/grafana.db .dump > "$BACKUP_DIR/grafana-$backup_timestamp.sql"
        success "Grafana database backed up"
    fi
    
    # Create compressed backup
    tar -czf "$BACKUP_DIR/database-backup-$backup_timestamp.tar.gz" -C "$BACKUP_DIR" --exclude="*.tar.gz" .
    
    success "Database backup completed: $BACKUP_DIR/database-backup-$backup_timestamp.tar.gz"
}

# Restore database from backup
restore_databases() {
    local backup_file="$1"
    
    if [[ ! -f "$backup_file" ]]; then
        error "Backup file not found: $backup_file"
    fi
    
    log "Restoring databases from $backup_file..."
    
    # Extract backup
    local temp_dir="/tmp/db-restore-$$"
    mkdir -p "$temp_dir"
    tar -xzf "$backup_file" -C "$temp_dir"
    
    # Stop services
    log "Stopping services..."
    docker-compose -f "$PROJECT_DIR/docker-compose.yml" stop
    
    # Restore Headscale SQLite database
    if [[ -f "$temp_dir"/headscale-*.sqlite ]]; then
        local headscale_backup=$(ls "$temp_dir"/headscale-*.sqlite | head -1)
        docker-compose -f "$PROJECT_DIR/docker-compose.yml" up -d headscale
        sleep 10
        docker cp "$headscale_backup" headscale:/var/lib/headscale/db.sqlite
        success "Headscale database restored"
    fi
    
    # Restore PostgreSQL databases
    for sql_file in "$temp_dir"/*-postgres-*.sql; do
        if [[ -f "$sql_file" ]]; then
            local db_name=$(basename "$sql_file" | sed 's/-postgres-.*\.sql$//')
            local container="${db_name}-db"
            
            if docker ps -a --format "{{.Names}}" | grep -q "$container"; then
                docker-compose -f "$PROJECT_DIR/docker-compose.yml" up -d "$container"
                wait_for_database "$container"
                docker exec -i "$container" psql -U postgres < "$sql_file"
                success "$container database restored"
            fi
        fi
    done
    
    # Restore MySQL/MariaDB databases
    for sql_file in "$temp_dir"/*-mysql-*.sql; do
        if [[ -f "$sql_file" ]]; then
            local db_name=$(basename "$sql_file" | sed 's/-mysql-.*\.sql$//')
            local container="${db_name}-db"
            
            if docker ps -a --format "{{.Names}}" | grep -q "$container"; then
                docker-compose -f "$PROJECT_DIR/docker-compose.yml" up -d "$container"
                wait_for_database "$container"
                docker exec -i "$container" mysql -u root -p"${MYSQL_ROOT_PASSWORD:-root}" < "$sql_file"
                success "$container database restored"
            fi
        fi
    done
    
    # Restore Grafana database
    if [[ -f "$temp_dir"/grafana-*.sql ]]; then
        local grafana_backup=$(ls "$temp_dir"/grafana-*.sql | head -1)
        docker-compose -f "$PROJECT_DIR/docker-compose.yml" up -d grafana
        sleep 15
        docker exec -i grafana sqlite3 /var/lib/grafana/grafana.db < "$grafana_backup"
        success "Grafana database restored"
    fi
    
    # Restart all services
    log "Restarting all services..."
    docker-compose -f "$PROJECT_DIR/docker-compose.yml" up -d
    
    # Cleanup
    rm -rf "$temp_dir"
    
    success "Database restoration completed"
}

# Optimize databases
optimize_databases() {
    log "Optimizing databases..."
    
    # Optimize Headscale SQLite database
    if docker exec headscale test -f /var/lib/headscale/db.sqlite; then
        docker exec headscale sqlite3 /var/lib/headscale/db.sqlite "VACUUM; ANALYZE;"
        success "Headscale database optimized"
    fi
    
    # Optimize PostgreSQL databases
    local postgres_containers=$(docker ps --format "{{.Names}}" | grep -E ".*-db$" | grep postgres || true)
    
    for container in $postgres_containers; do
        docker exec "$container" psql -U postgres -c "VACUUM ANALYZE;"
        success "$container database optimized"
    done
    
    # Optimize MySQL/MariaDB databases
    local mysql_containers=$(docker ps --format "{{.Names}}" | grep -E ".*-db$" | grep -E "(mysql|mariadb)" || true)
    
    for container in $mysql_containers; do
        docker exec "$container" mysqlcheck --optimize --all-databases -u root -p"${MYSQL_ROOT_PASSWORD:-root}"
        success "$container database optimized"
    done
    
    # Optimize Grafana database
    if docker ps | grep -q "grafana"; then
        docker exec grafana sqlite3 /var/lib/grafana/grafana.db "VACUUM; ANALYZE;"
        success "Grafana database optimized"
    fi
    
    success "Database optimization completed"
}

# Check database health
check_database_health() {
    log "Checking database health..."
    
    local unhealthy_dbs=()
    
    # Check Headscale database
    if docker ps | grep -q "headscale"; then
        if docker exec headscale headscale db status &>/dev/null; then
            success "Headscale database: healthy"
        else
            warning "Headscale database: unhealthy"
            unhealthy_dbs+=("headscale")
        fi
    fi
    
    # Check PostgreSQL databases
    local postgres_containers=$(docker ps --format "{{.Names}}" | grep -E ".*-db$" | grep postgres || true)
    
    for container in $postgres_containers; do
        if docker exec "$container" pg_isready -U postgres &>/dev/null; then
            success "$container: healthy"
        else
            warning "$container: unhealthy"
            unhealthy_dbs+=("$container")
        fi
    done
    
    # Check MySQL/MariaDB databases
    local mysql_containers=$(docker ps --format "{{.Names}}" | grep -E ".*-db$" | grep -E "(mysql|mariadb)" || true)
    
    for container in $mysql_containers; do
        if docker exec "$container" mysqladmin ping -h localhost &>/dev/null; then
            success "$container: healthy"
        else
            warning "$container: unhealthy"
            unhealthy_dbs+=("$container")
        fi
    done
    
    # Check Grafana database
    if docker ps | grep -q "grafana"; then
        if curl -f http://localhost:3000/api/health &>/dev/null; then
            success "Grafana database: healthy"
        else
            warning "Grafana database: unhealthy"
            unhealthy_dbs+=("grafana")
        fi
    fi
    
    if [[ ${#unhealthy_dbs[@]} -eq 0 ]]; then
        success "All databases are healthy"
    else
        warning "Unhealthy databases: ${unhealthy_dbs[*]}"
    fi
}

# Reset all databases
reset_databases() {
    warning "This will delete all database data. Are you sure? (y/N)"
    read -r confirmation
    
    if [[ "$confirmation" != "y" && "$confirmation" != "Y" ]]; then
        log "Database reset cancelled"
        return
    fi
    
    log "Resetting all databases..."
    
    # Create backup before reset
    backup_databases
    
    # Stop all services
    docker-compose -f "$PROJECT_DIR/docker-compose.yml" down
    
    # Remove database volumes
    docker volume rm $(docker volume ls -q | grep -E "(headscale|grafana|prometheus|photos|docs).*data") 2>/dev/null || true
    
    # Restart services
    docker-compose -f "$PROJECT_DIR/docker-compose.yml" up -d
    
    # Reinitialize databases
    sleep 30
    init_headscale_database
    init_grafana_database
    init_prometheus_database
    init_service_databases
    
    success "Database reset completed"
}

# Main database initialization function
main() {
    local action="${1:-init}"
    
    log "Starting database operations (action: $action)..."
    
    load_environment
    
    case "$action" in
        "init")
            init_headscale_database
            init_grafana_database
            init_prometheus_database
            init_service_databases
            ;;
        "backup")
            backup_databases
            ;;
        "restore")
            if [[ -z "${2:-}" ]]; then
                error "Backup file required for restore action"
            fi
            restore_databases "$2"
            ;;
        "optimize")
            optimize_databases
            ;;
        "health")
            check_database_health
            ;;
        "reset")
            reset_databases
            ;;
        *)
            error "Invalid action. Use: init, backup, restore, optimize, health, or reset"
            ;;
    esac
    
    success "Database operations completed"
}

# Handle script arguments
if [[ $# -eq 0 ]]; then
    echo "Family Network Platform - Database Initialization"
    echo "Usage: $0 <action> [options]"
    echo
    echo "Actions:"
    echo "  init     - Initialize all databases (default)"
    echo "  backup   - Create database backup"
    echo "  restore  - Restore databases from backup file"
    echo "  optimize - Optimize database performance"
    echo "  health   - Check database health"
    echo "  reset    - Reset all databases (destructive)"
    echo
    echo "Examples:"
    echo "  $0 init                           # Initialize databases"
    echo "  $0 backup                         # Create backup"
    echo "  $0 restore backup.tar.gz          # Restore from backup"
    echo "  $0 health                         # Check health"
    exit 1
fi

main "$@"