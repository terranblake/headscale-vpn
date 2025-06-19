#!/bin/bash
# Backup script for headscale-vpn deployment

set -e

# Configuration
BACKUP_DIR=${BACKUP_DIR:-./backups}
BACKUP_NAME="headscale-backup-$(date +%Y%m%d-%H%M%S)"
RETENTION_DAYS=${RETENTION_DAYS:-30}

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

# Create backup directory
mkdir -p "$BACKUP_DIR/$BACKUP_NAME"

log_info "Starting backup: $BACKUP_NAME"

# Backup database
log_info "Backing up PostgreSQL database..."
docker exec headscale-db pg_dump -U headscale headscale > "$BACKUP_DIR/$BACKUP_NAME/database.sql"

# Backup headscale data
log_info "Backing up Headscale data..."
docker cp headscale:/var/lib/headscale "$BACKUP_DIR/$BACKUP_NAME/headscale-data"

# Backup configuration files
log_info "Backing up configuration files..."
cp -r config "$BACKUP_DIR/$BACKUP_NAME/"
cp .env "$BACKUP_DIR/$BACKUP_NAME/" 2>/dev/null || log_warn ".env file not found"
cp docker-compose.yml "$BACKUP_DIR/$BACKUP_NAME/"

# Backup certificates
log_info "Backing up certificates..."
docker cp headscale:/var/lib/headscale/private.key "$BACKUP_DIR/$BACKUP_NAME/" 2>/dev/null || log_warn "Private key not found"
docker cp headscale:/var/lib/headscale/noise_private.key "$BACKUP_DIR/$BACKUP_NAME/" 2>/dev/null || log_warn "Noise private key not found"

# Create archive
log_info "Creating backup archive..."
cd "$BACKUP_DIR"
tar -czf "$BACKUP_NAME.tar.gz" "$BACKUP_NAME"
rm -rf "$BACKUP_NAME"

# Cleanup old backups
log_info "Cleaning up old backups (retention: $RETENTION_DAYS days)..."
find "$BACKUP_DIR" -name "headscale-backup-*.tar.gz" -mtime +$RETENTION_DAYS -delete

log_info "Backup completed: $BACKUP_DIR/$BACKUP_NAME.tar.gz"