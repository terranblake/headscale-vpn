#!/bin/bash
# Start NordVPN connection

set -e

echo "Starting NordVPN connection..."

# Validate environment variables
if [[ -z "$NORDVPN_USER" || -z "$NORDVPN_PASS" ]]; then
    echo "ERROR: NORDVPN_USER and NORDVPN_PASS must be set"
    exit 1
fi

# Create NordVPN auth file
cat > /etc/openvpn/nordvpn-auth.txt << EOF
${NORDVPN_USER}
${NORDVPN_PASS}
EOF
chmod 600 /etc/openvpn/nordvpn-auth.txt

# Select NordVPN server
NORDVPN_SERVER=${NORDVPN_SERVER:-us}
NORDVPN_CONFIG="/etc/openvpn/nordvpn/ovpn_udp/${NORDVPN_SERVER}*.nordvpn.com.udp.ovpn"

# Find the first matching server configuration
SELECTED_CONFIG=$(ls $NORDVPN_CONFIG | head -n 1)

if [[ ! -f "$SELECTED_CONFIG" ]]; then
    echo "ERROR: No NordVPN configuration found for server: $NORDVPN_SERVER"
    echo "Available servers:"
    ls /etc/openvpn/nordvpn/ovpn_udp/ | head -10
    exit 1
fi

echo "Using NordVPN server: $(basename $SELECTED_CONFIG)"

# Create OpenVPN configuration with auth
cp "$SELECTED_CONFIG" /etc/openvpn/nordvpn.conf
echo "auth-user-pass /etc/openvpn/nordvpn-auth.txt" >> /etc/openvpn/nordvpn.conf

# Add custom DNS to prevent leaks
echo "dhcp-option DNS 103.86.96.100" >> /etc/openvpn/nordvpn.conf
echo "dhcp-option DNS 103.86.99.100" >> /etc/openvpn/nordvpn.conf

# Disable default route handling (we'll manage routing ourselves)
echo "route-noexec" >> /etc/openvpn/nordvpn.conf

# Create up/down scripts for custom routing
cat > /etc/openvpn/up.sh << 'EOF'
#!/bin/bash
echo "VPN connected - Interface: $dev, IP: $ifconfig_local, Gateway: $route_vpn_gateway"
echo "$route_vpn_gateway" > /tmp/vpn-gateway
echo "$dev" > /tmp/vpn-interface
EOF

cat > /etc/openvpn/down.sh << 'EOF'
#!/bin/bash
echo "VPN disconnected"
rm -f /tmp/vpn-gateway /tmp/vpn-interface
EOF

chmod +x /etc/openvpn/up.sh /etc/openvpn/down.sh

echo "up /etc/openvpn/up.sh" >> /etc/openvpn/nordvpn.conf
echo "down /etc/openvpn/down.sh" >> /etc/openvpn/nordvpn.conf

# Start OpenVPN
exec openvpn --config /etc/openvpn/nordvpn.conf
