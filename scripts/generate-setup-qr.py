#!/usr/bin/env python3

"""
Family Network QR Code Generator
Creates QR codes for easy family member device setup
"""

import argparse
import json
import os
import sys
import yaml
from datetime import datetime, timedelta
from pathlib import Path

try:
    import qrcode
    from qrcode.image.styledpil import StyledPilImage
    from qrcode.image.styles.moduledrawers import RoundedModuleDrawer
    from qrcode.image.styles.colormasks import SquareGradiantColorMask
except ImportError:
    print("Error: Required packages not installed")
    print("Install with: pip install qrcode[pil] pillow")
    sys.exit(1)

class FamilyQRGenerator:
    def __init__(self, project_dir=None):
        self.project_dir = Path(project_dir) if project_dir else Path(__file__).parent.parent
        self.config_dir = self.project_dir / "config"
        self.output_dir = self.project_dir / "config" / "qr-codes"
        self.output_dir.mkdir(parents=True, exist_ok=True)
        
    def load_user_config(self, username):
        """Load user configuration from YAML file"""
        user_config_file = self.config_dir / "users" / f"{username}.yaml"
        
        if not user_config_file.exists():
            raise FileNotFoundError(f"User configuration not found: {user_config_file}")
            
        with open(user_config_file, 'r') as f:
            return yaml.safe_load(f)
    
    def load_server_config(self):
        """Load server configuration"""
        # Try to load from .env file
        env_file = self.project_dir / ".env"
        server_config = {
            'server_url': 'https://vpn.family.local',
            'server_name': 'family-network'
        }
        
        if env_file.exists():
            with open(env_file, 'r') as f:
                for line in f:
                    if line.startswith('HEADSCALE_SERVER_URL='):
                        server_config['server_url'] = line.split('=', 1)[1].strip()
                    elif line.startswith('HEADSCALE_SERVER_NAME='):
                        server_config['server_name'] = line.split('=', 1)[1].strip()
        
        # Try to load from headscale config
        headscale_config = self.config_dir / "headscale" / "config.yaml"
        if headscale_config.exists():
            try:
                with open(headscale_config, 'r') as f:
                    config = yaml.safe_load(f)
                    if 'server_url' in config:
                        server_config['server_url'] = config['server_url']
            except Exception:
                pass  # Use defaults
                
        return server_config
    
    def generate_preauth_key(self, username, expiration_hours=24):
        """Generate a pre-auth key (placeholder implementation)"""
        # In a real implementation, this would call headscale
        # For now, return a placeholder
        import hashlib
        import time
        
        timestamp = str(int(time.time()))
        key_data = f"{username}-{timestamp}"
        key_hash = hashlib.sha256(key_data.encode()).hexdigest()[:16]
        
        return f"preauth-{key_hash}"
    
    def create_setup_data(self, username, device_type="mobile", include_preauth=True):
        """Create setup data for QR code"""
        user_config = self.load_user_config(username)
        server_config = self.load_server_config()
        
        setup_data = {
            'type': 'family_network_setup',
            'version': '1.0',
            'server': {
                'url': server_config['server_url'],
                'name': server_config['server_name']
            },
            'user': {
                'username': username,
                'name': user_config['user']['name'],
                'email': user_config['user']['email'],
                'type': user_config['user']['type']
            },
            'device': {
                'type': device_type,
                'setup_url': f"https://family.local/setup?user={username}"
            },
            'services': {
                'dashboard': 'https://family.local',
                'photos': 'https://photos.family.local',
                'documents': 'https://documents.family.local',
                'calendar': 'https://calendar.family.local',
                'streaming': 'https://streaming.family.local'
            },
            'generated': datetime.now().isoformat(),
            'expires': (datetime.now() + timedelta(days=7)).isoformat()
        }
        
        if include_preauth:
            setup_data['auth'] = {
                'preauth_key': self.generate_preauth_key(username),
                'expires_hours': 24
            }
            
        return setup_data
    
    def create_simple_setup_url(self, username):
        """Create a simple setup URL for basic QR codes"""
        server_config = self.load_server_config()
        
        # Create a simple URL with setup parameters
        setup_url = f"https://family.local/setup"
        params = [
            f"user={username}",
            f"server={server_config['server_url']}",
            f"type=mobile"
        ]
        
        return f"{setup_url}?{'&'.join(params)}"
    
    def generate_qr_code(self, data, output_file, style="modern"):
        """Generate QR code with specified style"""
        
        # Create QR code instance
        qr = qrcode.QRCode(
            version=1,  # Controls size (1 is smallest)
            error_correction=qrcode.constants.ERROR_CORRECT_M,
            box_size=10,
            border=4,
        )
        
        # Add data to QR code
        if isinstance(data, dict):
            qr.add_data(json.dumps(data, separators=(',', ':')))
        else:
            qr.add_data(str(data))
            
        qr.make(fit=True)
        
        # Generate image based on style
        if style == "simple":
            # Simple black and white QR code
            img = qr.make_image(fill_color="black", back_color="white")
        elif style == "modern":
            # Modern styled QR code with rounded corners
            img = qr.make_image(
                image_factory=StyledPilImage,
                module_drawer=RoundedModuleDrawer(),
                color_mask=SquareGradiantColorMask(
                    back_color=(255, 255, 255),
                    center_color=(0, 100, 200),
                    edge_color=(0, 50, 150)
                )
            )
        else:
            # Default style
            img = qr.make_image(fill_color="black", back_color="white")
        
        # Save image
        img.save(output_file)
        return output_file
    
    def generate_setup_instructions(self, username, qr_file):
        """Generate setup instructions to accompany QR code"""
        user_config = self.load_user_config(username)
        user_name = user_config['user']['name']
        
        instructions_file = qr_file.with_suffix('.txt')
        
        instructions = f"""
Family Network QR Code Setup Instructions
=========================================

For: {user_name} ({username})
Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}

MOBILE SETUP (iPhone/Android):
1. Install Tailscale app from your app store
2. Open the app and tap "Sign in"
3. Choose "Use a different server"
4. Scan this QR code OR enter manually:
   - Server: [See QR code data]
   - Username: {username}
   - Password: [Check your welcome email]

COMPUTER SETUP:
1. Go to: https://tailscale.com/download
2. Download and install Tailscale
3. Use the same server and credentials as above

VERIFY CONNECTION:
- Look for "Connected" status in Tailscale
- Open browser and go to: https://family.local
- You should see the family dashboard

QR CODE CONTAINS:
- Server connection information
- Your username and setup details
- Links to family services
- Expiration date (7 days from generation)

TROUBLESHOOTING:
- Make sure you have internet connection
- Try turning WiFi off and on
- Check that QR code hasn't expired
- Ask another family member for help

Keep this QR code private - it contains your family network access information!
"""
        
        with open(instructions_file, 'w') as f:
            f.write(instructions.strip())
            
        return instructions_file
    
    def generate_family_overview_qr(self):
        """Generate a QR code with family network overview"""
        server_config = self.load_server_config()
        
        overview_data = {
            'type': 'family_network_info',
            'name': 'Family Network',
            'description': 'Private family services and VPN',
            'setup_url': 'https://family.local/setup',
            'services': {
                'Dashboard': 'https://family.local',
                'Photos': 'https://photos.family.local',
                'Documents': 'https://documents.family.local',
                'Calendar': 'https://calendar.family.local',
                'Streaming': 'https://streaming.family.local'
            },
            'help': 'https://family.local/help',
            'generated': datetime.now().isoformat()
        }
        
        output_file = self.output_dir / "family-network-overview.png"
        self.generate_qr_code(overview_data, output_file, style="modern")
        
        # Generate instructions
        instructions_file = self.output_dir / "family-network-overview.txt"
        with open(instructions_file, 'w') as f:
            f.write(f"""
Family Network Overview QR Code
===============================

This QR code contains information about your family network services.

Scan with any QR code reader to see:
- Available family services
- Setup instructions link
- Help and documentation links

Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}

Share this QR code with family members who need basic information
about the family network services.
""".strip())
        
        return output_file, instructions_file

