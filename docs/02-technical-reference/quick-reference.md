# Quick Reference Guide
## Essential Commands and Procedures

### 🚀 Daily Operations

#### Service Management
```bash
# Check all services status
make status
docker-compose ps

# View service logs
make logs
docker-compose logs -f headscale

# Restart specific service
docker-compose restart headscale
docker-compose restart traefik

# Restart all services
make restart
```

#### Family User Management
```bash
# Create new family user
make create-user USER=alice
docker exec headscale headscale users create alice

# List all users
make list-users
docker exec headscale headscale users list

# Generate pre-auth key for user
docker exec headscale headscale preauthkeys create --user alice --expiration 24h

# List all connected devices
make list-devices
docker exec headscale headscale nodes list
```

#### Service Addition
```bash
# Add new service to DNS
echo "  - name: newservice.family.local" >> config/headscale.yaml
echo "    type: A" >> config/headscale.yaml
echo "    value: \"192.168.1.105\"" >> config/headscale.yaml

# Apply DNS changes
docker-compose restart headscale

# Verify DNS resolution
nslookup newservice.family.local
```

---

### 🔧 Monitoring Commands

#### System Health
```bash
# Check service health
curl -f http://localhost:8080/health  # Headscale
curl -f http://localhost:8080/api/v1/node  # API status

# Check SSL certificates
openssl s_client -connect vpn.yourdomain.com:443 -servername vpn.yourdomain.com

# Monitor resource usage
docker stats
htop
```

#### VPN Status
```bash
# Check connected nodes
docker exec headscale headscale nodes list

# View node details
docker exec headscale headscale nodes show NODE_ID

# Check routes
docker exec headscale headscale routes list

# View ACL status
docker exec headscale headscale acl check
```

#### Network Diagnostics
```bash
# Test DNS resolution
nslookup streamyfin.family.local
dig @localhost streamyfin.family.local

# Check port connectivity
nc -zv vpn.yourdomain.com 8080
telnet vpn.yourdomain.com 443

# Monitor network traffic
netstat -tulpn | grep :8080
ss -tulpn | grep :443
```

---

### 📊 Monitoring and Metrics

#### Prometheus Queries
```promql
# Connected devices
headscale_nodes_total

# Service uptime
up{job="headscale"}

# HTTP request rate
rate(http_requests_total[5m])

# Memory usage
process_resident_memory_bytes{job="headscale"}
```

#### Grafana Dashboards
```bash
# Access Grafana
open http://localhost:3000

# Default credentials
Username: admin
Password: (from .env file)

# Import dashboard
# Use dashboard ID: 1860 (Node Exporter Full)
```

#### Log Analysis
```bash
# View recent logs
docker-compose logs --tail=100 headscale

# Follow logs in real-time
docker-compose logs -f

# Search logs for errors
docker-compose logs headscale | grep -i error

# Export logs for analysis
docker-compose logs --since="1h" > /tmp/headscale-logs.txt
```

---

### 🔒 Security Operations

#### Certificate Management
```bash
# Check certificate expiry
openssl x509 -in /path/to/cert.pem -text -noout | grep "Not After"

# Force certificate renewal
docker-compose exec traefik traefik --certificatesresolvers.letsencrypt.acme.caserver=https://acme-v02.api.letsencrypt.org/directory

# View certificate details
docker-compose logs traefik | grep -i certificate
```

#### Access Control
```bash
# Update ACL configuration
nano config/acl.json
docker exec headscale headscale acl load /etc/headscale/acl.json

# Check ACL syntax
docker exec headscale headscale acl check

# View current ACL
docker exec headscale headscale acl show
```

#### Backup Operations
```bash
# Manual backup
./scripts/backup.sh

# Verify backup
ls -la /backup/$(date +%Y%m%d)/

# Restore from backup
./scripts/restore.sh /backup/20231201/
```

---

### 🚨 Troubleshooting Commands

