# System Architecture Overview
## Headscale-VPN Family Network Platform

### 🎯 System Purpose

This platform provides secure, transparent access to family services hosted on a home network. Family members connect through a VPN that automatically activates only for family services, leaving their normal internet usage unaffected.

---

## 🏗️ Architecture Components

### Core Infrastructure
```
┌─────────────────────────────────────────────────────────────┐
│                    Home Network                             │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────┐ │
│  │   Headscale     │  │  Family Services │  │   Router    │ │
│  │   VPN Server    │  │  (Streamyfin,    │  │   Gateway   │ │
│  │                 │  │   Photos, etc.)  │  │             │ │
│  └─────────────────┘  └─────────────────┘  └─────────────┘ │
└─────────────────────────────────────────────────────────────┘
                              │
                              │ VPN Tunnel
                              │
┌─────────────────────────────────────────────────────────────┐
│                  Family Member Devices                     │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────┐ │
│  │  Mobile Device  │  │  Mobile Device  │  │ Streaming   │ │
│  │  (VPN Client)   │  │  (VPN Client)   │  │   Device    │ │
│  │                 │  │                 │  │             │ │
│  └─────────────────┘  └─────────────────┘  └─────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

### Traffic Flow
```
Family Member Device:
┌─────────────────────────────────────────────────────────┐
│ Application Traffic Routing                             │
│                                                         │
│ *.family.local domains    ──► VPN ──► Home Network     │
│ *.terr.ac domains         ──► VPN ──► Home Network     │
│ All other traffic         ──► Direct Internet          │
│                                                         │
│ Result: 99% direct, 1% VPN, 100% transparent           │
└─────────────────────────────────────────────────────────┘
```

---

## 🔧 Technical Stack

### VPN Infrastructure
- **Headscale**: Self-hosted Tailscale coordination server
- **WireGuard**: Underlying VPN protocol (via Tailscale)
- **Magic DNS**: Automatic service discovery and routing
- **On-Demand VPN**: iOS-native automatic connection management

### Service Layer
- **Docker Compose**: Service orchestration
- **Traefik**: Reverse proxy and SSL termination
- **Let's Encrypt**: Automatic SSL certificate management
- **Prometheus**: Metrics collection and monitoring

### Client Technology
- **On-Demand VPN**: Automatic connection management
- **Wildcard Domain Routing**: Scalable service addition
- **Cross-Platform Support**: Works on mobile, desktop, and streaming devices
- **Universal Casting**: Compatible with various streaming protocols

---

## 🌐 Network Design

### DNS Architecture
```yaml
# Headscale Magic DNS Configuration
dns_config:
  magic_dns: true
  base_domain: family.local
  nameservers:
    - 1.1.1.1
    - 8.8.8.8
  extra_records:
    - name: "*.family.local"
      type: A
      value: "192.168.1.1"  # Home router/reverse proxy
```

### VPN Network Topology
```
Tailscale Network: 100.64.0.0/10
├── 100.64.0.1    # Headscale server
├── 100.64.0.2    # Home network gateway
├── 100.64.0.10   # Family member 1 (iPhone)
├── 100.64.0.11   # Family member 2 (iPad)
└── 100.64.0.12   # Family member 3 (iPhone)