def main():
    parser = argparse.ArgumentParser(description='Generate QR codes for family network setup')
    parser.add_argument('-u', '--username', required=True, help='Username for QR code')
    parser.add_argument('-d', '--device', default='mobile', 
                       choices=['mobile', 'computer', 'tablet'],
                       help='Device type for setup')
    parser.add_argument('-s', '--style', default='modern',
                       choices=['simple', 'modern', 'default'],
                       help='QR code style')
    parser.add_argument('-o', '--output', help='Output directory (default: config/qr-codes)')
    parser.add_argument('--simple-url', action='store_true',
                       help='Generate simple URL QR code instead of full data')
    parser.add_argument('--no-preauth', action='store_true',
                       help='Don\'t include pre-auth key in QR code')
    parser.add_argument('--overview', action='store_true',
                       help='Generate family network overview QR code')
    parser.add_argument('--project-dir', help='Project directory path')
    
    args = parser.parse_args()
    
    try:
        generator = FamilyQRGenerator(args.project_dir)
        
        if args.output:
            generator.output_dir = Path(args.output)
            generator.output_dir.mkdir(parents=True, exist_ok=True)
        
        if args.overview:
            # Generate family overview QR code
            qr_file, instructions_file = generator.generate_family_overview_qr()
            print(f"Generated family overview QR code: {qr_file}")
            print(f"Generated instructions: {instructions_file}")
            return
        
        # Generate user-specific QR code
        if args.simple_url:
            # Generate simple URL QR code
            setup_url = generator.create_simple_setup_url(args.username)
            data = setup_url
            filename = f"{args.username}-setup-url.png"
        else:
            # Generate full setup data QR code
            data = generator.create_setup_data(
                args.username, 
                args.device, 
                include_preauth=not args.no_preauth
            )
            filename = f"{args.username}-{args.device}-setup.png"
        
        output_file = generator.output_dir / filename
        generator.generate_qr_code(data, output_file, args.style)
        
        # Generate instructions
        instructions_file = generator.generate_setup_instructions(args.username, output_file)
        
        print(f"Generated QR code: {output_file}")
        print(f"Generated instructions: {instructions_file}")
        print(f"\nShare the QR code and instructions with {args.username}")
        print("QR code expires in 7 days for security")
        
    except FileNotFoundError as e:
        print(f"Error: {e}")
        print(f"Make sure user {args.username} exists (create with create-family-user.sh)")
        sys.exit(1)
    except Exception as e:
        print(f"Error generating QR code: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()