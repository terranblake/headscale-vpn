# Headscale VPN - Self-Hosted Tailscale Deployment

A complete self-hosted VPN solution using Headscale and open-source tailscaled components.

## Overview

This repository contains a Docker-based deployment that replaces traditional router-based VPN setups with a modern, distributed mesh VPN using only open-source components.

## Architecture

- **Headscale**: Self-hosted coordination server (replaces Tailscale's servers)
- **VPN Exit Node**: Routes traffic through commercial VPN providers
- **Proxy Gateway**: Optional traffic inspection and filtering
- **Open Source tailscaled**: Built from source, no proprietary dependencies

## Quick Start

```bash
# Clone and setup
git clone <this-repo>
cd headscale-vpn

# Start the infrastructure
docker-compose up -d

# Add your first device
./scripts/add-device.sh
```

## Documentation

- [Migration Plan](MIGRATION_PLAN.md) - Detailed migration strategy
- [Configuration Guide](docs/configuration.md) - Setup and configuration
- [Troubleshooting](docs/troubleshooting.md) - Common issues and solutions

## Components

- `docker-compose.yml` - Main infrastructure deployment
- `config/` - Headscale and component configurations
- `build/` - Custom Docker images
- `scripts/` - Management and setup scripts
- `docs/` - Documentation and guides

## License

This project is open source under the MIT License.
