# Family Network Platform

A complete family network solution providing secure, transparent access to home services from anywhere. Built on Headscale (self-hosted Tailscale coordination server) with automatic on-demand VPN connections.

## 🎯 What This Provides

**For Family Members:**
- 🎬 **Streamyfin Media Server** - Movies, TV shows, and family content
- 📸 **Family Photo Collection** - Shared memories accessible anywhere
- 📄 **Document Storage** - Family files and important documents
- 🏠 **Home Automation** - Remote control of smart home devices
- 🔒 **Completely Secure** - Encrypted tunnels, zero technical complexity

**For Administrators:**
- 🚀 **One-time setup** - Configure once, works forever
- 📱 **Universal compatibility** - Works on any device with Tailscale
- 🌐 **Wildcard domains** - Add services without client updates
- 📊 **Built-in monitoring** - Health checks and performance metrics
- 🔧 **Production-ready** - SSL, backups, and automated maintenance

## 🏗️ How It Works

```
Family Member Device:
┌─────────────────────────────────────────────────────────┐
│ Smart Traffic Routing                                   │
│                                                         │
│ *.family.local domains    ──► VPN ──► Home Network     │
│ All other traffic         ──► Direct Internet          │
│                                                         │
│ Result: 99% direct, 1% VPN, 100% transparent           │
└─────────────────────────────────────────────────────────┘
```

**Key Benefits:**
- ✅ **Automatic VPN connection** - only for family services
- ✅ **Normal internet speed** - other apps unaffected  
- ✅ **Zero ongoing management** - works transparently
- ✅ **Universal device support** - phones, tablets, computers
- ✅ **Infinite scalability** - add services without client changes

## 📚 Documentation Structure

### 📖 [Technical Architecture](docs/01-technical-architecture/)
For system administrators and technical users:
- [System Overview](docs/01-technical-architecture/system-overview.md) - Complete architecture documentation
- [Deployment Guide](docs/01-technical-architecture/deployment-guide.md) - Production setup instructions

### 🔧 [Technical Reference](docs/02-technical-reference/)
Configuration and management documentation:
- [Configuration Guide](docs/02-technical-reference/configuration-guide.md) - Complete configuration reference
- [Monitoring Commands](docs/02-technical-reference/monitoring-commands.md) - System monitoring and maintenance
- [VPN Management](docs/02-technical-reference/vpn-management.md) - User and device management
- [Quick Reference](docs/02-technical-reference/quick-reference.md) - Common commands and procedures

### 👨‍👩‍👧‍👦 [Family Documentation](docs/03-family-docs/)
Non-technical guides for family members:
- [How It Works](docs/03-family-docs/how-it-works.md) - Simple explanation of the technology
- [Initial Setup](docs/03-family-docs/initial-setup.md) - Step-by-step connection guide
- [Available Services](docs/03-family-docs/available-services.md) - Complete service directory
- [Service Guides](docs/03-family-docs/services/) - Detailed guides for each service

## 🚀 Quick Start

### For Administrators

1. **Deploy the platform**
   ```bash
   git clone https://github.com/terranblake/headscale-vpn.git
   cd headscale-vpn
   cp .env.example .env
   cp config/headscale.yaml.example config/headscale.yaml
   # Edit configuration files
   make deploy
   ```

2. **Create family users**
   ```bash
   make create-user USER=alice
   make create-user USER=bob
   make generate-setup-config USER=alice
   ```

3. **Send setup instructions**
   - Share generated configuration with family members
   - Provide simple setup guide from family documentation
   - Offer support during initial connection

### For Family Members

1. **Install Tailscale app** on your device
2. **Connect to family network** using provided setup information
3. **Install Streamyfin app** for media access
4. **Start enjoying family content** from anywhere

**Complete setup takes 5-10 minutes and works on any device.**

## 🌟 Key Features

### Universal Compatibility
- **Mobile devices** - iPhone, iPad, Android phones and tablets
- **Computers** - Windows, macOS, Linux
- **Streaming devices** - Cast to Apple TV, Chromecast, Roku, etc.
- **Smart TVs** - Direct browser access or casting

### Automatic Operation
- **On-demand VPN** - connects only when accessing family services
- **Wildcard domains** - `*.family.local` automatically routes through VPN
- **Split tunneling** - normal internet traffic stays direct and fast
- **Zero maintenance** - family members never manage VPN connections

### Scalable Service Addition
```bash
# Add new service (admin only)
echo "  - name: photos.family.local" >> config/headscale.yaml
echo "    type: A" >> config/headscale.yaml  
echo "    value: \"192.168.1.101\"" >> config/headscale.yaml
docker restart headscale

# Family members automatically get access
# No client configuration changes needed
```

### Production Features
- **SSL certificates** - Automatic Let's Encrypt integration
- **Monitoring** - Prometheus metrics and Grafana dashboards
- **Backups** - Automated configuration and data backups
- **Health checks** - Service monitoring and automatic recovery
- **Security** - Encrypted tunnels and access control

## 🎬 Included Services

### Core Services
- **Streamyfin** - Complete media streaming platform
- **Family Photos** - Shared photo collection and memories
- **Document Storage** - Family files and important documents
- **Home Automation** - Smart home control and monitoring

### Infrastructure
- **Headscale** - VPN coordination server
- **Traefik** - Reverse proxy with automatic SSL
- **Prometheus** - Metrics collection and monitoring
- **Grafana** - Performance dashboards and alerting

## 📋 Requirements

### Server Requirements
- **Hardware** - 4+ CPU cores, 8GB+ RAM, 500GB+ storage
- **Operating System** - Ubuntu 22.04 LTS (recommended)
- **Network** - Static IP or DDNS, 100+ Mbps upload bandwidth
- **Domain** - Owned domain with DNS management access

### Client Requirements
- **Any device** with Tailscale app support
- **Internet connection** - WiFi or cellular data
- **5 minutes** for initial setup per device

## 🔒 Security Model

- **WireGuard encryption** - Modern, audited VPN protocol
- **Zero-trust networking** - Explicit access control for all services
- **Automatic updates** - Security patches applied automatically
- **Family-only access** - No external users or public access
- **Audit logging** - Complete access and change tracking

## 🎯 Perfect For

- **Families** wanting to share media and photos securely
- **Remote access** to home services while traveling
- **Cord-cutting** with personal media streaming
- **Privacy-conscious** users avoiding commercial cloud services
- **Tech enthusiasts** wanting a professional home network

## 📞 Support

- **Technical documentation** - Complete setup and configuration guides
- **Family guides** - Non-technical instructions for end users
- **Troubleshooting** - Common issues and solutions
- **Community** - GitHub issues for questions and improvements

## 📄 License

MIT License - see [LICENSE](LICENSE) file for details.

---

**Transform your home network into a professional family cloud platform with zero complexity for family members.** 🏠✨