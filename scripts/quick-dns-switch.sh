#!/bin/bash

# Quick DNS-01 switch script
set -e

echo "=== Switching to DNS-01 Challenge ==="

# 1. Create Cloudflare secret
echo "Creating Cloudflare credentials secret..."

# Check if environment variables are set
if [ -z "$CLOUDFLARE_EMAIL" ] || [ -z "$CLOUDFLARE_API_KEY" ]; then
    echo "Error: CLOUDFLARE_EMAIL and CLOUDFLARE_API_KEY environment variables must be set"
    echo "Please run: source .env"
    exit 1
fi

kubectl create secret generic cloudflare-credentials \
    --from-literal=email="$CLOUDFLARE_EMAIL" \
    --from-literal=api-key="$CLOUDFLARE_API_KEY" \
    -n kube-system \
    --dry-run=client -o yaml | kubectl apply -f -

# 2. Update Traefik
echo "Updating Traefik with DNS-01 configuration..."
helm upgrade traefik traefik/traefik \
    --namespace kube-system \
    --values k8s/traefik-values-dns.yaml \
    --set certificatesResolvers.letsencrypt.acme.email="$ACME_EMAIL"

# 3. Wait for restart
echo "Waiting for Traefik to restart..."
kubectl rollout status deployment/traefik -n kube-system --timeout=300s

# 4. Force certificate renewal
echo "Removing old ACME data..."
kubectl exec -n kube-system deployment/traefik -- rm -f /data/acme.json || true

echo "Restarting Traefik..."
kubectl rollout restart deployment/traefik -n kube-system
kubectl rollout status deployment/traefik -n kube-system --timeout=300s

echo ""
echo "=== DNS-01 Setup Complete ==="
echo "Wait 2-3 minutes for certificate generation, then test:"
echo "curl -I https://headscale.terranblake.com/"
echo "./scripts/check-tls.sh"