#### Common Issues
```bash
# Headscale won't start
docker-compose logs headscale
docker exec headscale headscale version

# Database connection issues
docker-compose logs postgres
docker exec postgres psql -U headscale -d headscale -c "\l"

# DNS resolution problems
nslookup streamyfin.family.local
systemctl status systemd-resolved
```

#### Network Connectivity
```bash
# Test external connectivity
ping 8.8.8.8
curl -I https://google.com

# Check firewall rules
sudo ufw status
iptables -L

# Verify port forwarding
nc -zv external_ip 8080
nc -zv external_ip 443
```

#### Service Recovery
```bash
# Restart failed services
docker-compose restart
systemctl restart docker

# Clear Docker cache
docker system prune -f
docker volume prune -f

# Reset to known good state
git checkout HEAD -- config/
docker-compose down && docker-compose up -d
```

---

### 📱 Client Support Commands

#### Generate Setup Materials
```bash
# Create user and setup config
make create-user USER=newuser
make generate-setup-config USER=newuser

# Generate pre-auth key
docker exec headscale headscale preauthkeys create --user newuser --expiration 24h

# Create mobile config profile
./scripts/generate-mobile-config.sh newuser
```

#### Troubleshoot Client Issues
```bash
# Check if client is connected
docker exec headscale headscale nodes list | grep client-name

# View client details
docker exec headscale headscale nodes show CLIENT_ID

# Force client reconnection
docker exec headscale headscale nodes expire CLIENT_ID
```

#### Test Client Connectivity
```bash
# Test from server to client
ping 100.64.0.10  # Client's Tailscale IP

# Test service access
curl -I http://streamyfin.family.local

# Check DNS from client perspective
nslookup streamyfin.family.local 100.64.0.1
```

---

### 🔄 Maintenance Procedures

#### Regular Maintenance
```bash
# Weekly tasks
docker system prune -f
./scripts/backup.sh
docker-compose pull && docker-compose up -d

# Monthly tasks
sudo apt update && sudo apt upgrade -y
docker exec headscale headscale nodes expire --all-inactive

# Quarterly tasks
./scripts/security-audit.sh
./scripts/performance-review.sh
```

#### Updates and Upgrades
```bash
# Update Headscale
docker-compose pull headscale
docker-compose up -d headscale

# Update all services
docker-compose pull
docker-compose up -d

# Update host system
sudo apt update && sudo apt upgrade -y
sudo reboot
```

#### Performance Optimization
```bash
# Check resource usage
docker stats
df -h
free -h

# Optimize database
docker exec postgres vacuumdb -U headscale -d headscale

# Clean up old data
docker exec headscale headscale nodes expire --older-than=30d
```

---

### 📋 Emergency Procedures

#### Service Down
```bash
# Quick diagnosis
make status
docker-compose ps
curl -f http://localhost:8080/health

# Emergency restart
docker-compose down
docker-compose up -d

# Check logs for errors
docker-compose logs --tail=50
```

#### Data Recovery
```bash
# Restore from backup
./scripts/restore.sh /backup/latest/

# Rebuild from configuration
docker-compose down -v
docker-compose up -d
./scripts/restore-config.sh
```

#### Network Issues
```bash
# Reset networking
docker network prune -f
systemctl restart docker
docker-compose up -d

# Check external connectivity
ping 8.8.8.8
curl -I https://google.com
```

---

### 📞 Support Information

#### Log Collection for Support
```bash
# Collect all relevant logs
mkdir -p /tmp/support-logs
docker-compose logs > /tmp/support-logs/docker-compose.log
journalctl -u docker > /tmp/support-logs/docker.log
dmesg > /tmp/support-logs/dmesg.log
tar -czf support-logs-$(date +%Y%m%d).tar.gz /tmp/support-logs/
```

#### System Information
```bash
# Gather system info
uname -a
docker version
docker-compose version
cat /etc/os-release
free -h
df -h
```

#### Configuration Backup
```bash
# Backup current configuration
tar -czf config-backup-$(date +%Y%m%d).tar.gz config/ .env docker-compose.yml
```

This quick reference provides immediate access to the most commonly needed commands and procedures for managing the family network platform.