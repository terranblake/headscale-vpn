# Production Deployment Guide

This guide covers deploying headscale-vpn in a production environment with proper security, monitoring, and maintenance procedures.

## Prerequisites

- Linux server with Docker and Docker Compose
- Domain name with DNS control
- SSL certificate (Let's Encrypt recommended)
- Minimum 2GB RAM, 20GB storage
- Open ports: 80, 443, 8080, 3478/UDP

## Security Hardening

### 1. SSL/TLS Configuration

```bash
# Generate SSL certificates with Let's Encrypt
sudo certbot certonly --standalone -d your-domain.com

# Copy certificates to config directory
sudo cp /etc/letsencrypt/live/your-domain.com/fullchain.pem config/headscale/tls/cert.pem
sudo cp /etc/letsencrypt/live/your-domain.com/privkey.pem config/headscale/tls/key.pem
```

### 2. Environment Security

```bash
# Set secure environment variables
export POSTGRES_PASSWORD=$(openssl rand -base64 32)
export HEADSCALE_PREAUTH_KEY=$(openssl rand -base64 32)

# Restrict file permissions
chmod 600 .env
chmod 600 config/headscale/config.yaml
```

### 3. Firewall Configuration

```bash
# UFW example
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 8080/tcp
sudo ufw allow 3478/udp
sudo ufw enable
```

## Production Configuration

### 1. Update Headscale Config

Edit `config/headscale/config.yaml`:

```yaml
server_url: https://your-domain.com
listen_addr: 0.0.0.0:8080
metrics_listen_addr: 127.0.0.1:9090

tls_cert_path: /etc/headscale/tls/cert.pem
tls_key_path: /etc/headscale/tls/key.pem

log:
  level: info
  format: json

database:
  type: postgres
  postgres:
    host: headscale-db
    port: 5432
    name: headscale
    user: headscale
    password: ${POSTGRES_PASSWORD}
    max_open_conns: 10
    max_idle_conns: 5
    conn_max_idle_time: 3600s
```

### 2. Docker Compose Production Override

Create `docker-compose.prod.yml`:

```yaml
version: '3.8'

services:
  headscale:
    restart: unless-stopped
    ports:
      - "443:8080"
    volumes:
      - ./config/headscale/tls:/etc/headscale/tls:ro
    healthcheck:
      test: ["CMD", "curl", "-f", "https://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3

  headscale-db:
    restart: unless-stopped
    volumes:
      - postgres-data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U headscale"]
      interval: 30s
      timeout: 5s
      retries: 3

  vpn-exit-node:
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "tailscale", "status"]
      interval: 60s
      timeout: 10s
      retries: 3

volumes:
  postgres-data:
    driver: local
```

### 3. Reverse Proxy (Optional)

If using nginx as reverse proxy:

```nginx
server {
    listen 80;
    server_name your-domain.com;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name your-domain.com;

    ssl_certificate /etc/letsencrypt/live/your-domain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/your-domain.com/privkey.pem;

    location / {
        proxy_pass http://localhost:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

## Monitoring and Alerting

### 1. Health Monitoring

Set up continuous monitoring:

```bash
# Add to crontab
*/5 * * * * /path/to/headscale-vpn/scripts/health-check.sh check >> /var/log/headscale-health.log 2>&1
```

### 2. Log Management

Configure log rotation:

```bash
# /etc/logrotate.d/headscale-vpn
/var/log/headscale-*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
}
```

### 3. Metrics Collection

Enable Prometheus metrics in headscale config and set up monitoring stack.

## Backup Strategy

### 1. Automated Backups

```bash
# Add to crontab for daily backups
0 2 * * * /path/to/headscale-vpn/scripts/backup.sh
```

### 2. Backup Verification

```bash
# Weekly backup verification
0 3 * * 0 /path/to/headscale-vpn/scripts/verify-backup.sh
```

### 3. Off-site Storage

Configure backup sync to remote storage:

```bash
# Example with rsync
rsync -av --delete /path/to/backups/ user@backup-server:/backups/headscale/
```

## Maintenance Procedures

### 1. Updates

```bash
# Update containers
docker-compose pull
docker-compose up -d

# Update system
sudo apt update && sudo apt upgrade -y
```

### 2. Certificate Renewal

```bash
# Renew Let's Encrypt certificates
sudo certbot renew --quiet
sudo systemctl reload nginx  # if using nginx
```

### 3. Database Maintenance

```bash
# Vacuum database monthly
docker exec headscale-db psql -U headscale -d headscale -c "VACUUM ANALYZE;"
```

## Troubleshooting

### 1. Service Issues

```bash
# Check service status
make health

# View logs
docker-compose logs -f headscale
docker-compose logs -f vpn-exit-node
```

### 2. Network Issues

```bash
# Test connectivity
make vpn-status
make vpn-ip

# Check routing
docker exec vpn-exit-node ip route
```

### 3. Database Issues

```bash
# Check database connection
docker exec headscale-db pg_isready -U headscale

# Database backup before maintenance
make backup
```

## Performance Tuning

### 1. Database Optimization

```sql
-- Optimize PostgreSQL settings
ALTER SYSTEM SET shared_buffers = '256MB';
ALTER SYSTEM SET effective_cache_size = '1GB';
ALTER SYSTEM SET maintenance_work_mem = '64MB';
SELECT pg_reload_conf();
```

### 2. Container Resources

```yaml
# Add to docker-compose.yml
services:
  headscale:
    deploy:
      resources:
        limits:
          memory: 512M
        reservations:
          memory: 256M
```

### 3. Network Optimization

```bash
# Optimize network settings
echo 'net.core.rmem_max = 16777216' >> /etc/sysctl.conf
echo 'net.core.wmem_max = 16777216' >> /etc/sysctl.conf
sysctl -p
```

## Security Checklist

- [ ] SSL/TLS certificates configured
- [ ] Firewall rules in place
- [ ] Strong passwords and keys
- [ ] Regular security updates
- [ ] Log monitoring enabled
- [ ] Backup encryption configured
- [ ] Access controls implemented
- [ ] Network segmentation applied

## Support and Maintenance

- Monitor logs regularly
- Test backups monthly
- Update dependencies quarterly
- Review security settings annually
- Document any custom configurations