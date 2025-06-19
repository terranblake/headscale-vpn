#!/bin/bash
# Restore script for headscale-vpn deployment

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check arguments
if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <backup-file.tar.gz>"
    exit 1
fi

BACKUP_FILE="$1"

if [[ ! -f "$BACKUP_FILE" ]]; then
    log_error "Backup file not found: $BACKUP_FILE"
    exit 1
fi

# Confirmation
echo -e "${YELLOW}WARNING: This will restore from backup and overwrite current data!${NC}"
read -p "Are you sure you want to continue? (yes/no): " confirm
if [[ "$confirm" != "yes" ]]; then
    log_info "Restore cancelled"
    exit 0
fi

# Stop services
log_info "Stopping services..."
docker-compose down

# Extract backup
RESTORE_DIR="/tmp/headscale-restore-$$"
mkdir -p "$RESTORE_DIR"
tar -xzf "$BACKUP_FILE" -C "$RESTORE_DIR"

BACKUP_NAME=$(basename "$BACKUP_FILE" .tar.gz)
BACKUP_PATH="$RESTORE_DIR/$BACKUP_NAME"

# Restore configuration
log_info "Restoring configuration files..."
cp -r "$BACKUP_PATH/config" ./
cp "$BACKUP_PATH/.env" ./ 2>/dev/null || log_warn ".env not found in backup"
cp "$BACKUP_PATH/docker-compose.yml" ./

# Start database
log_info "Starting database..."
docker-compose up -d headscale-db

# Wait for database
log_info "Waiting for database to be ready..."
sleep 10
while ! docker exec headscale-db pg_isready -U headscale >/dev/null 2>&1; do
    sleep 2
done

# Restore database
log_info "Restoring database..."
docker exec -i headscale-db psql -U headscale -d headscale < "$BACKUP_PATH/database.sql"

# Start headscale
log_info "Starting Headscale..."
docker-compose up -d headscale

# Wait for headscale
sleep 5

# Restore headscale data
log_info "Restoring Headscale data..."
docker cp "$BACKUP_PATH/headscale-data/." headscale:/var/lib/headscale/

# Restore certificates
if [[ -f "$BACKUP_PATH/private.key" ]]; then
    log_info "Restoring private key..."
    docker cp "$BACKUP_PATH/private.key" headscale:/var/lib/headscale/
fi

if [[ -f "$BACKUP_PATH/noise_private.key" ]]; then
    log_info "Restoring noise private key..."
    docker cp "$BACKUP_PATH/noise_private.key" headscale:/var/lib/headscale/
fi

# Restart headscale to pick up restored data
log_info "Restarting Headscale..."
docker-compose restart headscale

# Start all services
log_info "Starting all services..."
docker-compose up -d

# Cleanup
rm -rf "$RESTORE_DIR"

log_info "Restore completed successfully!"
log_info "Please verify that all services are working correctly."