#!/bin/bash
# Setup and authenticate tailscale proxy with headscale

set -e

echo "Setting up Tailscale Proxy connection to Headscale..."

# Wait for tailscaled to be ready
while ! /usr/local/bin/tailscale status >/dev/null 2>&1; do
    echo "Waiting for tailscaled to start..."
    sleep 2
done

# Check if already authenticated
if /usr/local/bin/tailscale status --json | grep -q '"BackendState":"Running"'; then
    echo "Tailscale already authenticated and running"
    exit 0
fi

# Configure tailscale to use headscale
echo "Configuring tailscale to use Headscale server: ${HEADSCALE_URL}"

# Authenticate with headscale as a proxy gateway
/usr/local/bin/tailscale up \
    --login-server="${HEADSCALE_URL}" \
    --accept-routes \
    --accept-dns=false \
    --hostname="proxy-gateway" \
    --authkey="${HEADSCALE_API_KEY}" || {
    
    echo "Authentication failed, trying manual registration..."
    echo "Please run the following command on your headscale server:"
    echo "headscale nodes register --user admin --key \$(tailscale up --login-server=${HEADSCALE_URL} --hostname=proxy-gateway 2>&1 | grep -o 'nodekey:[a-f0-9]*')"
    
    # Keep trying to authenticate
    while true; do
        sleep 30
        if /usr/local/bin/tailscale status --json | grep -q '"BackendState":"Running"'; then
            echo "Authentication successful!"
            break
        fi
        echo "Still waiting for authentication..."
    done
}

echo "Tailscale proxy setup complete!"
