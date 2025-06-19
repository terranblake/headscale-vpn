#!/bin/bash

# Mobile Configuration Generator
# Creates device-specific configuration files for easy family member setup

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_FILE="/var/log/family-network-mobile-config.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

# Help function
show_help() {
    cat << EOF
Mobile Configuration Generator

Usage: $0 [OPTIONS]

OPTIONS:
    -u, --username USER     Username for configuration (required)
    -d, --device DEVICE     Device type: ios, android, windows, mac, linux (required)
    -n, --name NAME         Device name (optional, defaults to username-device)
    -o, --output DIR        Output directory (default: config/mobile-configs)
    --qr                    Generate QR code for easy mobile setup
    --email                 Generate email with setup instructions
    --all-devices           Generate configs for all device types
    -h, --help              Show this help message

EXAMPLES:
    # Generate iOS config for user
    $0 --username john --device ios

    # Generate Android config with QR code
    $0 --username emma --device android --qr

    # Generate configs for all devices
    $0 --username sarah --all-devices

    # Generate with custom output directory
    $0 --username mike --device windows --output /tmp/configs

EOF
}

# Default values
USERNAME=""
DEVICE=""
DEVICE_NAME=""
OUTPUT_DIR="$PROJECT_DIR/config/mobile-configs"
GENERATE_QR=false
GENERATE_EMAIL=false
ALL_DEVICES=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -u|--username)
            USERNAME="$2"
            shift 2
            ;;
        -d|--device)
            DEVICE="$2"
            shift 2
            ;;
        -n|--name)
            DEVICE_NAME="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --qr)
            GENERATE_QR=true
            shift
            ;;
        --email)
            GENERATE_EMAIL=true
            shift
            ;;
        --all-devices)
            ALL_DEVICES=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Validate required parameters
if [[ -z "$USERNAME" ]]; then
    error "Username is required"
    show_help
    exit 1
fi

if [[ "$ALL_DEVICES" == false && -z "$DEVICE" ]]; then
    error "Device type is required (or use --all-devices)"
    show_help
    exit 1
fi

# Check if user exists
USER_CONFIG="$PROJECT_DIR/config/users/${USERNAME}.yaml"
if [[ ! -f "$USER_CONFIG" ]]; then
    error "User $USERNAME does not exist. Create user first with create-family-user.sh"
    exit 1
fi

# Load user information
load_user_info() {
    if command -v yq >/dev/null 2>&1; then
        USER_NAME=$(yq eval '.user.name' "$USER_CONFIG" 2>/dev/null || echo "$USERNAME")
        USER_EMAIL=$(yq eval '.user.email' "$USER_CONFIG" 2>/dev/null || echo "${USERNAME}@family.local")
        USER_TYPE=$(yq eval '.user.type' "$USER_CONFIG" 2>/dev/null || echo "member")
    else
        # Fallback parsing
        USER_NAME=$(grep 'name:' "$USER_CONFIG" | head -1 | sed 's/.*name: *"\([^"]*\)".*/\1/' || echo "$USERNAME")
        USER_EMAIL=$(grep 'email:' "$USER_CONFIG" | head -1 | sed 's/.*email: *"\([^"]*\)".*/\1/' || echo "${USERNAME}@family.local")
        USER_TYPE=$(grep 'type:' "$USER_CONFIG" | head -1 | sed 's/.*type: *"\([^"]*\)".*/\1/' || echo "member")
    fi
}

# Get server configuration
get_server_config() {
    # Try to get server info from headscale config or environment
    if [[ -f "$PROJECT_DIR/.env" ]]; then
        source "$PROJECT_DIR/.env"
    fi
    
    SERVER_URL="${HEADSCALE_SERVER_URL:-https://vpn.family.local}"
    SERVER_NAME="${HEADSCALE_SERVER_NAME:-family-network}"
    
    # Try to get from headscale config
    if [[ -f "$PROJECT_DIR/config/headscale/config.yaml" ]]; then
        if command -v yq >/dev/null 2>&1; then
            SERVER_URL=$(yq eval '.server_url' "$PROJECT_DIR/config/headscale/config.yaml" 2>/dev/null || echo "$SERVER_URL")
        fi
    fi
}

