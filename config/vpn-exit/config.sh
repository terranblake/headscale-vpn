# VPN Exit Node Configuration

# NordVPN server preferences
# Available regions: us, uk, de, nl, ca, au, jp, etc.
NORDVPN_REGION=us

# Bypass domains (direct connection, no VPN)
bypass_domains=(
    "*.local"
    "*.internal" 
    "*.lan"
    "localhost"
    "example.com"
)

# Bypass IP ranges (direct connection, no VPN)
bypass_ips=(
    "192.168.0.0/16"
    "10.0.0.0/8"
    "172.16.0.0/12"
    "127.0.0.0/8"
)

# DNS servers for VPN traffic (NordVPN DNS)
vpn_dns=(
    "103.86.96.100"
    "103.86.99.100"
)

# DNS servers for bypass traffic
bypass_dns=(
    "1.1.1.1"
    "8.8.8.8"
)
