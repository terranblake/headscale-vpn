# Migration Plan: Router VPN to Self-Hosted Headscale Deployment

## Current State Analysis

### Existing Router-Based Setup
- **Primary VPN Server**: `wireguard_server` on router for device connectivity
- **Cascaded VPN**: `wireguard_client` connects to NordVPN for traffic anonymization
- **Selective Bypass**: Complex IP rule management using `danger/zone/` Python modules
- **Proxy Functionality**: mitmproxy with `wg_proxy_in` tunnel for traffic inspection
- **Current Issues**: Router dependency, complex rule management, single point of failure

### Existing Tailscale Infrastructure
- Basic Headscale v0.22.3 setup in `tailscale/docker-compose.yml`
- Uses official Tailscale client images (need to replace with open-source)
- Basic configuration files present but incomplete

## Migration Goals

### 1. Complete Self-Hosting
- **Headscale Server**: Self-hosted control plane (no Tailscale servers)
- **Open Source tailscaled**: Use only open-source tailscaled clients
- **No External Dependencies**: All traffic routing happens within your infrastructure

### 2. Functional Equivalence
- **Device Connectivity**: All devices connect through Headscale mesh
- **VPN Exit Node**: Dedicated node for NordVPN/commercial VPN connection
- **Selective Bypass**: Configurable IP/domain bypass (no VPN routing)
- **Proxy Capability**: Optional traffic inspection via dedicated proxy node

### 3. Improved Architecture
- **Distributed**: No single point of failure
- **Scalable**: Easy to add new devices and exit nodes
- **Maintainable**: Docker-based deployment with clear configuration

## Proposed Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Your Devices  │    │   Headscale      │    │  VPN Exit Node  │
│                 │    │   Control Plane  │    │                 │
│ • Phone         │◄──►│                  │    │ • tailscaled    │
│ • Laptop        │    │ • User/Device    │    │ • NordVPN       │
│ • Tablet        │    │   Management     │    │ • iptables      │
│ • Desktop       │    │ • ACL Rules      │    │ • Routing       │
└─────────────────┘    │ • Route Config   │    └─────────────────┘
                       └──────────────────┘
                                │
                       ┌──────────────────┐
                       │  Proxy Gateway   │
                       │  (Optional)      │
                       │                  │
                       │ • tailscaled     │
                       │ • mitmproxy      │
                       │ • Traffic Insp.  │
                       └──────────────────┘
