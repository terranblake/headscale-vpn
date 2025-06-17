#!/bin/bash
# Quick setup script for headscale-vpn deployment

set -e

echo "Setting up Headscale VPN deployment..."

# Check if .env exists
if [[ ! -f .env ]]; then
    echo "Creating .env file from template..."
    cp .env.example .env
    echo "Please edit .env with your configuration before running docker-compose up"
    exit 1
fi

# Create required directories
mkdir -p data/{headscale,postgres,vpn-exit,proxy}

# Generate headscale API key if not set
if ! grep -q "HEADSCALE_API_KEY=" .env || grep -q "your_headscale_api_key_here" .env; then
    echo "Generating Headscale API key..."
    API_KEY=$(openssl rand -base64 32)
    sed -i.bak "s/your_headscale_api_key_here/$API_KEY/" .env
    echo "Generated API key: $API_KEY"
fi

echo "Setup complete! Run 'docker-compose up -d' to start the deployment."
echo ""
echo "After startup, create your first user:"
echo "docker exec headscale headscale users create admin"
echo ""
echo "Then create a device auth key:"
echo "docker exec headscale headscale preauthkeys create --user admin"
