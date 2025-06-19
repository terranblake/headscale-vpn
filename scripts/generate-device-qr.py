#!/usr/bin/env python3
"""
QR Code Device Provisioning
Generate QR codes for easy device setup with pre-configured access
"""

import argparse
import base64
import json
import os
import subprocess
import sys
from datetime import datetime, timedelta
from typing import Dict, List, Optional

import qrcode
import requests
from PIL import Image, ImageDraw, ImageFont

class DeviceProvisioner:
    """Generate QR codes for device provisioning"""
    
    def __init__(self):
        self.headscale_url = os.getenv("HEADSCALE_URL", "http://localhost:8080")
        self.api_key = os.getenv("HEADSCALE_API_KEY", "")
        
    def generate_preauth_key(self, user: str, expiry_hours: int = 24, 
                           reusable: bool = False, ephemeral: bool = False) -> str:
        """Generate a pre-auth key for device registration"""
        
        # Calculate expiry time
        expiry = datetime.utcnow() + timedelta(hours=expiry_hours)
        expiry_str = expiry.strftime("%Y-%m-%dT%H:%M:%SZ")
        
        # Use headscale CLI to generate pre-auth key
        cmd = [
            "docker", "exec", "headscale", "headscale", "preauthkeys", "create",
            "--user", user,
            "--expiration", expiry_str,
            "--output", "json"
        ]
        
        if reusable:
            cmd.append("--reusable")
        if ephemeral:
            cmd.append("--ephemeral")
        
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, check=True)
            key_data = json.loads(result.stdout)
            return key_data["key"]
        except subprocess.CalledProcessError as e:
            print(f"Failed to generate pre-auth key: {e}")
            sys.exit(1)

    def get_user_services(self, user: str, device_type: str = "mobile") -> List[Dict]:
        """Get services accessible to user based on device type"""
        
        # This would typically query your service discovery database
        # For now, return example services
        services = [
            {
                "name": "Jellyfin Media Server",
                "url": "http://192.168.1.100:8096",
                "icon": "🎬",
                "category": "media"
            },
            {
                "name": "Home Assistant",
                "url": "http://192.168.1.101:8123",
                "icon": "🏠",
                "category": "automation"
            }
        ]
        
        # Filter services based on user permissions and device type
        if device_type == "tv":
            # TVs typically only need media services
            services = [s for s in services if s["category"] == "media"]
        
        return services

    def generate_device_config(self, user_email: str, device_name: str, 
                             device_type: str = "mobile", 
                             access_groups: List[str] = None) -> Dict:
        """Generate device configuration"""
        
        if access_groups is None:
            access_groups = ["default"]
        
        # Generate pre-auth key
        preauth_key = self.generate_preauth_key(
            user=user_email.split("@")[0],  # Use username part
            expiry_hours=24,
            reusable=False,
            ephemeral=device_type == "guest"
        )
        
        # Get accessible services
        services = self.get_user_services(user_email, device_type)
        
        # Generate configuration
        config = {
            "version": "1.0",
            "type": "headscale-vpn-config",
            "headscale_url": self.headscale_url,
            "preauth_key": preauth_key,
            "device_name": device_name,
            "device_type": device_type,
            "user_email": user_email,
            "access_groups": access_groups,
            "services": services,
            "dns_servers": ["100.64.0.1"],  # Headscale DNS
            "search_domains": ["headscale.local"],
            "routes": self.get_device_routes(device_type, access_groups),
            "created_at": datetime.utcnow().isoformat(),
            "expires_at": (datetime.utcnow() + timedelta(hours=24)).isoformat()
        }
        
        return config

    def get_device_routes(self, device_type: str, access_groups: List[str]) -> List[str]:
        """Get routes for device based on type and access groups"""
        
        routes = []
        
        # Base routes for all devices
        routes.extend([
            "192.168.1.0/24",  # Home network
            "100.64.0.0/10"    # Tailscale network
        ])
        
        # Additional routes based on access groups
        if "media" in access_groups:
            routes.extend([
                "192.168.1.100/32",  # Jellyfin server
                "192.168.1.110/32"   # Plex server
            ])
        
        if "automation" in access_groups:
            routes.extend([
                "192.168.1.101/32"   # Home Assistant
            ])
        
        return routes

    def generate_qr_code(self, config: Dict, output_path: str = None, 
                        include_logo: bool = True) -> str:
        """Generate QR code with device configuration"""
        
        # Encode configuration as base64 JSON
        config_json = json.dumps(config, separators=(',', ':'))
        config_b64 = base64.b64encode(config_json.encode()).decode()
        
        # Create QR code data URL
        qr_data = f"headscale-vpn://{config_b64}"
        
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
        qr_img = qr.make_image(fill_color="black", back_color="white")
        
        # Add logo if requested
        if include_logo:
            qr_img = self.add_logo_to_qr(qr_img)
        
        # Add device info text
        final_img = self.add_device_info(qr_img, config)
        
        # Save image
        if output_path is None:
            output_path = f"qr_codes/{config['device_name']}_setup.png"
        
        os.makedirs(os.path.dirname(output_path), exist_ok=True)
        final_img.save(output_path)
        
        return output_path

    def add_logo_to_qr(self, qr_img: Image.Image) -> Image.Image:
        """Add logo to center of QR code"""
        try:
            # Create a simple logo (you can replace with actual logo)
            logo_size = min(qr_img.size) // 6
            logo = Image.new('RGB', (logo_size, logo_size), 'white')
            draw = ImageDraw.Draw(logo)
            
            # Draw simple VPN icon
            margin = logo_size // 8
            draw.ellipse([margin, margin, logo_size-margin, logo_size-margin], 
                        fill='blue', outline='darkblue', width=2)
            draw.text((logo_size//2, logo_size//2), "VPN", 
                     fill='white', anchor="mm")
            
            # Paste logo onto QR code
            logo_pos = ((qr_img.size[0] - logo_size) // 2,
                       (qr_img.size[1] - logo_size) // 2)
            qr_img.paste(logo, logo_pos)
            
        except Exception as e:
            print(f"Warning: Could not add logo: {e}")
        
        return qr_img

    def add_device_info(self, qr_img: Image.Image, config: Dict) -> Image.Image:
        """Add device information below QR code"""
        
        # Create new image with space for text
        text_height = 120
        new_img = Image.new('RGB', 
                           (qr_img.size[0], qr_img.size[1] + text_height), 
                           'white')
        new_img.paste(qr_img, (0, 0))
        
        # Add text
        draw = ImageDraw.Draw(new_img)
        
        try:
            # Try to use a nice font
            font_large = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 16)
            font_small = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 12)
        except:
            # Fallback to default font
            font_large = ImageFont.load_default()
            font_small = ImageFont.load_default()
        
        y_offset = qr_img.size[1] + 10
        
        # Device name
        draw.text((10, y_offset), f"Device: {config['device_name']}", 
                 fill='black', font=font_large)
        y_offset += 25
        
        # User email
        draw.text((10, y_offset), f"User: {config['user_email']}", 
                 fill='black', font=font_small)
        y_offset += 20
        
        # Expiry
        expiry = datetime.fromisoformat(config['expires_at'].replace('Z', '+00:00'))
        draw.text((10, y_offset), f"Expires: {expiry.strftime('%Y-%m-%d %H:%M')}", 
                 fill='red', font=font_small)
        y_offset += 20
        
        # Services count
        service_count = len(config['services'])
        draw.text((10, y_offset), f"Services: {service_count} available", 
                 fill='green', font=font_small)
        
        return new_img

    def generate_setup_instructions(self, config: Dict, qr_path: str) -> str:
        """Generate setup instructions for the device"""
        
        instructions = f"""
# Device Setup Instructions

## Device: {config['device_name']}
## User: {config['user_email']}

### For Mobile Devices (Android/iOS):

1. **Install Tailscale App**
   - Android: Download from Google Play Store
   - iOS: Download from App Store

2. **Scan QR Code**
   - Open Tailscale app
   - Tap "Add Account" or "+"
   - Scan the QR code below
   - Or manually enter server: {config['headscale_url']}

3. **Complete Setup**
   - The app will automatically configure your connection
   - You'll see a green "Connected" status when ready

### For Smart TVs:

1. **Network Configuration**
   - Go to TV's Network Settings
   - Set DNS servers to: {', '.join(config['dns_servers'])}
   - Save and restart network connection

2. **Service Access**
   - Services will be automatically available
   - No additional software installation required

### Available Services:

"""
        
        for service in config['services']:
            instructions += f"- **{service['name']}** {service['icon']}\n"
            instructions += f"  URL: {service['url']}\n"
            instructions += f"  Category: {service['category']}\n\n"
        
        instructions += f"""
### Troubleshooting:

- **Connection Issues**: Check that your device is connected to the internet
- **Service Access**: Make sure you're connected to the VPN first
- **Expired Setup**: This setup expires on {config['expires_at']}

### Support:

For technical support, contact your network administrator.

---
Generated on: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
QR Code: {qr_path}
"""
        
        return instructions

