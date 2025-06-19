#!/usr/bin/env python3
"""
Chromecast Bridge for Jellyfin
Makes VPN-hosted Jellyfin appear as a local service to Chromecast
"""

import asyncio
import json
import logging
import socket
import struct
import time
from typing import Dict, Optional

import aiohttp
from zeroconf import ServiceInfo, Zeroconf

logger = logging.getLogger(__name__)

class ChromecastJellyfinBridge:
    """Bridge that makes Jellyfin accessible to Chromecast"""
    
    def __init__(self, jellyfin_vpn_url: str, local_ip: str = "192.168.1.100"):
        self.jellyfin_vpn_url = jellyfin_vpn_url.rstrip('/')
        self.local_ip = local_ip
        self.local_port = 8096  # Standard Jellyfin port
        self.zeroconf = Zeroconf()
        self.server_info = None
        
    async def start(self):
        """Start the Chromecast bridge"""
        logger.info("Starting Chromecast Jellyfin Bridge...")
        
        # Start HTTP proxy server
        await self.start_proxy_server()
        
        # Register mDNS service
        await self.register_mdns_service()
        
        # Start SSDP responder
        await self.start_ssdp_responder()
        
        logger.info(f"Bridge running at http://{self.local_ip}:{self.local_port}")
        logger.info("Jellyfin should now be discoverable by Chromecast")

    async def start_proxy_server(self):
        """Start HTTP proxy server for Jellyfin"""
        from aiohttp import web
        
        app = web.Application()
        
        # Proxy all requests to actual Jellyfin server
        app.router.add_route('*', '/{path:.*}', self.proxy_request)
        
        runner = web.AppRunner(app)
        await runner.setup()
        
        site = web.TCPSite(runner, self.local_ip, self.local_port)
        await site.start()
        
        logger.info(f"Proxy server started on {self.local_ip}:{self.local_port}")

    async def proxy_request(self, request):
        """Proxy HTTP request to actual Jellyfin server"""
        # Build target URL
        path = request.match_info.get('path', '')
        target_url = f"{self.jellyfin_vpn_url}/{path}"
        
        # Copy query parameters
        if request.query_string:
            target_url += f"?{request.query_string}"
        
        # Prepare headers (remove host header)
        headers = dict(request.headers)
        headers.pop('host', None)
        headers['Host'] = self.jellyfin_vpn_url.split('://')[-1]
        
        try:
            async with aiohttp.ClientSession() as session:
                async with session.request(
                    method=request.method,
                    url=target_url,
                    headers=headers,
                    data=await request.read()
                ) as response:
                    
                    # Read response
                    body = await response.read()
                    
                    # Modify response for Chromecast compatibility
                    if response.content_type and 'application/json' in response.content_type:
                        body = self.modify_jellyfin_json(body)
                    elif response.content_type and 'text/html' in response.content_type:
                        body = self.modify_jellyfin_html(body)
                    
                    # Return response
                    return web.Response(
                        body=body,
                        status=response.status,
                        headers=response.headers
                    )
                    
        except Exception as e:
            logger.error(f"Proxy error: {e}")
            return web.Response(text="Service unavailable", status=503)

    def modify_jellyfin_json(self, body: bytes) -> bytes:
        """Modify Jellyfin JSON responses for local access"""
        try:
            data = json.loads(body.decode())
            
            # Replace server URLs with local URLs
            data_str = json.dumps(data)
            data_str = data_str.replace(self.jellyfin_vpn_url, f"http://{self.local_ip}:{self.local_port}")
            
            return data_str.encode()
        except:
            return body

    def modify_jellyfin_html(self, body: bytes) -> bytes:
        """Modify Jellyfin HTML responses for local access"""
        try:
            html = body.decode()
            
            # Replace URLs in HTML
            html = html.replace(self.jellyfin_vpn_url, f"http://{self.local_ip}:{self.local_port}")
            
            return html.encode()
        except:
            return body

    async def register_mdns_service(self):
        """Register Jellyfin as mDNS service for discovery"""
        logger.info("Registering mDNS service...")
        
        # Jellyfin mDNS service info
        service_type = "_jellyfin._tcp.local."
        service_name = f"Jellyfin Media Server._jellyfin._tcp.local."
        
        properties = {
            'Version': '10.8.0',
            'Product': 'Jellyfin Server',
            'Id': 'jellyfin-bridge-server'
        }
        
        info = ServiceInfo(
            service_type,
            service_name,
            addresses=[socket.inet_aton(self.local_ip)],
            port=self.local_port,
            properties=properties
        )
        
        self.zeroconf.register_service(info)
        self.server_info = info
        
        logger.info(f"Registered mDNS service: {service_name}")

    async def start_ssdp_responder(self):
        """Start SSDP responder for UPnP discovery"""
        logger.info("Starting SSDP responder...")
        
        # Create SSDP socket
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        sock.bind(('', 1900))
        
        # Join multicast group
        mreq = struct.pack("4sl", socket.inet_aton("239.255.255.250"), socket.INADDR_ANY)
        sock.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, mreq)
        
        # Start listening for SSDP requests
        asyncio.create_task(self.handle_ssdp_requests(sock))

    async def handle_ssdp_requests(self, sock):
        """Handle SSDP discovery requests"""
        while True:
            try:
                data, addr = sock.recvfrom(1024)
                request = data.decode('utf-8')
                
                # Check if it's a search request for media servers
                if 'M-SEARCH' in request and ('upnp:rootdevice' in request or 'MediaServer' in request):
                    await self.send_ssdp_response(addr)
                    
            except Exception as e:
                logger.error(f"SSDP error: {e}")
                await asyncio.sleep(1)

    async def send_ssdp_response(self, addr):
        """Send SSDP response advertising Jellyfin server"""
        response = f"""HTTP/1.1 200 OK
CACHE-CONTROL: max-age=1800
DATE: {time.strftime('%a, %d %b %Y %H:%M:%S GMT', time.gmtime())}
EXT:
LOCATION: http://{self.local_ip}:{self.local_port}/dlna/description.xml
OPT: "http://schemas.upnp.org/upnp/1/0/"; ns=01
01-NLS: 1
SERVER: Linux/3.14 UPnP/1.0 Jellyfin/10.8.0
ST: upnp:rootdevice
USN: uuid:jellyfin-bridge-server::upnp:rootdevice

"""
        
        # Send response
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.sendto(response.encode(), addr)
        sock.close()

    def stop(self):
        """Stop the bridge"""
        if self.server_info:
            self.zeroconf.unregister_service(self.server_info)
        self.zeroconf.close()

