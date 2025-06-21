# TLS Debugging and Troubleshooting Guide

This guide provides comprehensive tools and procedures for diagnosing and fixing TLS certificate issues with Traefik and Let's Encrypt in your Headscale VPN deployment.

## Quick Start

If you're experiencing TLS certificate issues, start here:

```bash
# 1. Run the comprehensive debug script
sudo ./scripts/debug-tls.sh

# 2. If issues are found, try the automatic fix script
sudo ./scripts/fix-tls-issues.sh --dry-run  # See what would be fixed
sudo ./scripts/fix-tls-issues.sh            # Apply the fixes

# 3. If problems persist, force certificate renewal
sudo ./scripts/renew-certificates.sh
```

## Available Scripts

### 1. `debug-tls.sh` - Comprehensive Diagnostic Tool

This script performs a deep analysis of your TLS configuration and identifies issues.

**Features:**
- Environment validation
- DNS resolution testing
- Network connectivity checks
- Traefik configuration analysis
- ACME storage inspection
- Ingress configuration validation
- Certificate testing
- Kubernetes secrets analysis
- Traefik dashboard access
- Detailed recommendations

**Usage:**
```bash
sudo ./scripts/debug-tls.sh
```

**Output:**
- Console output with color-coded status messages
- Detailed debug report saved to `/tmp/tls-debug-YYYYMMDD-HHMMSS.log`

### 2. `fix-tls-issues.sh` - Automatic Issue Resolution

This script automatically fixes common TLS certificate issues.

**Features:**
- Removes conflicting TLS secrets from ingress
- Ensures proper ACME configuration
- Cleans up old certificates
- Updates Traefik Helm configuration
- Restarts services when needed
- Verification of applied fixes

**Usage:**
```bash
# Dry run (see what would be changed)
sudo ./scripts/fix-tls-issues.sh --dry-run

# Apply fixes
sudo ./scripts/fix-tls-issues.sh

# Force certificate renewal
sudo ./scripts/fix-tls-issues.sh --force-renewal
```

**Options:**
- `--dry-run`: Show what would be done without making changes
- `--force-renewal`: Force certificate renewal even if not needed
- `--help`: Show help message

### 3. `renew-certificates.sh` - Force Certificate Renewal

This script forces renewal of Let's Encrypt certificates by clearing ACME storage.

**Usage:**
```bash
sudo ./scripts/renew-certificates.sh
```

**What it does:**
- Safely shuts down Traefik
- Deletes ACME storage
- Recreates storage
- Restarts Traefik
- Triggers new certificate requests

### 4. `check-tls.sh` - Basic Health Check

A simpler script for basic TLS health checking.

**Usage:**
```bash
sudo ./scripts/check-tls.sh
```

## Common Issues and Solutions

### Issue 1: Self-Signed Certificate Instead of Let's Encrypt

**Symptoms:**
- Browser shows "Not secure" or certificate warnings
- Certificate issuer is not "Let's Encrypt Authority"

**Diagnosis:**
```bash
sudo ./scripts/debug-tls.sh
# Look for: "Certificate Type: NOT Let's Encrypt (ISSUE)"
```

**Solution:**
```bash
sudo ./scripts/fix-tls-issues.sh
```

**Root Causes:**
- Conflicting `secretName` in ingress TLS configuration
- Missing or incorrect cert resolver annotation
- ACME storage issues

### Issue 2: DNS Resolution Failures

**Symptoms:**
- ACME HTTP-01 challenge fails
- Let's Encrypt cannot reach your domain

**Diagnosis:**
```bash
sudo ./scripts/debug-tls.sh
# Look for: "DNS resolution failed with all methods"
```

**Solution:**
1. Ensure your domain points to your server's public IP
2. Check DNS propagation: `dig headscale.yourdomain.com`
3. Wait for DNS propagation (can take up to 48 hours)

### Issue 3: Port Accessibility Issues

**Symptoms:**
- ACME challenges fail
- Cannot reach website on ports 80/443

**Diagnosis:**
```bash
sudo ./scripts/debug-tls.sh
# Look for: "HTTP (80): NOT accessible" or "HTTPS (443): NOT accessible"
```

**Solution:**
1. Check firewall settings
2. Ensure ports 80 and 443 are open to the internet
3. Verify no other services are using these ports

### Issue 4: Traefik Configuration Problems

**Symptoms:**
- Traefik not starting
- ACME storage issues
- Configuration errors

**Diagnosis:**
```bash
sudo ./scripts/debug-tls.sh
# Check Traefik logs and configuration sections
```