def main():
    parser = argparse.ArgumentParser(description="Generate device provisioning QR codes")
    parser.add_argument("user_email", help="User email address")
    parser.add_argument("device_name", help="Device name")
    parser.add_argument("--device-type", default="mobile", 
                       choices=["mobile", "tv", "laptop", "guest"],
                       help="Device type")
    parser.add_argument("--access-groups", nargs="+", default=["default"],
                       help="Access groups for the device")
    parser.add_argument("--output-dir", default="./qr_codes",
                       help="Output directory for QR codes")
    parser.add_argument("--expiry-hours", type=int, default=24,
                       help="Hours until setup expires")
    
    args = parser.parse_args()
    
    # Create provisioner
    provisioner = DeviceProvisioner()
    
    # Generate device configuration
    config = provisioner.generate_device_config(
        user_email=args.user_email,
        device_name=args.device_name,
        device_type=args.device_type,
        access_groups=args.access_groups
    )
    
    # Generate QR code
    qr_path = os.path.join(args.output_dir, f"{args.device_name}_setup.png")
    provisioner.generate_qr_code(config, qr_path)
    
    # Generate instructions
    instructions = provisioner.generate_setup_instructions(config, qr_path)
    instructions_path = os.path.join(args.output_dir, f"{args.device_name}_instructions.md")
    
    with open(instructions_path, 'w') as f:
        f.write(instructions)
    
    print(f"✅ QR code generated: {qr_path}")
    print(f"📋 Instructions saved: {instructions_path}")
    print(f"⏰ Setup expires in {args.expiry_hours} hours")
    print(f"🔑 Pre-auth key: {config['preauth_key'][:20]}...")

if __name__ == "__main__":
    main()