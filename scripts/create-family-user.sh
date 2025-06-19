#!/bin/bash

# Family User Creation Script
# Creates a new family member account with appropriate access and configuration

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_FILE="/var/log/family-network-user-creation.log"

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
Family User Creation Script

Usage: $0 [OPTIONS]

OPTIONS:
    -n, --name NAME         Family member's full name (required)
    -u, --username USER     Username for the account (required)
    -e, --email EMAIL       Email address (required)
    -a, --age AGE          Age (for setting appropriate permissions)
    -d, --device DEVICE    Primary device type (phone/tablet/computer)
    -p, --parent           Mark as parent (full access)
    -k, --kid              Mark as child (restricted access)
    -g, --guest            Create temporary guest account
    --dry-run              Show what would be done without making changes
    -h, --help             Show this help message

EXAMPLES:
    # Create parent account
    $0 --name "John Smith" --username "john" --email "john@family.local" --parent

    # Create child account
    $0 --name "Emma Smith" --username "emma" --email "emma@family.local" --age 12 --kid

    # Create guest account
    $0 --name "Grandma" --username "grandma" --email "grandma@family.local" --guest

    # Dry run to see what would happen
    $0 --name "Test User" --username "test" --email "test@family.local" --dry-run

EOF
}

# Default values
NAME=""
USERNAME=""
EMAIL=""
AGE=""
DEVICE="computer"
IS_PARENT=false
IS_KID=false
IS_GUEST=false
DRY_RUN=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--name)
            NAME="$2"
            shift 2
            ;;
        -u|--username)
            USERNAME="$2"
            shift 2
            ;;
        -e|--email)
            EMAIL="$2"
            shift 2
            ;;
        -a|--age)
            AGE="$2"
            shift 2
            ;;
        -d|--device)
            DEVICE="$2"
            shift 2
            ;;
        -p|--parent)
            IS_PARENT=true
            shift
            ;;
        -k|--kid)
            IS_KID=true
            shift
            ;;
        -g|--guest)
            IS_GUEST=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
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
if [[ -z "$NAME" || -z "$USERNAME" || -z "$EMAIL" ]]; then
    error "Name, username, and email are required"
    show_help
    exit 1
fi

# Validate username format
if [[ ! "$USERNAME" =~ ^[a-z0-9_-]+$ ]]; then
    error "Username must contain only lowercase letters, numbers, hyphens, and underscores"
    exit 1
fi