**Solution:**
```bash
sudo ./scripts/fix-tls-issues.sh
# Or manually restart Traefik:
k3s kubectl rollout restart deployment -n traefik traefik
```

### Issue 5: Rate Limiting

**Symptoms:**
- Certificate requests fail
- "too many requests" errors in logs

**Diagnosis:**
```bash
k3s kubectl logs -n traefik -l app.kubernetes.io/name=traefik | grep -i "rate\|limit"
```

**Solution:**
1. Wait before retrying (Let's Encrypt limits: 5 failures per hour)
2. Use staging environment for testing
3. Check for duplicate requests

## Detailed Troubleshooting Workflow

### Step 1: Initial Assessment
```bash
# Run comprehensive debug
sudo ./scripts/debug-tls.sh

# Check the generated report
cat /tmp/tls-debug-*.log
```

### Step 2: Identify Issues
Look for these critical indicators in the debug output:
- 🔴 CRITICAL issues (must be fixed)
- 🟡 WARNING issues (should be addressed)
- DNS resolution failures
- Port accessibility problems
- Configuration conflicts

### Step 3: Apply Automatic Fixes
```bash
# See what would be fixed
sudo ./scripts/fix-tls-issues.sh --dry-run

# Apply fixes
sudo ./scripts/fix-tls-issues.sh
```

### Step 4: Manual Verification
```bash
# Check certificate
openssl s_client -connect headscale.yourdomain.com:443 -servername headscale.yourdomain.com < /dev/null | openssl x509 -noout -issuer -subject -dates

# Monitor Traefik logs
k3s kubectl logs -f -n traefik -l app.kubernetes.io/name=traefik
```

### Step 5: Force Renewal if Needed
```bash
# If automatic fixes don't work
sudo ./scripts/renew-certificates.sh
```

## Advanced Debugging

### Manual ACME Storage Inspection
```bash
# Get Traefik pod name
TRAEFIK_POD=$(k3s kubectl get pods -n traefik -l app.kubernetes.io/name=traefik -o jsonpath='{.items[0].metadata.name}')

# Check ACME file
k3s kubectl exec -n traefik $TRAEFIK_POD -- cat /data/acme.json | jq .

# Check file permissions
k3s kubectl exec -n traefik $TRAEFIK_POD -- ls -la /data/
```

### Traefik Dashboard Access
```bash
# Port forward to access dashboard
k3s kubectl port-forward -n traefik svc/traefik 9000:9000

# Access dashboard at http://localhost:9000
```

### Manual Certificate Testing
```bash
# Test certificate chain
openssl s_client -connect headscale.yourdomain.com:443 -servername headscale.yourdomain.com -showcerts

# Check certificate expiration
echo | openssl s_client -connect headscale.yourdomain.com:443 -servername headscale.yourdomain.com 2>/dev/null | openssl x509 -noout -dates
```

## Environment Requirements

### Required Environment Variables
```bash
# In .env file
DOMAIN=yourdomain.com
ACME_EMAIL=admin@yourdomain.com
```

### Required Tools
- k3s/kubectl
- helm
- openssl
- curl
- jq
- dig/nslookup

### Network Requirements
- Domain must resolve to server's public IP
- Ports 80 and 443 must be accessible from internet
- No firewall blocking Let's Encrypt servers

## Let's Encrypt Rate Limits

Be aware of Let's Encrypt rate limits:
- **Failed Validation Limit**: 5 failures per account, per hostname, per hour
- **Certificates per Registered Domain**: 50 per week
- **Duplicate Certificate Limit**: 5 per week

## Best Practices

1. **Always test with staging first** for new configurations
2. **Monitor Traefik logs** during certificate requests
3. **Use dry-run mode** before applying fixes
4. **Keep backups** of working configurations
5. **Document changes** for future reference

## Getting Help

If these tools don't resolve your issue:

1. **Check the debug report** in `/tmp/tls-debug-*.log`
2. **Review Traefik logs** for specific error messages
3. **Verify DNS and network connectivity** manually
4. **Check Let's Encrypt status** at https://letsencrypt.status.io/
5. **Consider using staging environment** for testing

## Script Locations

All scripts are located in the `scripts/` directory:
- `scripts/debug-tls.sh` - Comprehensive diagnostics
- `scripts/fix-tls-issues.sh` - Automatic issue resolution
- `scripts/renew-certificates.sh` - Force certificate renewal
- `scripts/check-tls.sh` - Basic health check

Remember to run all scripts as root for proper k3s access.