# Production Deployment Guide
## Complete Setup for Family Network Platform

### 🎯 Deployment Overview

This guide covers the complete deployment of the headscale-vpn family network platform, from initial server setup to family member onboarding.

---

## 📋 Prerequisites

### Hardware Requirements
```
Minimum Server Specs:
├── CPU: 4 cores (Intel i5-8400 or AMD Ryzen 5 2600)
├── RAM: 8GB (16GB recommended for media transcoding)
├── Storage: 500GB SSD (2TB+ recommended for media)
├── Network: Gigabit Ethernet
└── Internet: 100+ Mbps upload bandwidth

Recommended Setup:
├── Intel NUC or similar mini PC
├── Synology/QNAP NAS for storage
├── Unifi or similar managed networking
└── UPS for power protection
```

### Network Requirements
```
Home Network:
├── Static IP or DDNS for external access
├── Port forwarding capability
├── IPv4 connectivity (IPv6 optional)
└── Reliable internet connection

Domain Requirements:
├── Owned domain (e.g., terr.ac) OR
├── Free subdomain (e.g., duckdns.org)
└── DNS management access
```

### Software Prerequisites
```
Host Operating System:
├── Ubuntu 22.04 LTS (recommended)
├── Docker Engine 24.0+
├── Docker Compose v2.20+
└── Git for repository management
```

---

## 🚀 Initial Server Setup

### Step 1: Prepare Host System
```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install required packages
sudo apt install -y curl wget git ufw fail2ban

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER

# Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Logout and login to apply docker group membership
```

### Step 2: Configure Firewall
```bash
# Configure UFW firewall
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw allow 80/tcp    # HTTP
sudo ufw allow 443/tcp   # HTTPS
sudo ufw allow 8080/tcp  # Headscale
sudo ufw enable
```

### Step 3: Clone and Configure Repository
```bash
# Clone repository
git clone https://github.com/terranblake/headscale-vpn.git
cd headscale-vpn

# Copy configuration templates
cp config/headscale.yaml.example config/headscale.yaml
cp .env.example .env

# Generate secure passwords
openssl rand -base64 32  # Use for database passwords
openssl rand -hex 16     # Use for API keys
```

---

## ⚙️ Core Configuration

### Step 1: Configure Environment Variables
```bash
# Edit .env file
nano .env
```

```env
# Domain Configuration
DOMAIN=family.local
HEADSCALE_DOMAIN=vpn.yourdomain.com

# Database Configuration
POSTGRES_PASSWORD=your_secure_password_here
POSTGRES_DB=headscale

# SSL Configuration
ACME_EMAIL=your-email@example.com

# Service Configuration
STREAMYFIN_DATA_PATH=/path/to/media/storage
PHOTOS_DATA_PATH=/path/to/photos/storage

# Monitoring
GRAFANA_ADMIN_PASSWORD=your_grafana_password
```

### Step 2: Configure Headscale
```bash
# Edit headscale configuration
nano config/headscale.yaml
```

```yaml
# Key sections to configure:
server_url: https://vpn.yourdomain.com:8080
listen_addr: 0.0.0.0:8080
metrics_listen_addr: 0.0.0.0:9090

# Database
db_type: postgres
db_host: postgres
db_port: 5432
db_name: headscale
db_user: headscale
db_pass: your_secure_password_here

# DNS Configuration
dns_config:
  magic_dns: true
  base_domain: family.local
  nameservers:
    - 1.1.1.1
    - 8.8.8.8
  extra_records:
    - name: streamyfin.family.local
      type: A
      value: "192.168.1.100"
    - name: photos.family.local
      type: A
      value: "192.168.1.101"

# OIDC (optional)
oidc:
  only_start_if_oidc_is_available: false
```

### Step 3: Configure Services
```bash
# Configure Streamyfin
mkdir -p data/streamyfin/{config,cache,media}

# Configure photo storage
mkdir -p data/photos

# Set proper permissions
sudo chown -R 1000:1000 data/
```

---

## 🐳 Docker Deployment

### Step 1: Deploy Core Services
```bash
# Start core infrastructure
docker-compose up -d postgres headscale traefik

# Wait for services to initialize
sleep 30

# Check service status
docker-compose ps
```

### Step 2: Initialize Headscale
```bash
# Create initial admin user
docker exec headscale headscale users create admin

# Generate API key for management
docker exec headscale headscale apikeys create --expiration 90d

# Verify headscale is running
curl -I http://localhost:8080/health
```

### Step 3: Deploy Family Services
```bash
# Start all services
docker-compose up -d

# Verify all services are running
docker-compose ps

# Check logs for any errors
docker-compose logs -f
```

---

## 🌐 DNS and SSL Setup

### Step 1: Configure External DNS
```bash
# Add DNS records for your domain:
# A record: vpn.yourdomain.com → your_public_ip
# A record: *.family.local → your_public_ip (if supported)
# CNAME: streamyfin.yourdomain.com → vpn.yourdomain.com
```

### Step 2: Configure Port Forwarding
```bash
# Router port forwarding rules:
# External 80 → Internal server_ip:80
# External 443 → Internal server_ip:443
# External 8080 → Internal server_ip:8080
```