# Generate pre-auth key
generate_preauth_key() {
    local expiration="${1:-24h}"
    
    if command -v headscale >/dev/null 2>&1; then
        headscale preauthkeys create --user "$USERNAME" --expiration "$expiration" --output json 2>/dev/null | jq -r '.key' || echo ""
    else
        warning "Headscale not available, using placeholder key"
        echo "PLACEHOLDER_PREAUTH_KEY_${USERNAME}_$(date +%s)"
    fi
}

# Generate iOS configuration
generate_ios_config() {
    local device_name="${DEVICE_NAME:-${USERNAME}-iphone}"
    local output_file="$OUTPUT_DIR/${USERNAME}-ios.mobileconfig"
    local preauth_key
    
    preauth_key=$(generate_preauth_key "7d")
    
    mkdir -p "$OUTPUT_DIR"
    
    cat > "$output_file" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>PayloadContent</key>
    <array>
        <dict>
            <key>PayloadDisplayName</key>
            <string>Family Network VPN</string>
            <key>PayloadIdentifier</key>
            <string>com.family.vpn.${USERNAME}</string>
            <key>PayloadType</key>
            <string>com.apple.vpn.managed</string>
            <key>PayloadUUID</key>
            <string>$(uuidgen)</string>
            <key>PayloadVersion</key>
            <integer>1</integer>
            <key>UserDefinedName</key>
            <string>Family Network</string>
            <key>VPNType</key>
            <string>IKEv2</string>
            <key>IKEv2</key>
            <dict>
                <key>AuthenticationMethod</key>
                <string>Certificate</string>
                <key>ChildSecurityAssociationParameters</key>
                <dict>
                    <key>EncryptionAlgorithm</key>
                    <string>AES-256</string>
                    <key>IntegrityAlgorithm</key>
                    <string>SHA2-256</string>
                    <key>DiffieHellmanGroup</key>
                    <integer>14</integer>
                </dict>
                <key>IKESecurityAssociationParameters</key>
                <dict>
                    <key>EncryptionAlgorithm</key>
                    <string>AES-256</string>
                    <key>IntegrityAlgorithm</key>
                    <string>SHA2-256</string>
                    <key>DiffieHellmanGroup</key>
                    <integer>14</integer>
                </dict>
                <key>RemoteAddress</key>
                <string>$SERVER_URL</string>
                <key>RemoteIdentifier</key>
                <string>$SERVER_NAME</string>
                <key>LocalIdentifier</key>
                <string>$USERNAME</string>
            </dict>
        </dict>
    </array>
    <key>PayloadDisplayName</key>
    <string>Family Network VPN Configuration</string>
    <key>PayloadIdentifier</key>
    <string>com.family.vpn.${USERNAME}.profile</string>
    <key>PayloadRemovalDisallowed</key>
    <false/>
    <key>PayloadType</key>
    <string>Configuration</string>
    <key>PayloadUUID</key>
    <string>$(uuidgen)</string>
    <key>PayloadVersion</key>
    <integer>1</integer>
</dict>
</plist>
EOF

    # Create setup instructions
    cat > "$OUTPUT_DIR/${USERNAME}-ios-setup.txt" << EOF
iOS Setup Instructions for $USER_NAME
=====================================

1. INSTALL TAILSCALE APP:
   - Open App Store on your iPhone/iPad
   - Search for "Tailscale"
   - Install the official Tailscale app

2. SETUP FAMILY NETWORK:
   - Open Tailscale app
   - Tap "Sign in"
   - Choose "Use a different server"
   - Enter server URL: $SERVER_URL
   - Use pre-auth key: $preauth_key

3. ALTERNATIVE SETUP (if pre-auth doesn't work):
   - Username: $USERNAME
   - Password: [Check your welcome email]

4. VERIFY CONNECTION:
   - Look for "Connected" status in Tailscale app
   - Open Safari and go to: https://family.local
   - You should see the family dashboard

Pre-auth key expires in 7 days.
Generated on: $(date)
EOF

    success "Generated iOS configuration: $output_file"
}

# Generate Android configuration
generate_android_config() {
    local device_name="${DEVICE_NAME:-${USERNAME}-android}"
    local output_file="$OUTPUT_DIR/${USERNAME}-android-setup.txt"
    local preauth_key
    
    preauth_key=$(generate_preauth_key "7d")
    
    mkdir -p "$OUTPUT_DIR"
    
    cat > "$output_file" << EOF
Android Setup Instructions for $USER_NAME
==========================================

1. INSTALL TAILSCALE APP:
   - Open Google Play Store
   - Search for "Tailscale"
   - Install the official Tailscale app

2. SETUP FAMILY NETWORK:
   - Open Tailscale app
   - Tap "Sign in"
   - Choose "Use a different server"
   - Enter server URL: $SERVER_URL
   - Use pre-auth key: $preauth_key

3. ALTERNATIVE SETUP (if pre-auth doesn't work):
   - Username: $USERNAME
   - Password: [Check your welcome email]

4. VERIFY CONNECTION:
   - Look for "Connected" status in Tailscale app
   - Open Chrome and go to: https://family.local
   - You should see the family dashboard

5. OPTIONAL - ADD TO HOME SCREEN:
   - In Chrome, go to https://family.local
   - Tap the menu (three dots)
   - Select "Add to Home screen"
   - Name it "Family Network"

Pre-auth key expires in 7 days.
Generated on: $(date)

TROUBLESHOOTING:
- If connection fails, try turning WiFi off and on
- Make sure you're connected to internet
- Check that the pre-auth key hasn't expired
EOF

    success "Generated Android setup instructions: $output_file"
}

# Generate Windows configuration
generate_windows_config() {
    local device_name="${DEVICE_NAME:-${USERNAME}-windows}"
    local output_file="$OUTPUT_DIR/${USERNAME}-windows-setup.txt"
    local preauth_key
    
    preauth_key=$(generate_preauth_key "7d")
    
    mkdir -p "$OUTPUT_DIR"
    
    cat > "$output_file" << EOF
Windows Setup Instructions for $USER_NAME
==========================================

1. DOWNLOAD TAILSCALE:
   - Go to: https://tailscale.com/download/windows
   - Download and install Tailscale for Windows
   - Run the installer as Administrator

2. SETUP FAMILY NETWORK:
   - Open Tailscale from the system tray (bottom right)
   - Click "Sign in"
   - Choose "Use a different server"
   - Enter server URL: $SERVER_URL
   - Use pre-auth key: $preauth_key

3. ALTERNATIVE SETUP (if pre-auth doesn't work):
   - Username: $USERNAME
   - Password: [Check your welcome email]

4. VERIFY CONNECTION:
   - Look for Tailscale icon in system tray
   - Icon should be solid (not grayed out)
   - Open web browser and go to: https://family.local
   - You should see the family dashboard

5. CREATE DESKTOP SHORTCUTS:
   - Right-click on desktop
   - New > Shortcut
   - Enter: https://family.local
   - Name it "Family Network"

Pre-auth key expires in 7 days.
Generated on: $(date)

TROUBLESHOOTING:
- Run Tailscale as Administrator if connection fails
- Check Windows Firewall settings
- Restart computer if installation seems incomplete
- Make sure Windows is up to date
EOF

    success "Generated Windows setup instructions: $output_file"
}

# Generate macOS configuration
generate_mac_config() {
    local device_name="${DEVICE_NAME:-${USERNAME}-mac}"
    local output_file="$OUTPUT_DIR/${USERNAME}-mac-setup.txt"
    local preauth_key
    
    preauth_key=$(generate_preauth_key "7d")
    
    mkdir -p "$OUTPUT_DIR"
    
    cat > "$output_file" << EOF
macOS Setup Instructions for $USER_NAME
========================================

1. DOWNLOAD TAILSCALE:
   - Go to: https://tailscale.com/download/mac
   - Download Tailscale for Mac
   - Open the .dmg file and drag Tailscale to Applications

2. SETUP FAMILY NETWORK:
   - Open Tailscale from Applications or menu bar
   - Click "Sign in"
   - Choose "Use a different server"
   - Enter server URL: $SERVER_URL
   - Use pre-auth key: $preauth_key

3. ALTERNATIVE SETUP (if pre-auth doesn't work):
   - Username: $USERNAME
   - Password: [Check your welcome email]

4. VERIFY CONNECTION:
   - Look for Tailscale icon in menu bar (top right)
   - Icon should show "Connected"
   - Open Safari and go to: https://family.local
   - You should see the family dashboard

5. ADD TO DOCK:
   - Open Safari and go to: https://family.local
   - Drag the URL from address bar to Dock
   - Rename to "Family Network"

Pre-auth key expires in 7 days.
Generated on: $(date)

TROUBLESHOOTING:
- Allow Tailscale in System Preferences > Security & Privacy
- Check Network settings if connection fails
- Restart Tailscale from menu bar if needed
- Make sure macOS is up to date
EOF

    success "Generated macOS setup instructions: $output_file"
}

# Generate Linux configuration
generate_linux_config() {
    local device_name="${DEVICE_NAME:-${USERNAME}-linux}"
    local output_file="$OUTPUT_DIR/${USERNAME}-linux-setup.txt"
    local preauth_key
    
    preauth_key=$(generate_preauth_key "7d")
    
    mkdir -p "$OUTPUT_DIR"
    
    cat > "$output_file" << EOF
Linux Setup Instructions for $USER_NAME
========================================

1. INSTALL TAILSCALE:
   
   Ubuntu/Debian:
   curl -fsSL https://tailscale.com/install.sh | sh
   
   Fedora/CentOS:
   sudo dnf install tailscale
   
   Arch Linux:
   sudo pacman -S tailscale

2. START TAILSCALE SERVICE:
   sudo systemctl enable --now tailscaled

3. SETUP FAMILY NETWORK:
   sudo tailscale up --login-server=$SERVER_URL --authkey=$preauth_key

4. ALTERNATIVE SETUP (if pre-auth doesn't work):
   sudo tailscale up --login-server=$SERVER_URL
   # Then follow the authentication URL with:
   # Username: $USERNAME
   # Password: [Check your welcome email]

5. VERIFY CONNECTION:
   tailscale status
   # Should show "Connected"
   
   # Test family network access:
   curl -k https://family.local
   # Should return HTML content

6. CREATE DESKTOP SHORTCUT:
   cat > ~/Desktop/family-network.desktop << 'EOL'
[Desktop Entry]
Version=1.0
Type=Application
Name=Family Network
Comment=Access family services
Exec=xdg-open https://family.local
Icon=network-workgroup
Terminal=false
Categories=Network;
EOL
   chmod +x ~/Desktop/family-network.desktop

Pre-auth key expires in 7 days.
Generated on: $(date)

TROUBLESHOOTING:
- Check firewall settings: sudo ufw allow in on tailscale0
- Restart tailscale: sudo systemctl restart tailscaled
- Check logs: sudo journalctl -u tailscaled
- Make sure system is up to date
EOF

    success "Generated Linux setup instructions: $output_file"
}

# Generate QR code for mobile setup
generate_qr_code() {
    local config_text="$1"
    local output_file="$2"
    
    if command -v qrencode >/dev/null 2>&1; then
        echo "$config_text" | qrencode -o "$output_file" -s 8
        success "Generated QR code: $output_file"
    else
        warning "qrencode not installed, skipping QR code generation"
        log "Install qrencode with: sudo apt install qrencode (Ubuntu/Debian)"
    fi
}

# Generate setup email
generate_setup_email() {
    local email_file="$OUTPUT_DIR/${USERNAME}-setup-email.html"
    
    cat > "$email_file" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Family Network Device Setup</title>
    <style>
        body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
        .header { background: #2196F3; color: white; padding: 20px; text-align: center; }
        .content { padding: 20px; }
        .device-section { background: #f9f9f9; border-left: 4px solid #2196F3; padding: 15px; margin: 20px 0; }
        .button { background: #2196F3; color: white; padding: 10px 20px; text-decoration: none; border-radius: 5px; }
        .code { background: #f1f1f1; padding: 10px; font-family: monospace; border-radius: 3px; }
        .footer { background: #f1f1f1; padding: 20px; text-align: center; font-size: 12px; }
    </style>
</head>
<body>
    <div class="header">
        <h1>📱 Device Setup Instructions</h1>
        <p>Get connected to the Family Network</p>
    </div>
    
    <div class="content">
        <p>Hi $USER_NAME,</p>
        
        <p>Your device configuration files are ready! Follow the instructions below to connect your devices to the family network.</p>
        
        <div class="device-section">
            <h3>📱 Mobile Devices (iPhone/Android)</h3>
            <ol>
                <li>Install the Tailscale app from your app store</li>
                <li>Open the app and choose "Use a different server"</li>
                <li>Enter server: <span class="code">$SERVER_URL</span></li>
                <li>Use your family account credentials</li>
            </ol>
        </div>
        
        <div class="device-section">
            <h3>💻 Computers (Windows/Mac/Linux)</h3>
            <ol>
                <li>Download Tailscale from <a href="https://tailscale.com/download">tailscale.com/download</a></li>
                <li>Install and run the application</li>
                <li>Configure with server: <span class="code">$SERVER_URL</span></li>
                <li>Sign in with your family account</li>
            </ol>
        </div>
        
        <div class="device-section">
            <h3>🔑 Your Account Information</h3>
            <p><strong>Username:</strong> $USERNAME</p>
            <p><strong>Server:</strong> $SERVER_URL</p>
            <p><strong>Password:</strong> Check your welcome email</p>
        </div>
        
        <h3>✅ Verify Your Connection</h3>
        <p>Once connected, visit <strong>https://family.local</strong> to access all family services!</p>
        
        <p style="text-align: center; margin: 30px 0;">
            <a href="https://family.local" class="button">Access Family Network</a>
        </p>
        
        <h3>📋 Available Services</h3>
        <ul>
            <li>📸 Photos: https://photos.family.local</li>
            <li>📄 Documents: https://documents.family.local</li>
            <li>📅 Calendar: https://calendar.family.local</li>
            <li>🎵 Streaming: https://streaming.family.local</li>
        </ul>
        
        <p>Need help? Check the setup instructions included with this email or ask another family member!</p>
    </div>
    
    <div class="footer">
        <p>Configuration generated on $(date)</p>
        <p>Keep your login information secure and don't share with non-family members.</p>
    </div>
</body>
</html>
EOF

    success "Generated setup email: $email_file"
}

# Main execution
main() {
    log "Generating mobile configuration for user: $USERNAME"
    
    # Load user information
    load_user_info
    get_server_config
    
    # Create output directory
    mkdir -p "$OUTPUT_DIR"
    
    if [[ "$ALL_DEVICES" == true ]]; then
        log "Generating configurations for all device types..."
        generate_ios_config
        generate_android_config
        generate_windows_config
        generate_mac_config
        generate_linux_config
    else
        case "$DEVICE" in
            ios|iphone|ipad)
                generate_ios_config
                ;;
            android)
                generate_android_config
                ;;
            windows|win)
                generate_windows_config
                ;;
            mac|macos|osx)
                generate_mac_config
                ;;
            linux)
                generate_linux_config
                ;;
            *)
                error "Unknown device type: $DEVICE"
                error "Supported types: ios, android, windows, mac, linux"
                exit 1
                ;;
        esac
    fi
    
    # Generate QR code if requested
    if [[ "$GENERATE_QR" == true ]]; then
        local qr_text="Server: $SERVER_URL\nUsername: $USERNAME\nSetup: https://family.local/setup"
        generate_qr_code "$qr_text" "$OUTPUT_DIR/${USERNAME}-qr.png"
    fi
    
    # Generate setup email if requested
    if [[ "$GENERATE_EMAIL" == true ]]; then
        generate_setup_email
    fi
    
    success "Mobile configuration generation completed!"
    
    echo ""
    echo "Generated files in: $OUTPUT_DIR"
    echo "Share the appropriate setup file with $USER_NAME"
    echo ""
    echo "Next steps:"
    echo "1. Send the setup instructions to the user"
    echo "2. Help them install the VPN app"
    echo "3. Verify they can connect and access family services"
    echo "4. Show them how to use the family dashboard"
}

# Run main function
main "$@"