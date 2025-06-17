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

# Initial setup
make setup

# Edit configuration
nano .env

# Start the infrastructure
make up

# Create first user and auth key
make user-create USER=admin
make key-create USER=admin
```

## Usage

```bash
# Common operations
make help              # Show all commands
make status            # Check service status
make logs              # View logs
make nodes-list        # List connected devices

# Direct headscale commands
docker exec headscale headscale users create john
docker exec headscale headscale preauthkeys create --user john
```

## Documentation

- [Migration Plan](MIGRATION_PLAN.md) - Detailed migration strategy
- [Configuration Guide](docs/configuration.md) - Setup and configuration
- [Troubleshooting](docs/troubleshooting.md) - Common issues and solutions

## Components

- `docker-compose.yml` - Main infrastructure deployment
- `config/` - Headscale and component configurations
- `build/` - Custom Docker images built from source
- `docs/` - Documentation and guides
- `Makefile` - Convenient commands for common operations
- `setup.sh` - Initial setup script

## License

This project is open source under the MIT License.