### Step 3: Verify SSL Certificates
```bash
# Check certificate generation
docker-compose logs traefik | grep -i certificate

# Test HTTPS access
curl -I https://vpn.yourdomain.com
curl -I https://streamyfin.yourdomain.com
```

---

## 👥 Family Member Setup

### Step 1: Create Family Users
```bash
# Create users for each family member
docker exec headscale headscale users create alice
docker exec headscale headscale users create bob
docker exec headscale headscale users create charlie

# List all users
docker exec headscale headscale users list
```

### Step 2: Generate Pre-Auth Keys
```bash
# Generate pre-auth keys for each user
docker exec headscale headscale preauthkeys create --user alice --expiration 24h
docker exec headscale headscale preauthkeys create --user bob --expiration 24h
docker exec headscale headscale preauthkeys create --user charlie --expiration 24h
```

### Step 3: Create iOS Configuration Profiles
```bash
# Generate iOS profiles for each family member
./scripts/setup-smart-tailscale.sh

# This creates .mobileconfig files for each user
# Send these files to family members via secure method
```

---

## 📊 Monitoring Setup

### Step 1: Configure Prometheus
```bash
# Prometheus configuration is included in docker-compose.yml
# Verify metrics collection
curl http://localhost:9090/metrics
```

### Step 2: Setup Grafana Dashboards
```bash
# Access Grafana
open http://localhost:3000

# Login with admin credentials from .env
# Import pre-configured dashboards from config/grafana/
```

### Step 3: Configure Alerting
```bash
# Edit alerting rules
nano config/prometheus/alert.rules.yml

# Configure notification channels in Grafana
# Set up email/Slack notifications for critical alerts
```

---

## 🔒 Security Hardening

### Step 1: Enable Fail2Ban
```bash
# Configure fail2ban for SSH protection
sudo systemctl enable fail2ban
sudo systemctl start fail2ban

# Check fail2ban status
sudo fail2ban-client status
```

### Step 2: Configure Automatic Updates
```bash
# Enable unattended upgrades
sudo apt install unattended-upgrades
sudo dpkg-reconfigure -plow unattended-upgrades

# Configure automatic security updates
echo 'Unattended-Upgrade::Automatic-Reboot "false";' | sudo tee -a /etc/apt/apt.conf.d/50unattended-upgrades
```

### Step 3: Setup Backup Strategy
```bash
# Create backup script
cat > scripts/backup.sh << 'EOF'
#!/bin/bash
# Backup critical data and configurations

BACKUP_DIR="/backup/$(date +%Y%m%d)"
mkdir -p $BACKUP_DIR

# Backup configurations
tar -czf $BACKUP_DIR/config.tar.gz config/
tar -czf $BACKUP_DIR/data.tar.gz data/

# Backup database
docker exec postgres pg_dump -U headscale headscale > $BACKUP_DIR/database.sql

# Cleanup old backups (keep 30 days)
find /backup -type d -mtime +30 -exec rm -rf {} \;
EOF

chmod +x scripts/backup.sh

# Setup daily backup cron job
echo "0 2 * * * /path/to/headscale-vpn/scripts/backup.sh" | crontab -
```

---

## ✅ Deployment Verification

### Step 1: System Health Checks
```bash
# Check all services are running
docker-compose ps

# Verify headscale connectivity
curl -f http://localhost:8080/health

# Check DNS resolution
nslookup streamyfin.family.local localhost

# Verify SSL certificates
openssl s_client -connect vpn.yourdomain.com:443 -servername vpn.yourdomain.com
```

### Step 2: VPN Connectivity Test
```bash
# Test with a client device
# Install Tailscale on test device
# Use pre-auth key to connect
# Verify access to family.local services
```

### Step 3: Service Functionality Test
```bash
# Test Streamyfin access
curl -I http://streamyfin.family.local

# Test photo service
curl -I http://photos.family.local

# Verify AirPlay functionality with Apple TV
```

---

## 🔧 Post-Deployment Tasks

### Step 1: Documentation
```bash
# Document your specific configuration
# Update family setup guides with your domain names
# Create service-specific documentation
```

### Step 2: Family Onboarding
```bash
# Send iOS configuration profiles to family members
# Provide setup instructions
# Schedule support calls for initial setup
```

### Step 3: Monitoring and Maintenance
```bash
# Set up monitoring alerts
# Schedule regular backup verification
# Plan for periodic security updates
```

---

## 🚨 Troubleshooting Common Issues

### Headscale Won't Start
```bash
# Check logs
docker-compose logs headscale

# Common issues:
# - Database connection problems
# - Port conflicts
# - Configuration syntax errors
```

### SSL Certificate Issues
```bash
# Check Traefik logs
docker-compose logs traefik

# Verify DNS resolution
nslookup vpn.yourdomain.com

# Check Let's Encrypt rate limits
```

### VPN Connection Problems
```bash
# Check headscale status
docker exec headscale headscale nodes list

# Verify firewall rules
sudo ufw status

# Check network connectivity
ping vpn.yourdomain.com
```

### Service Discovery Issues
```bash
# Test DNS resolution
nslookup streamyfin.family.local

# Check Magic DNS configuration
docker exec headscale headscale dns status

# Verify service containers are running
docker-compose ps
```

This deployment guide provides a complete, production-ready setup for the family network platform. Follow each section carefully and verify functionality at each step.