Home Network: 192.168.1.0/24
├── 192.168.1.1   # Router/Gateway
├── 192.168.1.100 # Streamyfin server
├── 192.168.1.101 # Photo server
└── 192.168.1.102 # Document server
```

### Service Discovery
```
DNS Resolution Flow:
1. Family member visits streamyfin.family.local
2. VPN client checks routing rules: *.family.local → Connect VPN
3. VPN connects automatically
4. DNS query routed through Headscale Magic DNS
5. Returns 192.168.1.100 (Streamyfin server)
6. Traffic flows: Device → VPN → Home → Streamyfin
7. When done, VPN disconnects automatically
```

---

## 🔒 Security Model

### Authentication & Authorization
```
User Management:
├── Headscale Users (one per family member)
├── Pre-auth Keys (time-limited, single-use)
├── Service-level Authentication (individual app logins)
└── Network ACLs (restrict access to home network only)
```

### Encryption & Transport
```
Security Layers:
├── WireGuard Encryption (VPN tunnel)
├── TLS/HTTPS (service-level encryption)
├── Application Authentication (service logins)
└── Network Isolation (VPN-only access)
```

### Access Control
```yaml
# Tailscale ACL Configuration
{
  "groups": {
    "group:family": ["tag:family-member"],
    "group:servers": ["tag:home-server"]
  },
  "acls": [
    {
      "action": "accept",
      "src": ["group:family"],
      "dst": ["group:servers:*", "192.168.1.0/24:*"]
    }
  ]
}
```

---

## 📊 Scalability Design

### Horizontal Scaling
```
Service Addition Process:
1. Deploy new service on home network
2. Add DNS record to Headscale config
3. Restart Headscale (applies DNS changes)
4. Service automatically available to all family members
5. No client configuration changes needed
```

### Performance Characteristics
```
Expected Load:
├── Concurrent Users: 5-10 family members
├── Bandwidth: 100-500 Mbps (streaming video)
├── Latency: <50ms (local network + VPN overhead)
└── Availability: 99.9% (home internet dependent)
```

### Resource Requirements
```
Home Server Minimum:
├── CPU: 4 cores (Intel i5 or equivalent)
├── RAM: 8GB (16GB recommended)
├── Storage: 500GB SSD (2TB+ for media)
├── Network: Gigabit ethernet
└── Internet: 100+ Mbps upload (for remote streaming)
```

---

## 🔄 Data Flow Patterns

### Media Streaming Flow
```
1. Family member opens Streamyfin app
2. VPN client activates for *.family.local domains
3. App connects to streamyfin.family.local
4. Authentication with stored credentials
5. Browse media library (metadata over VPN)
6. Select content to play
7. Video stream: Home Server → VPN → Mobile Device
8. Cast to streaming device (local network casting)
9. Close app → VPN disconnects automatically
```

### Service Discovery Flow
```
1. New service deployed: photos.family.local
2. DNS record added to Headscale
3. Family member visits URL
4. iOS recognizes *.family.local pattern
5. VPN connects automatically
6. Service loads and functions normally
7. Bookmark created for future access
```

---

## 🎯 Design Principles

### Transparency
- **Zero VPN management** for family members
- **Automatic connection** for family services only
- **Normal internet speed** for all other usage
- **No technical knowledge** required

### Reliability
- **Self-healing** VPN connections
- **Automatic failover** for service discovery
- **Graceful degradation** when services unavailable
- **Minimal single points of failure**

### Maintainability
- **Infrastructure as Code** (Docker Compose)
- **Automated monitoring** and alerting
- **Simple service addition** process
- **Clear documentation** and procedures

### Security
- **Defense in depth** (multiple security layers)
- **Principle of least privilege** (minimal access grants)
- **Regular security updates** (automated where possible)
- **Audit logging** for access and changes

---

## 🚀 Deployment Architecture

### Production Environment
```
Home Network Deployment:
├── Docker Host (main server)
│   ├── Headscale (VPN coordination)
│   ├── Traefik (reverse proxy)
│   ├── Streamyfin (media server)
│   └── Monitoring (Prometheus/Grafana)
├── Network Storage (NAS)
│   ├── Media files
│   ├── Family photos
│   └── Document storage
└── Network Infrastructure
    ├── Router/Firewall
    ├── Managed switch
    └── WiFi access points
```

### Development/Testing
```
Local Development:
├── Docker Compose (service orchestration)
├── Test VPN clients (iOS Simulator)
├── Mock services (development versions)
└── Local DNS (for testing domain resolution)
```

This architecture provides a robust, scalable foundation for family network services while maintaining simplicity for end users and administrators.