# Security Procedures Guide

Comprehensive security procedures and best practices for the Family Network Platform.

## Table of Contents

- [Security Overview](#security-overview)
- [Initial Security Setup](#initial-security-setup)
- [Access Control Management](#access-control-management)
- [Certificate Management](#certificate-management)
- [Network Security](#network-security)
- [Monitoring and Auditing](#monitoring-and-auditing)
- [Incident Response](#incident-response)
- [Regular Security Maintenance](#regular-security-maintenance)

## Security Overview

### Security Architecture

The Family Network Platform implements multiple layers of security:

```
Security Layers:
┌─────────────────────────────────────────────────────────┐
│ Application Layer: Service-specific authentication     │
├─────────────────────────────────────────────────────────┤
│ Transport Layer: TLS/SSL encryption (Let's Encrypt)    │
├─────────────────────────────────────────────────────────┤
│ Network Layer: VPN encryption (WireGuard)              │
├─────────────────────────────────────────────────────────┤
│ Access Layer: ACL-based access control                 │
├─────────────────────────────────────────────────────────┤
│ Infrastructure Layer: Container isolation              │
└─────────────────────────────────────────────────────────┘
```

### Security Principles

1. **Zero Trust Architecture** - Verify every connection
2. **Principle of Least Privilege** - Minimum necessary access
3. **Defense in Depth** - Multiple security layers
4. **Regular Auditing** - Continuous security monitoring
5. **Family-First Security** - Balance security with usability

## Initial Security Setup

### System Hardening

#### Server Security Configuration
```bash
# Update system packages
sudo apt update && sudo apt upgrade -y

# Configure automatic security updates
sudo apt install unattended-upgrades -y
sudo dpkg-reconfigure -plow unattended-upgrades

# Configure firewall
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 41641/udp  # Headscale DERP
sudo ufw enable

# Disable root login and password authentication
sudo sed -i 's/#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sudo sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo systemctl restart sshd
```

#### Docker Security Configuration
```bash
# Create docker daemon configuration
sudo mkdir -p /etc/docker
cat > /etc/docker/daemon.json << 'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "live-restore": true,
  "userland-proxy": false,
  "no-new-privileges": true
}
EOF

sudo systemctl restart docker
```

### Initial Password Setup

#### Generate Secure Passwords
```bash
# Generate secure passwords for services
generate_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-25
}

# Store passwords securely
HEADSCALE_DB_PASSWORD=$(generate_password)
STREAMYFIN_PASSWORD=$(generate_password)
GRAFANA_PASSWORD=$(generate_password)

# Save to secure file (restrict permissions)
cat > .env.security << EOF
HEADSCALE_DB_PASSWORD=$HEADSCALE_DB_PASSWORD
STREAMYFIN_PASSWORD=$STREAMYFIN_PASSWORD
GRAFANA_PASSWORD=$GRAFANA_PASSWORD
EOF

chmod 600 .env.security
```

#### Configure Service Authentication
```bash
# Set Grafana admin password
docker exec -it grafana grafana-cli admin reset-admin-password "$GRAFANA_PASSWORD"

# Configure Streamyfin authentication
docker exec -it streamyfin /opt/streamyfin/bin/streamyfin-cli user create admin "$STREAMYFIN_PASSWORD"
```

### SSL/TLS Certificate Setup

#### Automatic Let's Encrypt Configuration
```bash
# Verify Traefik Let's Encrypt configuration
cat config/traefik/traefik.yml | grep -A 10 "certificatesResolvers"

# Test certificate generation
docker logs traefik 2>&1 | grep -i "certificate"

# Verify certificate installation
openssl s_client -connect streamyfin.family.local:443 -servername streamyfin.family.local < /dev/null 2>/dev/null | openssl x509 -text -noout | grep -A 2 "Validity"
```

## Access Control Management

### User Access Control

#### Family User Management
```bash
# Create family user with limited privileges
create_family_user() {
    local username="$1"
    local email="$2"
    
    # Create headscale user
    docker exec -it headscale headscale users create "$username"
    
    # Generate pre-auth key with expiration
    docker exec -it headscale headscale preauthkeys create \
        --user "$username" \
        --reusable \
        --expiration 168h  # 1 week
    
    echo "User $username created successfully"
}

# Example usage
create_family_user "alice" "alice@family.local"
create_family_user "bob" "bob@family.local"
```

#### ACL Security Configuration
```yaml
# config/headscale/acl.yaml - Secure ACL configuration
acls:
  # Family members can access family services only
  - action: accept
    src: ["group:family"]
    dst: ["group:family-services:80,443,8096,3000"]
  
  # Parents can access admin services
  - action: accept
    src: ["group:parents"]
    dst: ["group:admin-services:*"]
  
  # Deny all other traffic
  - action: deny
    src: ["*"]
    dst: ["*"]

groups:
  group:family:
    - alice
    - bob
    - charlie
    
  group:parents:
    - alice
    - bob
    
  group:family-services:
    - streamyfin.family.local
    - photos.family.local
    - docs.family.local
    
  group:admin-services:
    - grafana.family.local
    - prometheus.family.local
    - traefik.family.local

hosts:
  streamyfin.family.local: 192.168.1.100
  photos.family.local: 192.168.1.100
  docs.family.local: 192.168.1.100
  grafana.family.local: 192.168.1.100
```

### Service-Level Authentication

#### Traefik Authentication Middleware
```yaml
# config/traefik/dynamic/auth.yml
http:
  middlewares:
    admin-auth:
      basicAuth:
        users:
          - "admin:$2y$10$..."  # Generated with htpasswd
    
    family-auth:
      forwardAuth:
        address: "http://auth-service:8080/auth"
        authResponseHeaders:
          - "X-User"
          - "X-Groups"
    
    secure-headers:
      headers:
        customRequestHeaders:
          X-Forwarded-Proto: "https"
        customResponseHeaders:
          X-Content-Type-Options: "nosniff"
          X-Frame-Options: "SAMEORIGIN"
          X-XSS-Protection: "1; mode=block"
          Strict-Transport-Security: "max-age=31536000; includeSubDomains"
```

#### Generate Authentication Credentials
```bash
# Generate htpasswd credentials
generate_htpasswd() {
    local username="$1"
    local password="$2"
    
    echo "$password" | htpasswd -ni "$username"
}

# Create admin credentials
ADMIN_PASSWORD=$(generate_password)
ADMIN_HASH=$(generate_htpasswd "admin" "$ADMIN_PASSWORD")

echo "Admin credentials: admin / $ADMIN_PASSWORD"
echo "Hash for Traefik: $ADMIN_HASH"
```

## Certificate Management

### SSL Certificate Monitoring

#### Certificate Expiration Monitoring
```bash
#!/bin/bash
# scripts/check-certificates.sh

check_certificate() {
    local domain="$1"
    local days_warning="$2"
    
    # Get certificate expiration date
    expiry_date=$(openssl s_client -connect "$domain:443" -servername "$domain" < /dev/null 2>/dev/null | \
                  openssl x509 -noout -dates | grep notAfter | cut -d= -f2)
    
    # Convert to epoch time
    expiry_epoch=$(date -d "$expiry_date" +%s)
    current_epoch=$(date +%s)
    days_until_expiry=$(( (expiry_epoch - current_epoch) / 86400 ))
    
    if [ "$days_until_expiry" -lt "$days_warning" ]; then
        echo "WARNING: Certificate for $domain expires in $days_until_expiry days"
        return 1
    else
        echo "OK: Certificate for $domain expires in $days_until_expiry days"
        return 0
    fi
}

# Check all family services
domains=("streamyfin.family.local" "photos.family.local" "docs.family.local")
warning_days=30

for domain in "${domains[@]}"; do
    check_certificate "$domain" "$warning_days"
done
```

#### Certificate Renewal Automation
```bash
# Automatic certificate renewal check
cat > /etc/cron.daily/check-certificates << 'EOF'
#!/bin/bash
cd /path/to/headscale-vpn
./scripts/check-certificates.sh

# If certificates are expiring, restart Traefik to trigger renewal
if [ $? -ne 0 ]; then
    docker restart traefik
    sleep 60
    ./scripts/check-certificates.sh
fi
EOF

chmod +x /etc/cron.daily/check-certificates
```

### Certificate Backup and Recovery

#### Certificate Backup
```bash
# Backup Let's Encrypt certificates
backup_certificates() {
    local backup_dir="/backup/certificates/$(date +%Y%m%d)"
    mkdir -p "$backup_dir"
    
    # Copy Traefik certificate data
    docker cp traefik:/data/acme.json "$backup_dir/"
    
    # Backup certificate files
    cp -r /var/lib/docker/volumes/headscale-vpn_traefik-certificates/_data/* "$backup_dir/"
    
    # Create encrypted backup
    tar -czf "$backup_dir.tar.gz" -C "$backup_dir" .
    gpg --symmetric --cipher-algo AES256 "$backup_dir.tar.gz"
    rm "$backup_dir.tar.gz"
    
    echo "Certificates backed up to $backup_dir.tar.gz.gpg"
}
```

## Network Security

### Firewall Configuration

#### Advanced Firewall Rules
```bash
# Configure advanced UFW rules
configure_firewall() {
    # Reset firewall
    sudo ufw --force reset
    
    # Default policies
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    
    # SSH access (limit to specific IPs if possible)
    sudo ufw allow from 192.168.1.0/24 to any port 22
    
    # HTTP/HTTPS
    sudo ufw allow 80/tcp
    sudo ufw allow 443/tcp
    
    # Headscale DERP
    sudo ufw allow 41641/udp
    
    # Rate limiting for SSH
    sudo ufw limit ssh
    
    # Log denied connections
    sudo ufw logging on
    
    # Enable firewall
    sudo ufw enable
}
```

#### Network Segmentation
```bash
# Create isolated Docker networks
docker network create --driver bridge \
    --subnet=172.20.0.0/16 \
    --ip-range=172.20.240.0/20 \
    family-network-secure

# Configure network policies
cat > config/docker/network-policy.json << 'EOF'
{
  "networks": {
    "family-network": {
      "isolation": true,
      "allowed_services": ["headscale", "traefik", "streamyfin"]
    },
    "admin-network": {
      "isolation": true,
      "allowed_services": ["prometheus", "grafana"]
    }
  }
}
EOF
```

### VPN Security Configuration

#### Headscale Security Settings
```yaml
# config/headscale/config.yaml - Security configuration
server_url: https://headscale.family.local
listen_addr: 0.0.0.0:8080
metrics_listen_addr: 127.0.0.1:9090  # Restrict metrics to localhost

# Disable node sharing
node_update_check_interval: 10s
disable_check_updates: true

# Strict DERP configuration
derp:
  server:
    enabled: true
    region_id: 999
    region_code: "family"
    region_name: "Family Network"
    stun_listen_addr: "0.0.0.0:3478"
    private_key_path: /etc/headscale/derp_server_private.key
    
# Database encryption
database_encryption_key: "your-32-character-encryption-key-here"

# Log configuration
log_level: info
log_format: json
```

#### WireGuard Key Management
```bash
# Rotate WireGuard keys periodically
rotate_wireguard_keys() {
    echo "Rotating WireGuard keys..."
    
    # Generate new server private key
    wg genkey > /tmp/new_server_key
    
    # Update headscale configuration
    docker exec -it headscale headscale generate private-key > /tmp/new_headscale_key
    
    # Backup old keys
    mkdir -p /backup/keys/$(date +%Y%m%d)
    docker cp headscale:/etc/headscale/private.key "/backup/keys/$(date +%Y%m%d)/"
    
    # Apply new keys (requires service restart)
    docker cp /tmp/new_headscale_key headscale:/etc/headscale/private.key
    docker restart headscale
    
    # Clean up temporary files
    rm /tmp/new_server_key /tmp/new_headscale_key
    
    echo "WireGuard keys rotated successfully"
}
```

## Monitoring and Auditing

### Security Event Monitoring

#### Log Analysis for Security Events
```bash
#!/bin/bash
# scripts/security-audit.sh

# Check for failed authentication attempts
check_auth_failures() {
    echo "=== Authentication Failures ==="
    docker logs headscale --since 24h 2>&1 | grep -i "auth.*fail\|unauthorized\|forbidden"
    docker logs traefik --since 24h 2>&1 | grep -E "401|403"
}

# Check for suspicious network activity
check_network_activity() {
    echo "=== Suspicious Network Activity ==="
    # Check for unusual connection patterns
    docker logs headscale --since 24h 2>&1 | grep -E "connection.*refused\|timeout\|error"
    
    # Check firewall logs
    sudo grep "UFW BLOCK" /var/log/ufw.log | tail -20
}

# Check for privilege escalation attempts
check_privilege_escalation() {
    echo "=== Privilege Escalation Attempts ==="
    sudo grep -i "sudo\|su " /var/log/auth.log | tail -20
}

# Check container security
check_container_security() {
    echo "=== Container Security ==="
    # Check for containers running as root
    docker ps --format "table {{.Names}}\t{{.Image}}" | while read name image; do
        if [ "$name" != "NAMES" ]; then
            user=$(docker exec "$name" whoami 2>/dev/null || echo "unknown")
            echo "$name: $user"
        fi
    done
}

# Run all security checks
check_auth_failures
check_network_activity
check_privilege_escalation
check_container_security
```

#### Automated Security Alerts
```bash
# Create security monitoring script
cat > scripts/security-monitor.sh << 'EOF'
#!/bin/bash

ALERT_EMAIL="admin@family.local"
LOG_FILE="/var/log/family-security.log"

# Function to send alert
send_alert() {
    local subject="$1"
    local message="$2"
    
    echo "$(date): SECURITY ALERT - $subject" >> "$LOG_FILE"
    echo "$message" >> "$LOG_FILE"
    
    # Send email alert (configure mail server)
    echo "$message" | mail -s "Family Network Security Alert: $subject" "$ALERT_EMAIL"
}

# Monitor for brute force attacks
check_brute_force() {
    local failed_attempts=$(docker logs traefik --since 5m 2>&1 | grep -c "401\|403")
    
    if [ "$failed_attempts" -gt 10 ]; then
        send_alert "Potential Brute Force Attack" \
            "Detected $failed_attempts failed authentication attempts in the last 5 minutes"
    fi
}

# Monitor for unusual VPN activity
check_vpn_activity() {
    local new_connections=$(docker logs headscale --since 5m 2>&1 | grep -c "node.*connected")
    
    if [ "$new_connections" -gt 5 ]; then
        send_alert "Unusual VPN Activity" \
            "Detected $new_connections new VPN connections in the last 5 minutes"
    fi
}

# Run monitoring checks
check_brute_force
check_vpn_activity
EOF

chmod +x scripts/security-monitor.sh

# Add to crontab for regular monitoring
echo "*/5 * * * * /path/to/headscale-vpn/scripts/security-monitor.sh" | crontab -
```

### Access Logging and Auditing

#### Comprehensive Access Logging
```yaml
# config/traefik/traefik.yml - Enhanced logging
log:
  level: INFO
  format: json

accessLog:
  format: json
  fields:
    defaultMode: keep
    names:
      ClientUsername: drop
    headers:
      defaultMode: keep
      names:
        User-Agent: keep
        Authorization: drop
        Cookie: drop
```

#### Log Analysis Scripts
```bash
# Analyze access patterns
analyze_access_logs() {
    echo "=== Top IP Addresses ==="
    docker logs traefik --since 24h 2>&1 | \
        grep -oE '"ClientHost":"[^"]*"' | \
        sort | uniq -c | sort -nr | head -10
    
    echo "=== Most Accessed Services ==="
    docker logs traefik --since 24h 2>&1 | \
        grep -oE '"RequestHost":"[^"]*"' | \
        sort | uniq -c | sort -nr | head -10
    
    echo "=== Error Responses ==="
    docker logs traefik --since 24h 2>&1 | \
        grep -E '"DownstreamStatus":[45][0-9][0-9]' | \
        grep -oE '"DownstreamStatus":[0-9]*' | \
        sort | uniq -c | sort -nr
}
```

## Incident Response

### Security Incident Response Plan

#### Incident Classification
1. **Critical** - Active security breach, data compromise
2. **High** - Attempted breach, service disruption
3. **Medium** - Suspicious activity, policy violations
4. **Low** - Minor security events, informational

#### Response Procedures

##### Critical Incident Response
```bash
#!/bin/bash
# scripts/incident-response-critical.sh

echo "CRITICAL SECURITY INCIDENT RESPONSE"
echo "Timestamp: $(date)"

# 1. Isolate affected systems
isolate_systems() {
    echo "Isolating affected systems..."
    
    # Block all external traffic
    sudo ufw deny incoming
    
    # Stop non-essential services
    docker stop streamyfin photos docs
    
    # Keep only core VPN and monitoring
    docker ps --format "{{.Names}}" | grep -v -E "(headscale|traefik|prometheus|grafana)" | xargs docker stop
}

# 2. Preserve evidence
preserve_evidence() {
    local incident_dir="/incident/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$incident_dir"
    
    # Collect logs
    docker logs headscale > "$incident_dir/headscale.log"
    docker logs traefik > "$incident_dir/traefik.log"
    
    # Collect system information
    ps aux > "$incident_dir/processes.txt"
    netstat -tuln > "$incident_dir/network.txt"
    
    # Collect container information
    docker ps -a > "$incident_dir/containers.txt"
    docker images > "$incident_dir/images.txt"
    
    echo "Evidence preserved in $incident_dir"
}

# 3. Notify stakeholders
notify_stakeholders() {
    echo "Security incident detected at $(date)" | \
        mail -s "CRITICAL: Family Network Security Incident" admin@family.local
}

# Execute response
isolate_systems
preserve_evidence
notify_stakeholders

echo "Critical incident response completed"
```

##### Recovery Procedures
```bash
#!/bin/bash
# scripts/incident-recovery.sh

echo "SECURITY INCIDENT RECOVERY"

# 1. Verify system integrity
verify_integrity() {
    echo "Verifying system integrity..."
    
    # Check for unauthorized changes
    docker diff headscale
    docker diff traefik
    
    # Verify configuration files
    md5sum config/headscale/config.yaml
    md5sum config/traefik/traefik.yml
    
    # Check for rootkits
    sudo rkhunter --check --sk
}

# 2. Reset compromised credentials
reset_credentials() {
    echo "Resetting credentials..."
    
    # Generate new passwords
    NEW_ADMIN_PASSWORD=$(openssl rand -base64 32)
    
    # Update service passwords
    docker exec -it grafana grafana-cli admin reset-admin-password "$NEW_ADMIN_PASSWORD"
    
    # Rotate API keys
    docker exec -it headscale headscale apikeys expire --all
    
    echo "New admin password: $NEW_ADMIN_PASSWORD"
}

# 3. Restore services gradually
restore_services() {
    echo "Restoring services..."
    
    # Start core services first
    docker start headscale
    sleep 30
    
    # Verify core functionality
    if curl -f http://localhost:8080/health; then
        echo "Core services healthy, starting family services..."
        docker start streamyfin photos docs
    else
        echo "Core services unhealthy, manual intervention required"
        exit 1
    fi
}

# Execute recovery
verify_integrity
reset_credentials
restore_services

echo "Recovery completed"
```

## Regular Security Maintenance

### Weekly Security Tasks

#### Weekly Security Checklist
```bash
#!/bin/bash
# scripts/weekly-security-maintenance.sh

echo "=== Weekly Security Maintenance ==="
echo "Date: $(date)"

# 1. Update system packages
echo "Updating system packages..."
sudo apt update && sudo apt upgrade -y

# 2. Update Docker images
echo "Updating Docker images..."
docker-compose pull
docker-compose up -d

# 3. Check certificate expiration
echo "Checking certificate expiration..."
./scripts/check-certificates.sh

# 4. Rotate log files
echo "Rotating log files..."
docker logs headscale > "/backup/logs/headscale-$(date +%Y%m%d).log"
docker logs traefik > "/backup/logs/traefik-$(date +%Y%m%d).log"

# 5. Security audit
echo "Running security audit..."
./scripts/security-audit.sh > "/backup/security/audit-$(date +%Y%m%d).log"

# 6. Backup security configurations
echo "Backing up security configurations..."
tar -czf "/backup/security/config-$(date +%Y%m%d).tar.gz" config/

# 7. Test backup restoration
echo "Testing backup restoration..."
./scripts/test-backup.sh

echo "Weekly security maintenance completed"
```

### Monthly Security Tasks

#### Monthly Security Review
```bash
#!/bin/bash
# scripts/monthly-security-review.sh

echo "=== Monthly Security Review ==="

# 1. Review user access
echo "Reviewing user access..."
docker exec -it headscale headscale users list
docker exec -it headscale headscale nodes list

# 2. Review ACL configuration
echo "Reviewing ACL configuration..."
docker exec -it headscale headscale policy check

# 3. Analyze access patterns
echo "Analyzing access patterns..."
./scripts/analyze-access-logs.sh > "/reports/access-analysis-$(date +%Y%m).log"

# 4. Security vulnerability scan
echo "Running vulnerability scan..."
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
    aquasec/trivy image headscale:latest

# 5. Review firewall rules
echo "Reviewing firewall rules..."
sudo ufw status numbered

# 6. Update security documentation
echo "Security review completed. Update documentation as needed."
```

### Automated Security Updates

#### Configure Automatic Updates
```bash
# Configure unattended upgrades
cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};

Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
EOF

# Configure automatic Docker image updates
cat > scripts/auto-update-docker.sh << 'EOF'
#!/bin/bash
cd /path/to/headscale-vpn

# Pull latest images
docker-compose pull

# Update services one by one to minimize downtime
services=("headscale" "traefik" "streamyfin")
for service in "${services[@]}"; do
    echo "Updating $service..."
    docker-compose up -d "$service"
    sleep 30
    
    # Verify service health
    if ! docker ps | grep -q "$service"; then
        echo "ERROR: $service failed to start"
        exit 1
    fi
done

echo "Docker images updated successfully"
EOF

chmod +x scripts/auto-update-docker.sh

# Schedule weekly Docker updates
echo "0 2 * * 0 /path/to/headscale-vpn/scripts/auto-update-docker.sh" | crontab -
```

## Quick Reference

### Emergency Security Commands

```bash
# Immediate threat response
sudo ufw deny incoming                    # Block all incoming traffic
docker stop $(docker ps -q)             # Stop all containers
docker network disconnect family-network <container>  # Isolate container

# Password reset
docker exec -it grafana grafana-cli admin reset-admin-password <new-password>
docker exec -it headscale headscale apikeys expire --all

# Certificate issues
docker restart traefik                   # Force certificate renewal
openssl s_client -connect domain:443 -servername domain  # Check certificate

# Log analysis
docker logs traefik 2>&1 | grep -E "401|403|500"  # Check for errors
docker logs headscale 2>&1 | grep -i error       # Check VPN errors
```

### Security Monitoring Commands

```bash
# Real-time monitoring
docker logs traefik --follow | grep -E "401|403"  # Monitor auth failures
sudo tail -f /var/log/ufw.log                     # Monitor firewall blocks
docker stats                                       # Monitor resource usage

# Security audits
./scripts/security-audit.sh              # Run security audit
./scripts/check-certificates.sh          # Check certificate status
sudo rkhunter --check                    # Check for rootkits
```

---

This security procedures guide provides comprehensive protection for the Family Network Platform. Regular implementation of these procedures ensures a secure environment for family access to home services while maintaining usability and convenience.