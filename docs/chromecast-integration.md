# Chromecast Integration Guide
## Making Jellyfin Work with Chromecast Through VPN

### The Chromecast Challenge

Chromecast has unique networking requirements that make VPN integration tricky:

1. **Local Network Discovery**: Chromecast only discovers services on the same local network
2. **Direct IP Communication**: Chromecast connects directly to media servers by IP
3. **No VPN Client**: Chromecast cannot run VPN clients
4. **Firewall Restrictions**: Chromecast has strict network security

## Solution Overview

We solve this by creating a **local bridge device** that:
- Appears as a "local" Jellyfin server to Chromecast
- Proxies all requests through the VPN to your actual Jellyfin server
- Handles service discovery (mDNS/SSDP) to make Jellyfin discoverable

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Chromecast    │    │  Bridge Device  │    │ Jellyfin Server │
│                 │    │                 │    │  (via VPN)      │
│ • Discovers     │◄──►│ • Local Proxy   │◄──►│                 │
│   "Local" Server│    │ • mDNS/SSDP     │    │ • Your Content  │
│ • Streams Media │    │ • VPN Client    │    │ • Home Network  │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## Implementation Options

### Option 1: Dedicated Bridge Device (Recommended)

**Hardware**: Raspberry Pi, Mini PC, or Android TV Box

**Setup Process**:
1. Configure bridge device at home
2. Ship/carry to remote location
3. Plug into network where Chromecast is located
4. Chromecast automatically discovers "local" Jellyfin

**Pros**:
- ✅ Works with any Chromecast model
- ✅ No configuration needed on TV/Chromecast
- ✅ Reliable and always-on
- ✅ Best performance

**Cons**:
- ❌ Requires additional hardware
- ❌ Need to ship/carry device

### Option 2: Mobile Phone Bridge

**Setup Process**:
1. Install bridge app on phone
2. Connect phone to VPN
3. Create WiFi hotspot from phone
4. Connect Chromecast to phone's hotspot
5. Phone proxies Jellyfin traffic

**Pros**:
- ✅ No additional hardware
- ✅ Works immediately
- ✅ Portable solution

**Cons**:
- ❌ Drains phone battery
- ❌ Phone must stay connected
- ❌ Limited by phone's data/WiFi

### Option 3: Router-Level VPN (If Available)

**Setup Process**:
1. Configure router's VPN client
2. Route Jellyfin traffic through VPN
3. Chromecast uses router's VPN connection

**Pros**:
- ✅ Works for all devices
- ✅ No additional hardware

**Cons**:
- ❌ Requires router admin access
- ❌ Not available in most scenarios
- ❌ Complex configuration

## Detailed Implementation: Bridge Device

### Hardware Requirements

**Minimum Specs**:
- ARM or x86 processor
- 1GB RAM
- 8GB storage
- Ethernet + WiFi
- Power adapter

**Recommended Devices**:

1. **Raspberry Pi 4** ($35-75)
   - Easy to configure
   - Low power consumption
   - Excellent community support

2. **GL.iNet Travel Router** ($30-60)
   - Pre-built for networking
   - VPN client built-in
   - Portable design

3. **Intel NUC** ($100-200)
   - Most powerful option
   - Can run multiple services
   - Professional reliability

### Software Setup

#### 1. Base System Configuration

```bash
# Install required packages
sudo apt update && sudo apt install -y \
    python3 python3-pip \
    dnsmasq avahi-daemon \
    iptables-persistent

# Install Python dependencies
pip3 install aiohttp zeroconf netifaces
```

#### 2. Bridge Service Configuration

```python
# /opt/jellyfin-bridge/config.py
JELLYFIN_VPN_URL = "http://100.64.0.2:8096"  # Your Jellyfin via VPN
LOCAL_IP = "192.168.1.100"  # Bridge device IP
LOCAL_PORT = 8096
HEADSCALE_URL = "https://your-headscale.com"
PREAUTH_KEY = "your-preauth-key"
```

#### 3. Service Discovery Setup

