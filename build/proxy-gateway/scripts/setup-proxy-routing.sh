#!/bin/bash
# Setup iptables rules for transparent proxy

set -e

echo "Setting up proxy routing..."

# Get the tailscale interface
while true; do
    TS_INTERFACE=$(ip route | grep '100.64.0.0/10' | head -n1 | awk '{print $3}')
    if [[ -n "$TS_INTERFACE" ]]; then
        echo "Tailscale interface: $TS_INTERFACE"
        break
    fi
    echo "Waiting for Tailscale interface..."
    sleep 5
done

# Get mitmproxy port
MITMPROXY_PORT=${MITMPROXY_PORT:-8080}

# Setup iptables rules for transparent proxy
echo "Setting up iptables rules..."

# Create chain for proxy rules
iptables -t nat -N PROXY_REDIRECT 2>/dev/null || true
iptables -t nat -F PROXY_REDIRECT

# Redirect HTTP traffic to mitmproxy
iptables -t nat -A PROXY_REDIRECT -p tcp --dport 80 -j REDIRECT --to-port "$MITMPROXY_PORT"
iptables -t nat -A PROXY_REDIRECT -p tcp --dport 443 -j REDIRECT --to-port "$MITMPROXY_PORT"

# Don't redirect local traffic
iptables -t nat -I PROXY_REDIRECT -d 127.0.0.0/8 -j RETURN
iptables -t nat -I PROXY_REDIRECT -d 192.168.0.0/16 -j RETURN
iptables -t nat -I PROXY_REDIRECT -d 10.0.0.0/8 -j RETURN
iptables -t nat -I PROXY_REDIRECT -d 172.16.0.0/12 -j RETURN

# Don't redirect traffic from mitmproxy itself
iptables -t nat -I PROXY_REDIRECT -m owner --uid-owner root -j RETURN

# Apply proxy rules to traffic from Tailscale interface
iptables -t nat -A PREROUTING -i "$TS_INTERFACE" -p tcp --dport 80 -j PROXY_REDIRECT
iptables -t nat -A PREROUTING -i "$TS_INTERFACE" -p tcp --dport 443 -j PROXY_REDIRECT

# Allow forwarding
iptables -A FORWARD -i "$TS_INTERFACE" -j ACCEPT
iptables -A FORWARD -o "$TS_INTERFACE" -j ACCEPT

echo "Proxy routing setup complete"

# Monitor and maintain rules
while true; do
    sleep 60
    
    # Check if Tailscale is still running
    if ! /usr/local/bin/tailscale status >/dev/null 2>&1; then
        echo "Tailscale connection lost, restarting..."
        exit 1
    fi
    
    # Check if mitmproxy is still running
    if ! pgrep -f mitmdump >/dev/null; then
        echo "mitmproxy not running, restarting..."
        exit 1
    fi
done
