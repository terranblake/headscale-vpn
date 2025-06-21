#!/bin/bash
# Add a new device to the Headscale network

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
HEADSCALE_URL=${HEADSCALE_URL:-https://headscale.terranblake.com}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Headscale VPN - Add Device${NC}"
echo "================================"

# Function to check if headscale is running
check_headscale() {
    echo -e "${YELLOW}Checking Headscale connectivity...${NC}"
    if ! ssh mgmt-host "kubectl get pods -n headscale-vpn -l app=headscale --no-headers | grep Running" >/dev/null 2>&1; then
        echo -e "${RED}ERROR: Headscale pod is not running in Kubernetes${NC}"
        echo "Please check the deployment: kubectl get pods -n headscale-vpn"
        exit 1
    fi
    echo -e "${GREEN}Headscale is running${NC}"
}

# Function to create a user if it doesn't exist
create_user() {
    local username="$1"
    echo -e "${YELLOW}Creating user: $username${NC}"
    
    # Check if user already exists
    if ssh mgmt-host "kubectl exec -n headscale-vpn deployment/headscale -- headscale users list" | grep -q "$username"; then
        echo -e "${GREEN}User $username already exists${NC}"
    else
        ssh mgmt-host "kubectl exec -n headscale-vpn deployment/headscale -- headscale users create $username"
        echo -e "${GREEN}User $username created${NC}"
    fi
}

# Function to generate a pre-auth key
generate_preauthkey() {
    local username="$1"
    local expiry="${2:-24h}"
    
    echo -e "${YELLOW}Generating pre-auth key for user: $username${NC}"
    
    # Get user ID first
    local user_id=$(ssh mgmt-host "kubectl exec -n headscale-vpn deployment/headscale -- headscale users list" | grep "$username" | awk '{print $1}')
    
    if [[ -z "$user_id" ]]; then
        echo -e "${RED}ERROR: Could not find user ID for $username${NC}"
        exit 1
    fi
    
    local key=$(ssh mgmt-host "kubectl exec -n headscale-vpn deployment/headscale -- headscale preauthkeys create --user $user_id --expiration $expiry --reusable" | grep -o '[a-f0-9]\{48\}')
    
    if [[ -n "$key" ]]; then
        echo "$key"
    else
        echo -e "${RED}ERROR: Failed to generate pre-auth key${NC}"
        exit 1
    fi
}

# Function to show device connection instructions
show_instructions() {
    local username="$1"
    local preauthkey="$2"
    local device_type="$3"
    
    echo -e "${GREEN}Device Connection Instructions${NC}"
    echo "====================================="
    echo
    echo -e "${YELLOW}1. Install Tailscale on your device:${NC}"
    
    case "$device_type" in
        "linux")
            echo "   curl -fsSL https://tailscale.com/install.sh | sh"
            ;;
        "macos")
            echo "   brew install tailscale"
            echo "   # Or download from: https://tailscale.com/download/mac"
            ;;
        "windows")
            echo "   Download from: https://tailscale.com/download/windows"
            ;;
        "android")
            echo "   Install from Google Play Store: https://play.google.com/store/apps/details?id=com.tailscale.ipn"
            ;;
        "ios")
            echo "   Install from App Store: https://apps.apple.com/app/tailscale/id1470499037"
            ;;
        *)
            echo "   Visit: https://tailscale.com/download"
            ;;
    esac
    
    echo
    echo -e "${YELLOW}2. Connect to your Headscale network:${NC}"
    echo "   sudo tailscale up --login-server=$HEADSCALE_URL --authkey=$preauthkey"
    echo
    echo -e "${YELLOW}3. (Optional) Set exit node:${NC}"
    echo "   sudo tailscale up --exit-node=vpn-exit-node"
    echo
    echo -e "${YELLOW}4. Verify connection:${NC}"
    echo "   tailscale status"
    echo "   tailscale ip"
    echo
    echo -e "${GREEN}Your device should now be connected to the mesh VPN!${NC}"
}

# Main execution
main() {
    check_headscale
    
    # Get user input
    read -p "Enter username for this device: " username
    if [[ -z "$username" ]]; then
        echo -e "${RED}ERROR: Username cannot be empty${NC}"
        exit 1
    fi
    
    read -p "Enter device type (linux/macos/windows/android/ios): " device_type
    device_type=${device_type:-linux}
    
    read -p "Pre-auth key expiration (default: 24h): " expiry
    expiry=${expiry:-24h}
    
    # Create user and generate key
    create_user "$username"
    preauthkey=$(generate_preauthkey "$username" "$expiry")
    
    # Show instructions
    show_instructions "$username" "$preauthkey" "$device_type"
    
    echo
    echo -e "${GREEN}Device setup initiated successfully!${NC}"
    echo -e "${YELLOW}Pre-auth key expires in: $expiry${NC}"
}

# Run main function
main "$@"