```bash
# /etc/avahi/services/jellyfin.service
<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name replace-wildcards="yes">Jellyfin Media Server</name>
  <service>
    <type>_jellyfin._tcp</type>
    <port>8096</port>
    <txt-record>Version=10.8.0</txt-record>
    <txt-record>Product=Jellyfin Server</txt-record>
  </service>
</service-group>
```

### Automated Setup Script

```bash
#!/bin/bash
# setup-chromecast-bridge.sh

echo "🎬 Setting up Chromecast Jellyfin Bridge..."

# Get configuration
read -p "Enter your Jellyfin VPN URL: " JELLYFIN_URL
read -p "Enter your Headscale URL: " HEADSCALE_URL
read -p "Enter your pre-auth key: " PREAUTH_KEY

# Install dependencies
sudo apt update
sudo apt install -y python3-pip dnsmasq avahi-daemon

# Install Python packages
pip3 install aiohttp zeroconf netifaces qrcode

# Download bridge software
wget -O /opt/jellyfin-bridge.py https://raw.githubusercontent.com/your-repo/chromecast_bridge.py

# Create configuration
cat > /opt/jellyfin-bridge.conf << EOF
JELLYFIN_VPN_URL=$JELLYFIN_URL
HEADSCALE_URL=$HEADSCALE_URL
PREAUTH_KEY=$PREAUTH_KEY
LOCAL_IP=$(hostname -I | awk '{print $1}')
EOF

# Create systemd service
cat > /etc/systemd/system/jellyfin-bridge.service << EOF
[Unit]
Description=Jellyfin Chromecast Bridge
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 /opt/jellyfin-bridge.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Enable and start service
sudo systemctl enable jellyfin-bridge
sudo systemctl start jellyfin-bridge

echo "✅ Bridge setup complete!"
echo "📱 Configure your Jellyfin app to use: http://$(hostname -I | awk '{print $1}'):8096"
```

## User Setup Instructions

### For the Bridge Device Owner

1. **Initial Setup** (at home):
   ```bash
   # Run setup script
   curl -sSL https://your-domain.com/setup-bridge.sh | bash
   
   # Test connection
   curl http://localhost:8096/System/Info
   ```

2. **Deployment** (to remote location):
   - Package bridge device with power adapter
   - Include simple instruction card
   - Ship or carry to destination

3. **Remote Setup** (by recipient):
   - Plug device into power and ethernet
   - Wait 2-3 minutes for startup
   - Chromecast should automatically discover Jellyfin

### For the End User (Chromecast Owner)

1. **Phone/Tablet Setup**:
   ```
   📱 Open Jellyfin app
   ➕ Add server manually
   🌐 Enter: http://192.168.1.100:8096
   🔑 Login with provided credentials
   ✅ Server should appear as "available"
   ```

2. **Casting to Chromecast**:
   ```
   📺 Start playing content in Jellyfin app
   📡 Tap cast button
   🎯 Select your Chromecast
   🎬 Content starts playing on TV
   ```

3. **Troubleshooting**:
   - Ensure phone and Chromecast are on same network
   - Restart Chromecast if not appearing
   - Check bridge device status lights

## Advanced Features

### 1. Multi-Service Support

Extend the bridge to support multiple services:

```python
# Support multiple media servers
SERVICES = {
    'jellyfin': {'url': 'http://100.64.0.2:8096', 'port': 8096},
    'plex': {'url': 'http://100.64.0.3:32400', 'port': 32400},
    'emby': {'url': 'http://100.64.0.4:8920', 'port': 8920}
}
```

### 2. Quality Optimization

Optimize streaming for remote connections:

```python
# Automatic transcoding based on bandwidth
def get_optimal_quality(bandwidth_mbps):
    if bandwidth_mbps > 25:
        return "Original"
    elif bandwidth_mbps > 10:
        return "1080p"
    elif bandwidth_mbps > 5:
        return "720p"
    else:
        return "480p"
```

### 3. Bandwidth Monitoring

Monitor and adapt to network conditions:

