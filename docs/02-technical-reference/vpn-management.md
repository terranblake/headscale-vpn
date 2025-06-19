# VPN Management Guide

Complete guide for managing users, devices, and VPN connectivity in the Family Network Platform.

## Table of Contents

- [User Management](#user-management)
- [Device Management](#device-management)
- [ACL Configuration](#acl-configuration)
- [Network Troubleshooting](#network-troubleshooting)
- [Advanced Operations](#advanced-operations)

## User Management

### Creating Family Users

#### Using Make Commands (Recommended)
```bash
# Create a new family user
make create-user USER=alice

# Generate setup configuration for user
make generate-setup-config USER=alice

# List all users
make list-users
```

#### Manual User Creation
```bash
# Enter headscale container
docker exec -it headscale headscale users create alice

# Verify user creation
docker exec -it headscale headscale users list
```

### User Operations

#### Generate Pre-authentication Keys
```bash
# Generate reusable key for user (recommended for families)
docker exec -it headscale headscale preauthkeys create \
  --user alice \
  --reusable \
  --expiration 24h

# Generate single-use key
docker exec -it headscale headscale preauthkeys create \
  --user alice \
  --expiration 1h
```

#### List User Pre-auth Keys
```bash
docker exec -it headscale headscale preauthkeys list --user alice
```

#### Expire Pre-auth Keys
```bash
docker exec -it headscale headscale preauthkeys expire --user alice --key <key-id>
```

### User Deletion
```bash
# Delete user (removes all associated devices)
docker exec -it headscale headscale users delete alice

# Confirm deletion
docker exec -it headscale headscale users list
```

## Device Management

### Listing Devices

#### All Devices
```bash
# List all registered devices
docker exec -it headscale headscale nodes list

# List devices with detailed information
docker exec -it headscale headscale nodes list --output json
```

#### User-Specific Devices
```bash
# List devices for specific user
docker exec -it headscale headscale nodes list --user alice
```

### Device Registration

#### Automatic Registration (Recommended for Families)
Family members use pre-authentication keys for seamless setup:

1. **Generate reusable key:**
   ```bash
   docker exec -it headscale headscale preauthkeys create \
     --user alice \
     --reusable \
     --expiration 168h  # 1 week
   ```

2. **Family member connects:**
   ```bash
   # On family member's device
   tailscale up --login-server https://headscale.family.local --authkey <preauth-key>
   ```

#### Manual Device Approval
```bash
# List pending registrations
docker exec -it headscale headscale nodes list --user alice

# Approve pending device
docker exec -it headscale headscale nodes register --user alice --key <machine-key>
```

### Device Operations

#### Rename Devices
```bash
# Rename device for easier identification
docker exec -it headscale headscale nodes rename <node-id> "Alice-iPhone"
```

#### Move Device to Different User
```bash
# Move device between users
docker exec -it headscale headscale nodes move <node-id> bob
```

#### Delete Devices
```bash
# Delete specific device
docker exec -it headscale headscale nodes delete <node-id>

# Force delete unresponsive device
docker exec -it headscale headscale nodes delete <node-id> --force
```

#### Expire Device Keys
```bash
# Expire device key (forces re-authentication)
docker exec -it headscale headscale nodes expire <node-id>
```

## ACL Configuration

### Understanding ACL Structure

The ACL (Access Control List) defines network access policies. Located at `config/headscale/acl.yaml`.

#### Basic ACL Structure
```yaml
acls:
  - action: accept
    src: ["group:family"]
    dst: ["*:*"]

groups:
  group:family:
    - alice
    - bob
    - charlie

hosts:
  home-server: 192.168.1.100
  media-server: 192.168.1.101
```

### Common ACL Patterns

#### Family Full Access
```yaml
# Allow all family members access to everything
acls:
  - action: accept
    src: ["group:family"]
    dst: ["*:*"]
```

#### Service-Specific Access
```yaml
# Restrict access to specific services
acls:
  - action: accept
    src: ["group:family"]
    dst: ["home-server:80,443", "media-server:8096"]
  
  - action: accept
    src: ["group:parents"]
    dst: ["admin-panel:*"]
```

#### Device-Specific Rules
```yaml
# Allow specific devices special access
acls:
  - action: accept
    src: ["alice-laptop"]
    dst: ["admin-services:*"]
```

### Applying ACL Changes

#### Update ACL Configuration
```bash
# Edit ACL file
nano config/headscale/acl.yaml

# Restart headscale to apply changes
docker restart headscale

# Verify ACL syntax
docker exec -it headscale headscale policy check
```

#### Test ACL Rules
```bash
# Test connectivity between nodes
docker exec -it headscale headscale policy test \
  --src alice-phone \
  --dst home-server:80
```

## Network Troubleshooting

### Connectivity Issues

#### Check Node Status
```bash
# Verify node is online
docker exec -it headscale headscale nodes list

# Check specific node details
docker exec -it headscale headscale nodes show <node-id>
```

#### Verify Network Routes
```bash
# List all routes
docker exec -it headscale headscale routes list

# Enable/disable routes
docker exec -it headscale headscale routes enable <route-id>
docker exec -it headscale headscale routes disable <route-id>
```

#### DNS Resolution Issues
```bash
# Check DNS configuration
docker exec -it headscale headscale dns list

# Verify MagicDNS settings in headscale config
grep -A 5 "dns:" config/headscale/config.yaml
```

### Performance Troubleshooting

#### Check Headscale Logs
```bash
# View recent logs
docker logs headscale --tail 100

# Follow logs in real-time
docker logs headscale --follow

# Filter for specific user
docker logs headscale 2>&1 | grep alice
```

#### Monitor Resource Usage
```bash
# Check container resource usage
docker stats headscale

# Check system resources
htop
df -h
```

### Common Issues and Solutions

#### Issue: Device Won't Connect
**Symptoms:** Device shows "connecting" but never establishes connection

**Solutions:**
1. Check pre-auth key validity:
   ```bash
   docker exec -it headscale headscale preauthkeys list --user alice
   ```

2. Verify ACL allows connection:
   ```bash
   docker exec -it headscale headscale policy check
   ```

3. Check firewall settings:
   ```bash
   sudo ufw status
   ```

#### Issue: Can't Access Services
**Symptoms:** VPN connected but services unreachable

**Solutions:**
1. Test ACL rules:
   ```bash
   docker exec -it headscale headscale policy test \
     --src alice-phone --dst home-server:80
   ```

2. Verify service is running:
   ```bash
   docker ps | grep streamyfin
   curl -I http://localhost:8096
   ```

3. Check DNS resolution:
   ```bash
   nslookup streamyfin.family.local
   ```

#### Issue: Slow Performance
**Symptoms:** Services load slowly through VPN

**Solutions:**
1. Check DERP server connectivity:
   ```bash
   docker exec -it headscale headscale debug derp
   ```

2. Monitor bandwidth usage:
   ```bash
   iftop -i tailscale0
   ```

3. Optimize headscale configuration:
   ```yaml
   # In config/headscale/config.yaml
   derp:
     server:
       enabled: true
       region_id: 999
       stun_listen_addr: "0.0.0.0:3478"
   ```

## Advanced Operations

### Backup and Restore

#### Backup VPN Configuration
```bash
# Use built-in backup script
./scripts/backup.sh

# Manual backup
docker exec headscale headscale export > backup/headscale-$(date +%Y%m%d).json
```

#### Restore from Backup
```bash
# Use built-in restore script
./scripts/restore.sh backup/headscale-20240619.json

# Manual restore
docker exec -i headscale headscale import < backup/headscale-20240619.json
```

### Monitoring and Metrics

#### Enable Metrics Collection
```yaml
# In config/headscale/config.yaml
metrics_listen_addr: 0.0.0.0:9090
```

#### View Metrics
```bash
# Access Prometheus metrics
curl http://localhost:9090/metrics

# View in Grafana dashboard
# Navigate to http://localhost:3000
```

### Security Operations

#### Rotate Server Keys
```bash
# Generate new server key
docker exec -it headscale headscale generate private-key

# Update configuration with new key
# Restart headscale service
```

#### Audit Access Logs
```bash
# View access patterns
docker logs headscale 2>&1 | grep "node.*connected"

# Generate access report
./scripts/generate-access-report.sh
```

### Bulk Operations

#### Mass User Creation
```bash
# Create multiple users from list
for user in alice bob charlie diana; do
  docker exec -it headscale headscale users create $user
  docker exec -it headscale headscale preauthkeys create \
    --user $user --reusable --expiration 168h
done
```

#### Device Cleanup
```bash
# Remove offline devices older than 30 days
docker exec -it headscale headscale nodes list --output json | \
  jq -r '.[] | select(.lastSeen < (now - 2592000)) | .id' | \
  xargs -I {} docker exec -it headscale headscale nodes delete {}
```

## Best Practices

### Family Network Management

1. **Use Descriptive Names:**
   ```bash
   # Good: Alice-iPhone, Bob-Laptop, Family-AppleTV
   # Bad: node-1, device-abc123
   ```

2. **Regular Key Rotation:**
   ```bash
   # Rotate pre-auth keys monthly
   # Set reasonable expiration times (1 week for setup)
   ```

3. **Monitor Usage:**
   ```bash
   # Regular health checks
   make health-check
   
   # Review logs weekly
   docker logs headscale --since 7d
   ```

### Security Best Practices

1. **Principle of Least Privilege:**
   - Grant minimum necessary access in ACLs
   - Use groups instead of individual user rules
   - Regular ACL reviews

2. **Key Management:**
   - Use reusable keys for families (convenience)
   - Set appropriate expiration times
   - Rotate keys regularly

3. **Monitoring:**
   - Enable audit logging
   - Monitor for unusual connection patterns
   - Set up alerts for failed connections

### Troubleshooting Workflow

1. **Identify Scope:**
   - Single device or multiple devices?
   - Specific service or all services?
   - Recent change or ongoing issue?

2. **Check Basics:**
   - Device online status
   - ACL rules
   - Service availability

3. **Gather Information:**
   - Headscale logs
   - Device logs (if accessible)
   - Network connectivity tests

4. **Apply Solutions:**
   - Start with least disruptive fixes
   - Test after each change
   - Document resolution for future reference

## Quick Reference Commands

```bash
# User Management
make create-user USER=name
make list-users
docker exec -it headscale headscale users delete name

# Device Management  
docker exec -it headscale headscale nodes list
docker exec -it headscale headscale nodes delete <id>
docker exec -it headscale headscale nodes rename <id> "new-name"

# Pre-auth Keys
docker exec -it headscale headscale preauthkeys create --user name --reusable
docker exec -it headscale headscale preauthkeys list --user name

# ACL Management
docker exec -it headscale headscale policy check
docker exec -it headscale headscale policy test --src node1 --dst node2:port

# Troubleshooting
docker logs headscale --tail 100
make health-check
docker exec -it headscale headscale debug derp
```

---

This guide provides comprehensive VPN management procedures for the Family Network Platform. For additional support, refer to the [Quick Reference](quick-reference.md) or [Troubleshooting Guide](troubleshooting.md).