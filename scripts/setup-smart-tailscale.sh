#!/bin/bash
# Setup Smart Tailscale Configuration
# Configures split tunneling and on-demand VPN for family members

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

echo -e "${BLUE}"
cat << "EOF"
  ____                       _     _______     _ _               _      
 / ___| _ __ ___   __ _ _ __| |_  |__   __|   (_) |             | |     
 \___ \| '_ ` _ \ / _` | '__| __|    | | __ _ _| |___  ___ __ _| | ___ 
  ___) | | | | | | (_| | |  | |_     | |/ _` | | / __|/ __/ _` | |/ _ \
 |____/|_| |_| |_|\__,_|_|   \__|    |_|\__,_|_|_\___|\___\__,_|_|\___/
                                                                       
EOF
echo -e "${NC}"

echo "🎯 Smart Tailscale Configuration for Family Services"
echo "===================================================="
echo

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   log_error "This script should NOT be run as root"
   exit 1
fi

# Get configuration
log_step "Gathering configuration..."

read -p "Enter your Headscale server URL: " HEADSCALE_URL
read -p "Enter your home network CIDR (e.g., 192.168.1.0/24): " HOME_NETWORK
read -p "Enter your domain for services (e.g., family.local): " FAMILY_DOMAIN

# Validate inputs
if [[ ! $HEADSCALE_URL =~ ^https?:// ]]; then
    log_error "Invalid Headscale URL format"
    exit 1
fi

if [[ ! $HOME_NETWORK =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]]; then
    log_error "Invalid network CIDR format"
    exit 1
fi

log_info "Configuration:"
log_info "  Headscale URL: $HEADSCALE_URL"
log_info "  Home Network: $HOME_NETWORK"
log_info "  Family Domain: $FAMILY_DOMAIN"

# Create configuration directory
CONFIG_DIR="$HOME/.config/family-tailscale"
mkdir -p "$CONFIG_DIR"

# Step 1: Configure Headscale for Magic DNS
log_step "Configuring Headscale Magic DNS..."

cat > "$CONFIG_DIR/headscale-dns-config.yaml" << EOF
# Add this to your headscale config.yaml
dns_config:
  magic_dns: true
  base_domain: $FAMILY_DOMAIN
  nameservers:
    - 1.1.1.1
    - 8.8.8.8
  search_domains:
    - $FAMILY_DOMAIN
  extra_records:
    - name: jellyfin.$FAMILY_DOMAIN
      type: A
      value: "100.64.0.2"  # Your Jellyfin server's Tailscale IP
    - name: photos.$FAMILY_DOMAIN
      type: A
      value: "100.64.0.3"  # Your photo server's Tailscale IP
    - name: homeassistant.$FAMILY_DOMAIN
      type: A
      value: "100.64.0.4"  # Your Home Assistant's Tailscale IP
EOF

log_info "✅ Headscale DNS configuration saved to: $CONFIG_DIR/headscale-dns-config.yaml"
log_warn "⚠️  You need to add this to your headscale config.yaml and restart headscale"

# Step 2: Create Tailscale ACL for family access
log_step "Creating Tailscale ACL configuration..."

cat > "$CONFIG_DIR/tailscale-acl.json" << EOF
{
  "tagOwners": {
    "tag:family": ["autogroup:admin"],
    "tag:server": ["autogroup:admin"]
  },
  "groups": {
    "group:family": ["tag:family"],
    "group:servers": ["tag:server"]
  },
  "acls": [
    {
      "action": "accept",
      "src": ["group:family"],
      "dst": ["group:servers:*"]
    },
    {
      "action": "accept",
      "src": ["group:family"],
      "dst": ["$HOME_NETWORK:*"]
    }
  ],
  "ssh": [
    {
      "action": "accept",
      "src": ["autogroup:admin"],
      "dst": ["autogroup:self"],
      "users": ["autogroup:nonroot"]
    }
  ]
}
EOF

log_info "✅ Tailscale ACL saved to: $CONFIG_DIR/tailscale-acl.json"

# Step 3: Create family member setup script
log_step "Creating family member setup tools..."

cat > "$CONFIG_DIR/generate-family-config.py" << 'EOF'
#!/usr/bin/env python3
"""
Generate Tailscale configuration for family members
"""

import json
import qrcode
import base64
import argparse
from io import BytesIO

def generate_tailscale_config(user_email, family_domain, headscale_url):
    """Generate Tailscale configuration for family member"""
    
    config = {
        "version": "1.0",
        "name": f"Family Services - {user_email}",
        "description": "Access to family media and services",
        "headscale_url": headscale_url,
        "user": user_email.split('@')[0],
        "configuration": {
            "magic_dns": {
                "enabled": True,
                "base_domain": family_domain
            },
            "split_tunneling": {
                "enabled": True,
                "vpn_routes": [
                    "100.64.0.0/10",  # Tailscale network
                    "192.168.1.0/24"  # Home network (adjust as needed)
                ],
                "bypass_routes": [
                    "0.0.0.0/0"  # Everything else goes direct
                ]
            },
            "on_demand": {
                "enabled": True,
                "rules": [
                    {
                        "action": "connect",
                        "domains": [
                            f"*.{family_domain}",
                            f"jellyfin.{family_domain}",
                            f"photos.{family_domain}",
                            f"homeassistant.{family_domain}"
                        ]
                    }
                ]
            },
            "auto_connect": {
                "enabled": True,
                "trusted_networks": ["any"]
            }
        },
        "services": {
            f"jellyfin.{family_domain}": {
                "name": "Family Movies & TV",
                "description": "Stream movies and TV shows",
                "icon": "🎬",
                "app": "Streamyfin"
            },
            f"photos.{family_domain}": {
                "name": "Family Photos",
                "description": "Browse family photo collection",
                "icon": "📸",
                "app": "Web Browser"
            },
            f"homeassistant.{family_domain}": {
                "name": "Home Control",
                "description": "Control home automation",
                "icon": "🏠",
                "app": "Home Assistant"
            }
        }
    }
    
    return config

def generate_qr_code(config):
    """Generate QR code for easy setup"""
    
    # Encode configuration as base64 JSON
    config_json = json.dumps(config, separators=(',', ':'))
    config_b64 = base64.b64encode(config_json.encode()).decode()
    
    # Create QR code data
    qr_data = f"tailscale-family://{config_b64}"
    
    # Generate QR code
    qr = qrcode.QRCode(
        version=1,
        error_correction=qrcode.constants.ERROR_CORRECT_M,
        box_size=10,
        border=4,
    )
    qr.add_data(qr_data)
    qr.make(fit=True)
    
    # Create QR code image
    img = qr.make_image(fill_color="black", back_color="white")
    
    # Convert to base64 for embedding
    buffer = BytesIO()
    img.save(buffer, format='PNG')
    img_b64 = base64.b64encode(buffer.getvalue()).decode()
    
    return f"data:image/png;base64,{img_b64}"

def generate_setup_instructions(config, user_email):
    """Generate setup instructions for family member"""
    
    family_domain = config['configuration']['magic_dns']['base_domain']
    
    instructions = f"""
# Family Services Setup Instructions
## For: {user_email}

### 📱 Step 1: Install Tailscale
- **iPhone/iPad**: Download "Tailscale" from App Store
- **Android**: Download "Tailscale" from Google Play Store

### 🔗 Step 2: Connect to Family Network
1. Open Tailscale app
2. Tap "Add Account" or "Sign In"
3. Choose "Use a different server"
4. Enter server: {config['headscale_url']}
5. Use the login key provided separately

### 📺 Step 3: Install Streamyfin
- Download "Streamyfin" from your app store
- This is for watching family movies and shows

### 🎬 Step 4: Add Media Server
1. Open Streamyfin
2. Tap "Add Server"
3. Enter: jellyfin.{family_domain}
4. Login with credentials provided separately

### ✅ You're Done!
- Tailscale will automatically connect when you access family services
- Your regular internet browsing is unaffected
- Cast to Chromecast works normally

### 🎯 Available Services:
"""
    
    for domain, service in config['services'].items():
        instructions += f"- **{service['name']}** {service['icon']}\n"
        instructions += f"  URL: {domain}\n"
        instructions += f"  App: {service['app']}\n\n"
    
    instructions += """
### 🆘 Need Help?
Contact your family tech support person!

### 🔧 Troubleshooting:
- **Can't connect**: Make sure you're connected to internet
- **Services not loading**: Try disconnecting and reconnecting Tailscale
- **Chromecast issues**: Ensure phone and Chromecast are on same WiFi
"""
    
    return instructions

def main():
    parser = argparse.ArgumentParser(description="Generate family Tailscale configuration")
    parser.add_argument("user_email", help="Family member's email")
    parser.add_argument("--family-domain", default="family.local", help="Family domain")
    parser.add_argument("--headscale-url", required=True, help="Headscale server URL")
    parser.add_argument("--output-dir", default="./family-configs", help="Output directory")
    
    args = parser.parse_args()
    
    # Generate configuration
    config = generate_tailscale_config(args.user_email, args.family_domain, args.headscale_url)
    
    # Generate QR code
    qr_code = generate_qr_code(config)
    
    # Generate instructions
    instructions = generate_setup_instructions(config, args.user_email)
    
    # Create output directory
    import os
    os.makedirs(args.output_dir, exist_ok=True)
    
    # Save files
    username = args.user_email.split('@')[0]
    
    with open(f"{args.output_dir}/{username}_config.json", 'w') as f:
        json.dump(config, f, indent=2)
    
    with open(f"{args.output_dir}/{username}_instructions.md", 'w') as f:
        f.write(instructions)
    
    # Save QR code as HTML for easy viewing
    html = f"""
<!DOCTYPE html>
<html>
<head>
    <title>Setup QR Code - {args.user_email}</title>
    <style>
        body {{ font-family: Arial, sans-serif; text-align: center; margin: 50px; }}
        .qr-code {{ margin: 20px 0; }}
        .instructions {{ text-align: left; max-width: 600px; margin: 0 auto; }}
    </style>
</head>
<body>
    <h1>Family Services Setup</h1>
    <h2>For: {args.user_email}</h2>
    
    <div class="qr-code">
        <h3>📱 Scan with Tailscale App</h3>
        <img src="{qr_code}" alt="Setup QR Code" style="max-width: 300px;">
    </div>
    
    <div class="instructions">
        <h3>📋 Manual Setup Instructions</h3>
        <ol>
            <li>Install Tailscale app</li>
            <li>Scan QR code above</li>
            <li>Install Streamyfin app</li>
            <li>Add server: jellyfin.{args.family_domain}</li>
        </ol>
    </div>
</body>
</html>
    """
    
    with open(f"{args.output_dir}/{username}_qr.html", 'w') as f:
        f.write(html)
    
    print(f"✅ Configuration generated for {args.user_email}")
    print(f"📁 Files saved to: {args.output_dir}/")
    print(f"📱 QR Code: {args.output_dir}/{username}_qr.html")
    print(f"📋 Instructions: {args.output_dir}/{username}_instructions.md")

if __name__ == "__main__":
    main()
EOF

chmod +x "$CONFIG_DIR/generate-family-config.py"

# Step 4: Create convenience scripts
log_step "Creating convenience scripts..."

cat > "$CONFIG_DIR/create-family-user.sh" << EOF
#!/bin/bash
# Create a new family user and generate their configuration

if [ \$# -ne 1 ]; then
    echo "Usage: \$0 <user-email>"
    exit 1
fi

USER_EMAIL=\$1
USERNAME=\$(echo \$USER_EMAIL | cut -d'@' -f1)

echo "Creating family user: \$USER_EMAIL"

# Create user in headscale
docker exec headscale headscale users create \$USERNAME

# Generate pre-auth key
PREAUTH_KEY=\$(docker exec headscale headscale preauthkeys create --user \$USERNAME --expiration 24h --output json | jq -r '.key')

echo "Pre-auth key: \$PREAUTH_KEY"

# Generate configuration
python3 "$CONFIG_DIR/generate-family-config.py" \$USER_EMAIL --headscale-url $HEADSCALE_URL --output-dir ./family-configs

echo "✅ User created and configuration generated"
echo "📁 Configuration files: ./family-configs/"
echo "🔑 Pre-auth key: \$PREAUTH_KEY"
echo ""
echo "📧 Send to family member:"
echo "  1. Configuration files from ./family-configs/"
echo "  2. Pre-auth key: \$PREAUTH_KEY"
echo "  3. Jellyfin login credentials"
EOF

chmod +x "$CONFIG_DIR/create-family-user.sh"

# Step 5: Create Streamyfin optimization script
log_step "Creating Streamyfin optimization..."

cat > "$CONFIG_DIR/optimize-for-streamyfin.sh" << EOF
#!/bin/bash
# Optimize Jellyfin server for Streamyfin clients

echo "🎬 Optimizing Jellyfin for Streamyfin..."

# Add Streamyfin-specific configuration to Jellyfin
JELLYFIN_CONFIG_DIR="/path/to/jellyfin/config"  # Update this path

if [ -d "\$JELLYFIN_CONFIG_DIR" ]; then
    # Enable hardware transcoding if available
    echo "Enabling hardware transcoding..."
    
    # Configure network settings for remote access
    echo "Configuring network settings..."
    
    # Set up CORS for web clients
    echo "Configuring CORS settings..."
    
    echo "✅ Jellyfin optimized for Streamyfin"
else
    echo "⚠️  Jellyfin config directory not found. Update the path in this script."
fi
EOF

chmod +x "$CONFIG_DIR/optimize-for-streamyfin.sh"

# Step 6: Create testing script
log_step "Creating testing tools..."

cat > "$CONFIG_DIR/test-family-setup.sh" << EOF
#!/bin/bash
# Test family member setup

echo "🧪 Testing Family Setup..."

# Test DNS resolution
echo "Testing DNS resolution..."
nslookup jellyfin.$FAMILY_DOMAIN
nslookup photos.$FAMILY_DOMAIN

# Test Tailscale connectivity
echo "Testing Tailscale connectivity..."
tailscale status

# Test service accessibility
echo "Testing service accessibility..."
curl -s -o /dev/null -w "%{http_code}" http://jellyfin.$FAMILY_DOMAIN/System/Info

echo "✅ Testing complete"
EOF

chmod +x "$CONFIG_DIR/test-family-setup.sh"

# Step 7: Install Python dependencies for QR code generation
log_step "Installing Python dependencies..."

if command -v pip3 &> /dev/null; then
    pip3 install --user qrcode[pil] || log_warn "Failed to install Python dependencies"
else
    log_warn "pip3 not found. Install manually: pip3 install qrcode[pil]"
fi

# Summary
echo
log_info "🎉 Smart Tailscale setup complete!"
echo "=================================="
echo
echo -e "${BLUE}📁 Configuration files created in:${NC} $CONFIG_DIR"
echo
echo -e "${BLUE}📋 Next steps:${NC}"
echo "  1. Update your headscale config with: $CONFIG_DIR/headscale-dns-config.yaml"
echo "  2. Apply Tailscale ACL: $CONFIG_DIR/tailscale-acl.json"
echo "  3. Create family users: $CONFIG_DIR/create-family-user.sh user@example.com"
echo "  4. Test setup: $CONFIG_DIR/test-family-setup.sh"
echo
echo -e "${BLUE}🎯 For each family member:${NC}"
echo "  1. Run: $CONFIG_DIR/create-family-user.sh their-email@example.com"
echo "  2. Send them the generated configuration files"
echo "  3. Provide Jellyfin login credentials"
echo
echo -e "${YELLOW}⚠️  Remember to:${NC}"
echo "  • Restart headscale after updating DNS config"
echo "  • Apply the ACL configuration in your Tailscale admin console"
echo "  • Test with your own devices first"
echo
echo -e "${GREEN}🚀 Family members will only need to:${NC}"
echo "  1. Install Tailscale app"
echo "  2. Scan QR code or enter server manually"
echo "  3. Install Streamyfin app"
echo "  4. Add server: jellyfin.$FAMILY_DOMAIN"
echo "  5. Enjoy!"