class ChromecastSetupWizard:
    """Setup wizard for Chromecast integration"""
    
    def __init__(self):
        self.bridge = None
        
    async def setup_chromecast_bridge(self, jellyfin_url: str, network_interface: str = None):
        """Setup Chromecast bridge with guided configuration"""
        
        print("🎬 Chromecast Jellyfin Bridge Setup")
        print("=" * 40)
        
        # Detect local IP
        local_ip = self.detect_local_ip(network_interface)
        print(f"📍 Detected local IP: {local_ip}")
        
        # Validate Jellyfin connection
        print("🔍 Testing Jellyfin connection...")
        if not await self.test_jellyfin_connection(jellyfin_url):
            print("❌ Cannot connect to Jellyfin server")
            return False
        
        print("✅ Jellyfin connection successful")
        
        # Start bridge
        print("🌉 Starting Chromecast bridge...")
        self.bridge = ChromecastJellyfinBridge(jellyfin_url, local_ip)
        await self.bridge.start()
        
        # Display setup instructions
        self.display_setup_instructions(local_ip)
        
        return True

    def detect_local_ip(self, interface: str = None) -> str:
        """Detect local IP address"""
        if interface:
            import netifaces
            addrs = netifaces.ifaddresses(interface)
            return addrs[netifaces.AF_INET][0]['addr']
        else:
            # Auto-detect
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            try:
                s.connect(('8.8.8.8', 80))
                ip = s.getsockname()[0]
                s.close()
                return ip
            except:
                return '192.168.1.100'  # Fallback

    async def test_jellyfin_connection(self, url: str) -> bool:
        """Test connection to Jellyfin server"""
        try:
            async with aiohttp.ClientSession() as session:
                async with session.get(f"{url}/System/Info", timeout=10) as response:
                    return response.status == 200
        except:
            return False

    def display_setup_instructions(self, local_ip: str):
        """Display setup instructions for user"""
        
        instructions = f"""
🎯 Chromecast Setup Complete!

📱 PHONE/TABLET SETUP:
1. Make sure your phone is on the same network as the bridge device
2. Open the Jellyfin app on your phone
3. Add server manually: http://{local_ip}:8096
4. Login with your Jellyfin credentials
5. You should now see your Chromecast in the cast menu

📺 CHROMECAST SETUP:
1. Make sure Chromecast is on the same network
2. Chromecast will automatically discover the "local" Jellyfin server
3. No additional setup needed on Chromecast

🔧 TROUBLESHOOTING:
- Ensure all devices are on the same network
- Check firewall settings on bridge device
- Restart Chromecast if it doesn't appear
- Check bridge logs for connection issues

🌐 Bridge Status:
- Local Jellyfin URL: http://{local_ip}:8096
- mDNS Service: Registered
- SSDP Responder: Active
- Proxy Server: Running

The bridge will continue running. Keep this device powered on for Chromecast access.
        """
        
        print(instructions)

# Example usage
async def main():
    wizard = ChromecastSetupWizard()
    
    # Get Jellyfin URL from environment or user input
    jellyfin_url = input("Enter your Jellyfin VPN URL (e.g., http://100.64.0.2:8096): ")
    
    success = await wizard.setup_chromecast_bridge(jellyfin_url)
    
    if success:
        print("✅ Bridge setup complete! Press Ctrl+C to stop.")
        try:
            while True:
                await asyncio.sleep(1)
        except KeyboardInterrupt:
            print("\n🛑 Stopping bridge...")
            wizard.bridge.stop()
    else:
        print("❌ Bridge setup failed!")

if __name__ == "__main__":
    asyncio.run(main())