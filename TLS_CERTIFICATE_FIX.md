# TLS Certificate Fix for Traefik Let's Encrypt

## Problem Description

The Traefik configuration was using self-signed certificates instead of Let's Encrypt certificates due to a conflict between the Kubernetes Ingress TLS configuration and Traefik's ACME certificate resolver.

## Root Cause

The issue was in the `k8s/ingress.yaml` file where both of these were specified:
1. `traefik.ingress.kubernetes.io/router.tls.certresolver: letsencrypt` (telling Traefik to use ACME)
2. `secretName: headscale-tls` (telling Kubernetes to use a specific TLS secret)

When a `secretName` is specified in the Ingress TLS section, Traefik prioritizes that secret over the ACME-generated certificate. Since the `headscale-tls` secret either didn't exist or contained a self-signed certificate, that's what was being served.

## Changes Made

### 1. Fixed Ingress Configuration (`k8s/ingress.yaml`)

**Before:**
```yaml
spec:
  tls:
  - hosts:
    - headscale.terranblake.com
    secretName: headscale-tls  # This conflicts with ACME
```

**After:**
```yaml
spec:
  tls:
  - hosts:
    - headscale.${DOMAIN}
    # Remove secretName to let Traefik ACME handle certificate generation
```

**Additional changes:**
- Added `traefik.ingress.kubernetes.io/redirect-to-https: "true"` annotation
- Changed hardcoded domain to use `${DOMAIN}` environment variable

### 2. Updated Traefik Values (`k8s/traefik-values.yaml`)

**Before:**
```yaml
certificatesResolvers:
  letsencrypt:
    acme:
      email: admin@terranblake.com
```

**After:**
```yaml
certificatesResolvers:
  letsencrypt:
    acme:
      email: ${ACME_EMAIL}
```

### 3. Enhanced Deployment Script (`scripts/deploy-k3s.sh`)

**Added environment variable substitution for Traefik values:**
```bash
# Install Traefik with our custom values (substitute environment variables)
local temp_values="/tmp/traefik-values-processed.yaml"
envsubst < "$K8S_DIR/traefik-values.yaml" > "$temp_values"

helm upgrade --install traefik traefik/traefik \
    --namespace traefik \
    --values "$temp_values" \
    --wait --timeout=5m
```

**Added cleanup of conflicting TLS secrets:**
```bash
# Clean up any existing TLS secrets that might conflict with ACME
k3s kubectl delete secret headscale-tls -n headscale-vpn 2>/dev/null || true
```

### 4. New Troubleshooting Tools

**Created `scripts/check-tls.sh`:**
- Comprehensive TLS certificate troubleshooting
- Checks Traefik status, ACME storage, ingress configuration
- Tests DNS resolution and certificate status
- Provides troubleshooting tips

**Created `scripts/renew-certificates.sh`:**
- Forces certificate renewal by clearing ACME storage
- Safely restarts Traefik to trigger new certificate requests

## How to Apply the Fix

### Option 1: Redeploy Everything (Recommended)
```bash
# Run the deployment script which includes all fixes
sudo ./scripts/deploy-k3s.sh
```

### Option 2: Apply Changes to Existing Deployment
```bash
# 1. Update the ingress configuration
envsubst < k8s/ingress.yaml | k3s kubectl apply -f -

# 2. Update Traefik with new values
envsubst < k8s/traefik-values.yaml > /tmp/traefik-values-processed.yaml
helm upgrade traefik traefik/traefik \
    --namespace traefik \
    --values /tmp/traefik-values-processed.yaml

# 3. Clean up conflicting secrets
k3s kubectl delete secret headscale-tls -n headscale-vpn 2>/dev/null || true

# 4. Force certificate renewal if needed
sudo ./scripts/renew-certificates.sh
```

## Verification Steps

1. **Check TLS configuration:**
   ```bash
   sudo ./scripts/check-tls.sh
   ```

2. **Monitor Traefik logs for ACME activity:**
   ```bash
   k3s kubectl logs -f -n traefik -l app.kubernetes.io/name=traefik | grep -i acme
   ```

3. **Test the certificate:**
   ```bash
   openssl s_client -connect headscale.yourdomain.com:443 -servername headscale.yourdomain.com < /dev/null | openssl x509 -noout -issuer -subject -dates
   ```

4. **Check certificate in browser:**
   - Visit `https://headscale.yourdomain.com`
   - Click the lock icon to view certificate details
   - Verify issuer is "Let's Encrypt Authority"

## Expected Behavior After Fix

1. **Initial deployment:** Traefik will request a new Let's Encrypt certificate via HTTP-01 challenge
2. **Certificate storage:** Certificate will be stored in `/data/acme.json` within the Traefik pod
3. **Automatic renewal:** Traefik will automatically renew certificates before expiration
4. **No manual secrets:** No need to manually create or manage TLS secrets

## Troubleshooting

### If certificates are still not working:

1. **Check DNS:** Ensure `headscale.yourdomain.com` resolves to your server's public IP
2. **Check firewall:** Ports 80 and 443 must be accessible from the internet
3. **Check rate limits:** Let's Encrypt has rate limits (5 failures per hour, 50 certificates per week)
4. **Force renewal:** Use `sudo ./scripts/renew-certificates.sh`
5. **Check logs:** Monitor Traefik logs for error messages

### Common issues:

- **DNS not pointing to server:** ACME HTTP-01 challenge will fail
- **Firewall blocking ports:** Let's Encrypt cannot reach your server
- **Rate limiting:** Too many failed attempts, wait before retrying
- **Existing certificates:** Old certificates cached, force renewal needed

## Key Points

1. **Never specify `secretName` when using ACME** - let Traefik manage certificates automatically
2. **Environment variables** - use `${DOMAIN}` and `${ACME_EMAIL}` for flexibility
3. **Clean deployment** - remove conflicting secrets before applying new configuration
4. **Monitor logs** - Traefik logs show ACME certificate request progress
5. **Patience** - Initial certificate request can take a few minutes

This fix ensures that Traefik properly uses Let's Encrypt certificates instead of self-signed ones, providing proper TLS security for your Headscale deployment.