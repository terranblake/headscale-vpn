#!/bin/bash
# Manage routing and bypass rules for the VPN exit node

set -e

echo "Starting routing manager..."

# Function to parse bypass lists
parse_bypass_domains() {
    if [[ -n "$BYPASS_DOMAINS" ]]; then
        echo "$BYPASS_DOMAINS" | tr ',' '\n' | while read -r domain; do
            [[ -n "$domain" ]] && echo "$domain"
        done
    fi
}

parse_bypass_ips() {
    if [[ -n "$BYPASS_IPS" ]]; then
        echo "$BYPASS_IPS" | tr ',' '\n' | while read -r ip; do
            [[ -n "$ip" ]] && echo "$ip"
        done
    fi
}

# Function to resolve domains to IPs
resolve_domain() {
    local domain="$1"
    # Use multiple DNS servers for reliability
    dig +short @1.1.1.1 "$domain" A | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -5
    dig +short @8.8.8.8 "$domain" A | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -5
}

# Function to setup routing tables
setup_routing() {
    echo "Setting up routing tables..."
    
    # Get the tailscale interface
    TS_INTERFACE=$(ip route | grep '100.64.0.0/10' | head -n1 | awk '{print $3}')
    if [[ -z "$TS_INTERFACE" ]]; then
        echo "Waiting for Tailscale interface..."
        return 1
    fi
    
    echo "Tailscale interface: $TS_INTERFACE"
    
    # Wait for VPN connection
    while [[ ! -f /tmp/vpn-gateway ]]; do
        echo "Waiting for VPN connection..."
        sleep 5
    done
    
    VPN_GATEWAY=$(cat /tmp/vpn-gateway)
    VPN_INTERFACE=$(cat /tmp/vpn-interface)
    
    echo "VPN Gateway: $VPN_GATEWAY via $VPN_INTERFACE"
    
    # Create custom routing table for VPN traffic
    if ! grep -q "200 vpn" /etc/iproute2/rt_tables; then
        echo "200 vpn" >> /etc/iproute2/rt_tables
    fi
    
    # Default route for VPN traffic
    ip route add default via "$VPN_GATEWAY" dev "$VPN_INTERFACE" table vpn || true
    
    # Route all Tailscale traffic through VPN by default
    ip rule add from 100.64.0.0/10 table vpn priority 100 || true
    
    # Setup bypass rules for specified IPs
    parse_bypass_ips | while read -r ip_range; do
        [[ -n "$ip_range" ]] && {
            echo "Adding bypass rule for IP range: $ip_range"
            ip rule add to "$ip_range" table main priority 50 || true
        }
    done
    
    # Setup bypass rules for specified domains
    parse_bypass_domains | while read -r domain; do
        [[ -n "$domain" ]] && {
            echo "Resolving bypass domain: $domain"
            resolve_domain "$domain" | while read -r ip; do
                [[ -n "$ip" ]] && {
                    echo "Adding bypass rule for $domain -> $ip"
                    ip rule add to "$ip" table main priority 50 || true
                }
            done
        }
    done
    
    # Setup NAT for exit node functionality
    iptables -t nat -A POSTROUTING -o "$VPN_INTERFACE" -j MASQUERADE || true
    iptables -A FORWARD -i "$TS_INTERFACE" -o "$VPN_INTERFACE" -j ACCEPT || true
    iptables -A FORWARD -i "$VPN_INTERFACE" -o "$TS_INTERFACE" -m state --state RELATED,ESTABLISHED -j ACCEPT || true
    
    # Allow local traffic to bypass VPN
    iptables -t nat -I POSTROUTING -d 192.168.0.0/16 -j ACCEPT || true
    iptables -t nat -I POSTROUTING -d 10.0.0.0/8 -j ACCEPT || true
    iptables -t nat -I POSTROUTING -d 172.16.0.0/12 -j ACCEPT || true
    
    echo "Routing setup complete"
}

# Function to update bypass rules periodically
update_bypass_rules() {
    while true; do
        sleep 300  # Update every 5 minutes
        echo "Updating bypass rules..."
        
        # Re-resolve domains and update rules
        parse_bypass_domains | while read -r domain; do
            [[ -n "$domain" ]] && {
                resolve_domain "$domain" | while read -r ip; do
                    [[ -n "$ip" ]] && {
                        # Check if rule already exists
                        if ! ip rule list | grep -q "to $ip"; then
                            echo "Adding new bypass rule for $domain -> $ip"
                            ip rule add to "$ip" table main priority 50 || true
                        fi
                    }
                done
            }
        done
    done
}

# Main execution
while true; do
    if setup_routing; then
        echo "Routing setup successful, starting background updates..."
        update_bypass_rules &
        
        # Monitor and maintain routing
        while true; do
            sleep 30
            
            # Check if VPN is still connected
            if [[ ! -f /tmp/vpn-gateway ]]; then
                echo "VPN connection lost, restarting setup..."
                break
            fi
            
            # Check if Tailscale is still running
            if ! /usr/local/bin/tailscale status >/dev/null 2>&1; then
                echo "Tailscale connection lost, restarting setup..."
                break
            fi
        done
        
        # Kill background update process
        jobs -p | xargs -r kill
    else
        echo "Routing setup failed, retrying in 10 seconds..."
        sleep 10
    fi
done