```

## Migration Components

### Open Source Components Used

#### Headscale Ecosystem
- **Headscale Server**: `ghcr.io/juanfont/headscale:latest`
  - Open source implementation of Tailscale's coordination server
  - ACL management and device coordination
  - Route advertisements and policy enforcement

#### Tailscale Open Source Client Components
- **tailscaled**: Open source daemon from `tailscale/tailscale` repository
  - Will be built from source using official `tailscale/tailscale` Go repository
  - No proprietary Tailscale coordination dependencies
  - Configured to use only your Headscale server

- **tailscale CLI**: Open source client from same repository
  - Device management and configuration
  - Route management and exit node control
  - Status monitoring and debugging

#### Supporting Infrastructure
- **PostgreSQL**: `postgres:15-alpine` - Database for Headscale
- **Headscale UI**: `ghcr.io/gurucomputing/headscale-ui:latest` - Web management interface

### 1. Headscale Control Plane
- **Purpose**: Replace Tailscale's coordination server
- **Components**: 
  - Headscale server (ghcr.io/juanfont/headscale:latest)
  - PostgreSQL database (postgres:15-alpine)
  - Headscale UI for management (ghcr.io/gurucomputing/headscale-ui:latest)
- **Configuration**:
  - Custom domain/IP for coordination
  - ACL rules for device access and routing
  - Exit node advertisements

### 2. VPN Exit Node
- **Purpose**: Replace router's `wireguard_client` functionality
- **Components**:
  - **tailscaled**: Built from `tailscale/tailscale` Go source (latest stable)
  - **NordVPN OpenVPN client**: `openvpn` package with NordVPN configuration
  - **iptables/nftables**: For NAT and traffic routing rules
  - **unbound or systemd-resolved**: DNS resolution to prevent leaks
  - **Custom routing scripts**: Bypass list management
- **Base Image**: `ubuntu:22.04` or `alpine:3.18`
- **Functionality**:
  - Advertises itself as exit node to Headscale
  - Routes all mesh traffic through NordVPN
  - Maintains bypass rules for specified IPs/domains

### 3. Proxy Gateway (Optional)
- **Purpose**: Replace current mitmproxy functionality
- **Components**:
  - **tailscaled**: Built from `tailscale/tailscale` Go source (same as exit node)
  - **mitmproxy**: Latest stable version from PyPI
  - **Python 3.11+**: Runtime for mitmproxy and custom scripts
  - **iptables**: Traffic interception and routing
- **Base Image**: `python:3.11-slim` or `ubuntu:22.04`
- **Functionality**:
  - Intercepts and inspects traffic
  - Can be enabled/disabled per device via ACLs

### 4. Selective Bypass System
- **Configuration-Based**: Replace complex Python rule management
- **Methods**:
  - Headscale ACL rules for routing policies
  - Exit node bypass lists (IPs/domains)
  - Client-side routing overrides

## Implementation Phases

### Phase 1: Infrastructure Setup
1. **Enhanced Docker Compose**:
   - Headscale server: `ghcr.io/juanfont/headscale:latest`
   - PostgreSQL: `postgres:15-alpine`
   - Headscale UI: `ghcr.io/gurucomputing/headscale-ui:latest`
   - Proper networking and volumes

2. **Custom Docker Images Built from Source**:
   - **VPN Exit Node**: Ubuntu 22.04 base with tailscaled built from `tailscale/tailscale`
   - **Proxy Gateway**: Python 3.11 base with tailscaled and mitmproxy
   - **Build Process**: Multi-stage Docker builds using official Go toolchain

### Phase 2: Network Configuration
1. **Headscale ACL Configuration**:
   - Device access policies
   - Exit node routing rules
   - Bypass policies for specific traffic

2. **Exit Node Setup**:
   - NordVPN connection management
   - DNS leak prevention
   - Traffic routing rules

### Phase 3: Device Migration
1. **Gradual Migration**:
   - Add devices one by one to Headscale
   - Test connectivity and routing
   - Verify bypass functionality

2. **Validation**:
   - Confirm all traffic routing works
   - Test bypass rules
   - Verify no traffic goes to Tailscale servers

### Phase 4: Router Decommission
1. **Traffic Validation**:
   - Ensure all devices work through Headscale
   - Confirm VPN exit functionality
   - Test proxy capabilities

2. **Router Cleanup**:
   - Disable router VPN services
   - Remove complex routing rules
   - Simplify router to basic networking

## Key Configuration Files

### 1. `docker-compose.yml`
- Headscale server with PostgreSQL
- VPN exit node container
- Proxy gateway container
- Proper networking and dependencies

### 2. `headscale-config.yaml`
- Server configuration
- Database settings
- DERP server configuration (optional)

### 3. `acl.hjson`
- Device access policies
- Exit node routing rules
- Bypass configurations

### 4. Exit Node Configuration
- NordVPN credentials and server selection
- Bypass IP/domain lists
- Routing and firewall rules

## Migration Benefits

### Advantages
- **No External Dependencies**: Complete control over coordination
- **Better Security**: No traffic through third-party coordination servers
- **Simplified Management**: Configuration-based vs. complex scripting
- **Scalability**: Easy to add exit nodes in different locations
- **Reliability**: Distributed architecture, no single point of failure

### Considerations
- **Initial Setup Complexity**: More components to configure initially
- **Maintenance**: Need to maintain Headscale server and updates
- **Learning Curve**: New tooling and configuration patterns

## Next Steps for Review

Please review this plan and confirm:

1. **Architecture Approach**: Does the proposed mesh + exit node architecture meet your needs?
2. **Component Selection**: Are you comfortable with the Headscale + open-source tailscaled approach?
3. **Migration Strategy**: Does the phased approach work for your timeline?
4. **Bypass Handling**: Is the configuration-based bypass system preferable to your current Python-based rules?
5. **Scope**: Any additional requirements or constraints I should consider?

Once you approve this plan, I'll proceed with implementing the Docker configurations, ACL rules, and migration scripts.

### Build Process for Open Source Components

#### tailscaled Build Configuration
```dockerfile
# Multi-stage build to compile tailscaled from source
FROM golang:1.21-alpine AS builder
RUN apk add --no-cache git ca-certificates
WORKDIR /src
RUN git clone https://github.com/tailscale/tailscale.git .
RUN go mod download
RUN go build -ldflags="-s -w" -o tailscaled ./cmd/tailscaled
RUN go build -ldflags="-s -w" -o tailscale ./cmd/tailscale
```

#### Key Source Repositories
- **Primary Source**: `github.com/tailscale/tailscale` (Apache 2.0 License)
  - Contains both `tailscaled` daemon and `tailscale` CLI
  - Fully open source with no proprietary coordination dependencies
  - Will be configured to use only your Headscale server via `--login-server` flag

#### Verification of Open Source Nature
- All components use Apache 2.0 or BSD licenses
- No binary downloads from Tailscale Inc.
- Complete source code compilation
- No telemetry or external service dependencies when configured with Headscale
