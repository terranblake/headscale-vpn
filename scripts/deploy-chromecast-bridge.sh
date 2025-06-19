#!/bin/bash
# Deploy Chromecast Bridge for Jellyfin
# This script sets up a bridge device to make VPN-hosted Jellyfin work with Chromecast

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run as root (use sudo)"
   exit 1
fi

echo -e "${BLUE}"
cat << "EOF"
  ______ _                                           _   
 / _____) |                                         | |  
| /     | |__  ____ ___  ____   ____ ____ ____  ____| |_ 
| |     |  _ \|  __) _ \|    \ / _  ) _  |  _ \|  _ |  _)
| \_____| | | | | | |_| | | | ( (/ ( (/ /| | | | | | | |_
 \______)_| |_|_|  \___/|_|_|_|\____)____)_| |_|_| |_|\__)
                                                          
     ____       _     _            
    |  _ \     (_)   | |           
    | |_) |____ _  __| | ____  ___ 
    |  _ (/ ___) |/ _  |/ _  |/ _ \
    | |_) ) |   | ( (_| ( (/ /  __/
    |____/|_|   |_|\____|\___)\___|
                                   
EOF
echo -e "${NC}"

echo "🎬 Chromecast Jellyfin Bridge Deployment"
echo "========================================"
echo

# Get configuration from user
log_step "Gathering configuration..."

read -p "Enter your Jellyfin VPN URL (e.g., http://100.64.0.2:8096): " JELLYFIN_URL
read -p "Enter your Headscale server URL: " HEADSCALE_URL
read -p "Enter your Headscale pre-auth key: " PREAUTH_KEY

# Validate URLs
if [[ ! $JELLYFIN_URL =~ ^https?:// ]]; then
    log_error "Invalid Jellyfin URL format"
    exit 1
fi

if [[ ! $HEADSCALE_URL =~ ^https?:// ]]; then
    log_error "Invalid Headscale URL format"
    exit 1
fi

# Detect local IP
LOCAL_IP=$(hostname -I | awk '{print $1}')
log_info "Detected local IP: $LOCAL_IP"

# Update system
log_step "Updating system packages..."
apt update && apt upgrade -y

# Install dependencies
log_step "Installing dependencies..."
apt install -y \
    python3 \
    python3-pip \
    python3-venv \
    dnsmasq \
    avahi-daemon \
    avahi-utils \
    iptables-persistent \
    curl \
    wget \
    git

# Install Tailscale
log_step "Installing Tailscale..."
if ! command -v tailscale &> /dev/null; then
    curl -fsSL https://tailscale.com/install.sh | sh
else
    log_info "Tailscale already installed"
fi

# Create bridge directory
log_step "Setting up bridge application..."
mkdir -p /opt/chromecast-bridge
cd /opt/chromecast-bridge

# Create Python virtual environment
python3 -m venv venv
source venv/bin/activate

# Install Python dependencies
pip install aiohttp zeroconf netifaces qrcode[pil]

# Create bridge configuration
log_step "Creating configuration..."
cat > config.json << EOF
{
    "jellyfin_vpn_url": "$JELLYFIN_URL",
    "headscale_url": "$HEADSCALE_URL",
    "preauth_key": "$PREAUTH_KEY",
    "local_ip": "$LOCAL_IP",
    "local_port": 8096,
    "log_level": "INFO"
}
EOF

# Copy bridge script
log_step "Installing bridge software..."
cp /workspace/headscale-vpn/build/smart-tv-bridge/scripts/chromecast_bridge.py ./bridge.py

# Create systemd service
log_step "Creating system service..."
cat > /etc/systemd/system/chromecast-bridge.service << EOF
[Unit]
Description=Chromecast Jellyfin Bridge
After=network.target tailscaled.service
Wants=tailscaled.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/chromecast-bridge
ExecStartPre=/bin/sleep 10
ExecStart=/opt/chromecast-bridge/venv/bin/python bridge.py
Restart=always
RestartSec=10
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
EOF

# Configure Avahi for service discovery
log_step "Configuring service discovery..."
cat > /etc/avahi/services/jellyfin.service << EOF
<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name replace-wildcards="yes">Jellyfin Media Server</name>
  <service>
    <type>_jellyfin._tcp</type>
    <port>8096</port>
    <txt-record>Version=10.8.0</txt-record>
    <txt-record>Product=Jellyfin Server</txt-record>
    <txt-record>Id=chromecast-bridge</txt-record>
  </service>
</service-group>
EOF

# Configure firewall
log_step "Configuring firewall..."
iptables -A INPUT -p tcp --dport 8096 -j ACCEPT
iptables -A INPUT -p udp --dport 5353 -j ACCEPT  # mDNS
iptables -A INPUT -p udp --dport 1900 -j ACCEPT  # SSDP
iptables-save > /etc/iptables/rules.v4

# Connect to VPN
log_step "Connecting to VPN..."
tailscale up \
    --login-server="$HEADSCALE_URL" \
    --authkey="$PREAUTH_KEY" \
    --hostname="chromecast-bridge" \
    --accept-routes \
    --accept-dns=false

# Wait for VPN connection
log_info "Waiting for VPN connection..."
sleep 10

# Test Jellyfin connectivity
log_step "Testing Jellyfin connectivity..."
if curl -s --max-time 10 "$JELLYFIN_URL/System/Info" > /dev/null; then
    log_info "✅ Jellyfin connection successful"
else
    log_warn "⚠️  Could not connect to Jellyfin (will retry automatically)"
fi

# Enable and start services
log_step "Starting services..."
systemctl daemon-reload
systemctl enable avahi-daemon
systemctl enable chromecast-bridge
systemctl start avahi-daemon
systemctl start chromecast-bridge

# Wait for services to start
sleep 5

# Check service status
log_step "Checking service status..."
if systemctl is-active --quiet chromecast-bridge; then
    log_info "✅ Chromecast bridge service is running"
else
    log_error "❌ Bridge service failed to start"
    systemctl status chromecast-bridge
    exit 1
fi

# Create status check script
log_step "Creating status check script..."
cat > /usr/local/bin/bridge-status << 'EOF'
#!/bin/bash
echo "🎬 Chromecast Bridge Status"
echo "=========================="
echo
echo "🔗 VPN Status:"
tailscale status --self
echo
echo "🌉 Bridge Service:"
systemctl status chromecast-bridge --no-pager -l
echo
echo "📡 Service Discovery:"
avahi-browse -t _jellyfin._tcp
echo
echo "🌐 Local Access:"
echo "  Jellyfin URL: http://$(hostname -I | awk '{print $1}'):8096"
echo "  Bridge Config: /opt/chromecast-bridge/config.json"
echo "  Service Logs: journalctl -u chromecast-bridge -f"
EOF

chmod +x /usr/local/bin/bridge-status

# Create user instructions
log_step "Creating user instructions..."
cat > /home/pi/CHROMECAST_SETUP.txt << EOF
🎬 Chromecast Jellyfin Bridge Setup Complete!

📱 PHONE/TABLET SETUP:
1. Open the Jellyfin app on your phone/tablet
2. Add server manually: http://$LOCAL_IP:8096
3. Login with your Jellyfin credentials
4. You should now see your Chromecast in the cast menu

📺 CHROMECAST SETUP:
1. Make sure Chromecast is on the same network as this device
2. Chromecast will automatically discover the "local" Jellyfin server
3. No additional setup needed on Chromecast

🔧 MANAGEMENT:
- Check status: bridge-status
- View logs: journalctl -u chromecast-bridge -f
- Restart service: sudo systemctl restart chromecast-bridge
- Configuration: /opt/chromecast-bridge/config.json

🌐 Access URLs:
- Local Jellyfin: http://$LOCAL_IP:8096
- Original Jellyfin: $JELLYFIN_URL

🆘 TROUBLESHOOTING:
- Ensure all devices are on the same network
- Restart Chromecast if it doesn't appear
- Check that this device has internet connectivity
- Verify VPN connection: tailscale status

For support, check the logs or contact your system administrator.
EOF

# Display completion message
echo
echo -e "${GREEN}🎉 Chromecast Bridge Deployment Complete!${NC}"
echo "========================================"
echo
echo -e "${BLUE}📋 Setup Summary:${NC}"
echo "  • Bridge Device IP: $LOCAL_IP"
echo "  • Local Jellyfin URL: http://$LOCAL_IP:8096"
echo "  • VPN Connection: $(tailscale status --self | head -1)"
echo "  • Service Status: $(systemctl is-active chromecast-bridge)"
echo
echo -e "${BLUE}📱 Next Steps:${NC}"
echo "  1. Configure Jellyfin app to use: http://$LOCAL_IP:8096"
echo "  2. Ensure Chromecast is on the same network"
echo "  3. Cast from Jellyfin app as normal"
echo
echo -e "${BLUE}🔧 Management Commands:${NC}"
echo "  • Check status: bridge-status"
echo "  • View logs: journalctl -u chromecast-bridge -f"
echo "  • Restart: sudo systemctl restart chromecast-bridge"
echo
echo -e "${YELLOW}📄 Full instructions saved to: /home/pi/CHROMECAST_SETUP.txt${NC}"
echo

# Final connectivity test
log_step "Performing final connectivity test..."
if curl -s --max-time 5 "http://$LOCAL_IP:8096/System/Info" > /dev/null; then
    log_info "✅ Local bridge is responding"
else
    log_warn "⚠️  Local bridge not responding yet (may need a moment to start)"
fi

echo
echo -e "${GREEN}🚀 Bridge is ready for use!${NC}"
echo "Keep this device powered on for Chromecast access."