```python
# Real-time bandwidth monitoring
class BandwidthMonitor:
    def __init__(self):
        self.current_bandwidth = 0
        
    async def monitor_bandwidth(self):
        # Measure actual throughput
        # Adjust quality settings
        # Log performance metrics
```

### 4. Remote Management

Web interface for remote management:

```html
<!-- Bridge management interface -->
<div class="bridge-dashboard">
    <h2>📺 Chromecast Bridge Status</h2>
    <div class="status">
        <span class="indicator connected">🟢</span>
        Connected to Jellyfin
    </div>
    <div class="services">
        <h3>Available Services</h3>
        <ul>
            <li>🎬 Jellyfin Media Server</li>
            <li>📊 Current Bandwidth: 15 Mbps</li>
            <li>👥 Active Streams: 1</li>
        </ul>
    </div>
</div>
```

## Deployment Strategies

### 1. Family/Friends Network

**Scenario**: Setting up Jellyfin access for family members

**Approach**:
- Pre-configure Raspberry Pi at home
- Mail to family member with simple instructions
- Provide remote support via TeamViewer/SSH

**Instructions Card**:
```
📦 Jellyfin Bridge Setup

1. 🔌 Plug into power and ethernet
2. ⏰ Wait 3 minutes for startup
3. 📱 Open Jellyfin app on phone
4. ➕ Add server: http://192.168.1.100:8096
5. 🔑 Login: username/password (provided separately)
6. 📺 Cast to your Chromecast as normal

Need help? Call/text: [your number]
```

### 2. Vacation Rental

**Scenario**: Temporary setup in vacation rental

**Approach**:
- Portable bridge device in travel case
- Quick setup and teardown
- Mobile hotspot backup option

### 3. Multiple Locations

**Scenario**: Permanent setup across multiple locations

**Approach**:
- Deploy bridge devices to each location
- Centralized management dashboard
- Automated updates and monitoring

## Security Considerations

### 1. Network Isolation

```bash
# Isolate bridge traffic
iptables -A INPUT -i br0 -p tcp --dport 8096 -j ACCEPT
iptables -A INPUT -i br0 -j DROP
```

### 2. Access Control

```python
# IP-based access control
ALLOWED_NETWORKS = [
    "192.168.1.0/24",  # Local network
    "10.0.0.0/8"       # Private networks
]
```

### 3. Encryption

```python
# TLS termination at bridge
SSL_CERT = "/etc/ssl/bridge.crt"
SSL_KEY = "/etc/ssl/bridge.key"
```

## Performance Optimization

### 1. Caching

```python
# Cache frequently accessed content
CACHE_DIR = "/var/cache/jellyfin-bridge"
CACHE_SIZE_GB = 10
```

### 2. Compression

```python
# Compress responses
ENABLE_GZIP = True
COMPRESSION_LEVEL = 6
```

### 3. Connection Pooling

```python
# Reuse connections to Jellyfin
MAX_CONNECTIONS = 10
KEEP_ALIVE_TIMEOUT = 30
```

## Troubleshooting Guide

### Common Issues

1. **Chromecast Not Discovering Server**
   - Check mDNS service: `systemctl status avahi-daemon`
   - Verify network connectivity: `ping chromecast-ip`
   - Restart bridge service: `systemctl restart jellyfin-bridge`

2. **Playback Stuttering**
   - Check bandwidth: `iperf3 -c jellyfin-server`
   - Reduce quality in Jellyfin app
   - Monitor bridge CPU usage: `htop`

3. **Authentication Failures**
   - Verify VPN connection: `tailscale status`
   - Check Jellyfin credentials
   - Review bridge logs: `journalctl -u jellyfin-bridge`

### Diagnostic Commands

```bash
# Check bridge status
curl http://localhost:8096/System/Info

# Test VPN connectivity
ping 100.64.0.2

# Monitor traffic
tcpdump -i any port 8096

# Check service discovery
avahi-browse -a
```

This comprehensive Chromecast integration makes your VPN-hosted Jellyfin server work seamlessly with Chromecast devices, providing a user experience identical to having a local media server.