# Validate email format
if [[ ! "$EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
    error "Invalid email format"
    exit 1
fi

# Determine user type
USER_TYPE="member"
if [[ "$IS_PARENT" == true ]]; then
    USER_TYPE="parent"
elif [[ "$IS_KID" == true ]]; then
    USER_TYPE="child"
elif [[ "$IS_GUEST" == true ]]; then
    USER_TYPE="guest"
fi

# Set age-based restrictions if age is provided
if [[ -n "$AGE" && "$AGE" -lt 13 ]]; then
    IS_KID=true
    USER_TYPE="child"
    warning "Age under 13 detected, automatically setting child restrictions"
fi

log "Creating family user account for: $NAME ($USERNAME)"
log "User type: $USER_TYPE"
log "Primary device: $DEVICE"

if [[ "$DRY_RUN" == true ]]; then
    warning "DRY RUN MODE - No changes will be made"
fi

# Generate secure password
generate_password() {
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -base64 12 | tr -d "=+/" | cut -c1-12
    else
        # Fallback method
        date +%s | sha256sum | base64 | head -c 12
    fi
}

PASSWORD=$(generate_password)

# Create user configuration
create_user_config() {
    local config_file="$PROJECT_DIR/config/users/${USERNAME}.yaml"
    
    if [[ "$DRY_RUN" == true ]]; then
        log "Would create user config: $config_file"
        return
    fi
    
    mkdir -p "$(dirname "$config_file")"
    
    cat > "$config_file" << EOF
# Family Network User Configuration
# Generated on $(date)

user:
  name: "$NAME"
  username: "$USERNAME"
  email: "$EMAIL"
  type: "$USER_TYPE"
  created: "$(date -Iseconds)"
  primary_device: "$DEVICE"
  
permissions:
  photos:
    read: true
    write: $([ "$USER_TYPE" != "guest" ] && echo "true" || echo "false")
    share: $([ "$USER_TYPE" == "parent" ] && echo "true" || echo "false")
    
  documents:
    read: true
    write: $([ "$USER_TYPE" != "guest" ] && echo "true" || echo "false")
    share: $([ "$USER_TYPE" == "parent" ] && echo "true" || echo "false")
    admin_folders: $([ "$USER_TYPE" == "parent" ] && echo "true" || echo "false")
    
  calendar:
    read: true
    write: $([ "$USER_TYPE" != "guest" ] && echo "true" || echo "false")
    create_events: $([ "$USER_TYPE" != "guest" ] && echo "true" || echo "false")
    family_calendar: $([ "$USER_TYPE" == "parent" ] && echo "admin" || echo "read")
    
  home_automation:
    read: $([ "$USER_TYPE" == "child" ] && echo "false" || echo "true")
    control: $([ "$USER_TYPE" == "parent" ] && echo "true" || echo "false")
    security: $([ "$USER_TYPE" == "parent" ] && echo "true" || echo "false")
    
  streaming:
    access: true
    admin: $([ "$USER_TYPE" == "parent" ] && echo "true" || echo "false")
    content_rating: $([ "$USER_TYPE" == "child" ] && echo "PG-13" || echo "R")

restrictions:
  time_limits: $([ "$USER_TYPE" == "child" ] && echo "true" || echo "false")
  content_filter: $([ "$USER_TYPE" == "child" ] && echo "true" || echo "false")
  guest_expires: $([ "$USER_TYPE" == "guest" ] && echo "$(date -d '+30 days' -Iseconds)" || echo "null")
  
settings:
  language: "en"
  timezone: "$(timedatectl show --property=Timezone --value 2>/dev/null || echo 'UTC')"
  notifications: true
  mobile_sync: true
EOF

    success "Created user configuration: $config_file"
}

# Create Headscale user
create_headscale_user() {
    if [[ "$DRY_RUN" == true ]]; then
        log "Would create Headscale user: $USERNAME"
        return
    fi
    
    log "Creating Headscale user..."
    
    # Create user in Headscale
    if command -v headscale >/dev/null 2>&1; then
        headscale users create "$USERNAME" || {
            warning "Headscale user creation failed, user might already exist"
        }
        success "Headscale user created: $USERNAME"
    else
        warning "Headscale command not found, skipping VPN user creation"
    fi
}

# Generate device configuration
generate_device_config() {
    local config_dir="$PROJECT_DIR/config/devices/$USERNAME"
    
    if [[ "$DRY_RUN" == true ]]; then
        log "Would create device configs in: $config_dir"
        return
    fi
    
    mkdir -p "$config_dir"
    
    # Generate pre-auth key for easy device setup
    if command -v headscale >/dev/null 2>&1; then
        local preauth_key
        preauth_key=$(headscale preauthkeys create --user "$USERNAME" --expiration 24h --output json 2>/dev/null | jq -r '.key' || echo "")
        
        if [[ -n "$preauth_key" ]]; then
            cat > "$config_dir/setup-info.txt" << EOF
Family Network Setup Information for $NAME
==========================================

Username: $USERNAME
Email: $EMAIL
Temporary Password: $PASSWORD
Pre-auth Key: $preauth_key

Device Setup Instructions:
1. Install the family VPN app on your device
2. Use the pre-auth key above for quick setup
3. Change your password after first login

This information expires in 24 hours for security.
Generated on: $(date)
EOF
            success "Generated device setup info: $config_dir/setup-info.txt"
        else
            warning "Could not generate pre-auth key"
        fi
    fi
}

# Create user directories
create_user_directories() {
    if [[ "$DRY_RUN" == true ]]; then
        log "Would create user directories for: $USERNAME"
        return
    fi
    
    # Create user-specific directories in various services
    local user_dirs=(
        "$PROJECT_DIR/data/photos/users/$USERNAME"
        "$PROJECT_DIR/data/documents/users/$USERNAME"
        "$PROJECT_DIR/data/calendar/users/$USERNAME"
    )
    
    for dir in "${user_dirs[@]}"; do
        mkdir -p "$dir"
        # Set appropriate permissions
        chmod 750 "$dir"
        log "Created directory: $dir"
    done
    
    success "Created user directories"
}

# Generate welcome email
generate_welcome_email() {
    local email_file="$PROJECT_DIR/config/emails/welcome-${USERNAME}.html"
    
    if [[ "$DRY_RUN" == true ]]; then
        log "Would generate welcome email: $email_file"
        return
    fi
    
    mkdir -p "$(dirname "$email_file")"
    
    cat > "$email_file" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Welcome to the Family Network</title>
    <style>
        body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
        .header { background: #4CAF50; color: white; padding: 20px; text-align: center; }
        .content { padding: 20px; }
        .info-box { background: #f9f9f9; border-left: 4px solid #4CAF50; padding: 15px; margin: 20px 0; }
        .button { background: #4CAF50; color: white; padding: 10px 20px; text-decoration: none; border-radius: 5px; }
        .footer { background: #f1f1f1; padding: 20px; text-align: center; font-size: 12px; }
    </style>
</head>
<body>
    <div class="header">
        <h1>Welcome to the Family Network, $NAME!</h1>
    </div>
    
    <div class="content">
        <p>Hi $NAME,</p>
        
        <p>Your family network account has been created! You now have access to all our family services including photos, documents, calendar, and more.</p>
        
        <div class="info-box">
            <h3>Your Account Information:</h3>
            <p><strong>Username:</strong> $USERNAME</p>
            <p><strong>Email:</strong> $EMAIL</p>
            <p><strong>Account Type:</strong> $USER_TYPE</p>
            <p><strong>Temporary Password:</strong> $PASSWORD</p>
        </div>
        
        <h3>Getting Started:</h3>
        <ol>
            <li>Install the family VPN app on your device</li>
            <li>Connect using your username and temporary password</li>
            <li>Change your password after first login</li>
            <li>Explore the family services at <strong>https://family.local</strong></li>
        </ol>
        
        <h3>What You Can Access:</h3>
        <ul>
            <li>📸 <strong>Family Photos:</strong> https://photos.family.local</li>
            <li>📄 <strong>Documents:</strong> https://documents.family.local</li>
            <li>📅 <strong>Calendar:</strong> https://calendar.family.local</li>
            <li>🎵 <strong>Streaming:</strong> https://streaming.family.local</li>
$([ "$USER_TYPE" != "child" ] && echo "            <li>🏠 <strong>Home Automation:</strong> https://home.family.local</li>")
        </ul>
        
        <p>If you need help getting started, check out our family guides or ask another family member!</p>
        
        <p style="text-align: center; margin: 30px 0;">
            <a href="https://family.local" class="button">Access Family Network</a>
        </p>
    </div>
    
    <div class="footer">
        <p>This is your private family network. Keep your login information secure!</p>
        <p>Generated on $(date)</p>
    </div>
</body>
</html>
EOF

    success "Generated welcome email: $email_file"
}

# Update family directory
update_family_directory() {
    local directory_file="$PROJECT_DIR/config/family-directory.yaml"
    
    if [[ "$DRY_RUN" == true ]]; then
        log "Would update family directory: $directory_file"
        return
    fi
    
    # Create directory file if it doesn't exist
    if [[ ! -f "$directory_file" ]]; then
        cat > "$directory_file" << EOF
# Family Network Directory
# Auto-generated and maintained

family_members: []
last_updated: "$(date -Iseconds)"
EOF
    fi
    
    # Add new member to directory (simplified - in production would use proper YAML parsing)
    cat >> "$directory_file" << EOF

# Added $(date)
- name: "$NAME"
  username: "$USERNAME"
  email: "$EMAIL"
  type: "$USER_TYPE"
  joined: "$(date -Iseconds)"
  status: "active"
EOF

    success "Updated family directory"
}

# Main execution
main() {
    log "Starting family user creation process..."
    
    # Check if user already exists
    if [[ -f "$PROJECT_DIR/config/users/${USERNAME}.yaml" && "$DRY_RUN" == false ]]; then
        error "User $USERNAME already exists!"
        exit 1
    fi
    
    # Create user components
    create_user_config
    create_headscale_user
    generate_device_config
    create_user_directories
    generate_welcome_email
    update_family_directory
    
    if [[ "$DRY_RUN" == true ]]; then
        log "Dry run completed - no changes were made"
    else
        success "Family user account created successfully!"
        
        echo ""
        echo "Next Steps:"
        echo "1. Share the setup information with $NAME"
        echo "2. Help them install and configure the VPN app"
        echo "3. Send them the welcome email: config/emails/welcome-${USERNAME}.html"
        echo "4. Make sure they change their temporary password"
        echo ""
        echo "Setup info location: config/devices/$USERNAME/setup-info.txt"
    fi
}

# Run main function
main "$@"