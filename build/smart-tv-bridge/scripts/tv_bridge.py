#!/usr/bin/env python3
"""
Smart TV Bridge
Creates a bridge device that allows TVs to access VPN services without router configuration
"""

import asyncio
import json
import logging
import os
import subprocess
import time
from datetime import datetime
from typing import Dict, List, Optional

import aiohttp
import netifaces
import qrcode
from fastapi import FastAPI, Request, Response
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from zeroconf import ServiceInfo, Zeroconf

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class TVBridge:
    """Main TV Bridge class that handles all bridge functionality"""
    
    def __init__(self):
        self.app = FastAPI(title="TV Bridge", description="Smart TV VPN Bridge")
        self.zeroconf = Zeroconf()
        self.services = {}
        self.bridge_ip = "192.168.4.1"  # Default bridge IP
        self.is_connected = False
        self.setup_routes()
        
    def setup_routes(self):
        """Setup FastAPI routes"""
        
        @self.app.get("/", response_class=HTMLResponse)
        async def dashboard(request: Request):
            return await self.render_dashboard(request)
        
        @self.app.get("/api/status")
        async def status():
            return {
                "connected": self.is_connected,
                "services": len(self.services),
                "bridge_ip": self.bridge_ip,
                "uptime": self.get_uptime()
            }
        
        @self.app.get("/api/services")
        async def get_services():
            return {"services": list(self.services.values())}
        
        @self.app.get("/api/qr")
        async def get_qr_code():
            qr_data = self.generate_connection_qr()
            return {"qr_data": qr_data}
        
        @self.app.get("/service/{service_name}/{path:path}")
        async def proxy_service(service_name: str, path: str, request: Request):
            return await self.proxy_request(service_name, path, request)

    async def start(self):
        """Start the TV bridge"""
        logger.info("Starting TV Bridge...")
        
        # Setup network bridge
        await self.setup_network_bridge()
        
        # Connect to VPN
        await self.connect_to_vpn()
        
        # Discover services
        await self.discover_services()
        
        # Advertise services
        await self.advertise_services()
        
        # Start web interface
        await self.start_web_interface()
        
        logger.info("TV Bridge started successfully")

    async def setup_network_bridge(self):
        """Setup network bridge for TV connectivity"""
        logger.info("Setting up network bridge...")
        
        try:
            # Create bridge interface
            subprocess.run(["ip", "link", "add", "name", "br0", "type", "bridge"], check=True)
            subprocess.run(["ip", "addr", "add", f"{self.bridge_ip}/24", "dev", "br0"], check=True)
            subprocess.run(["ip", "link", "set", "dev", "br0", "up"], check=True)
            
            # Setup iptables for NAT
            subprocess.run(["iptables", "-t", "nat", "-A", "POSTROUTING", "-o", "tailscale0", "-j", "MASQUERADE"], check=True)
            subprocess.run(["iptables", "-A", "FORWARD", "-i", "br0", "-o", "tailscale0", "-j", "ACCEPT"], check=True)
            subprocess.run(["iptables", "-A", "FORWARD", "-i", "tailscale0", "-o", "br0", "-j", "ACCEPT"], check=True)
            
            # Enable IP forwarding
            with open("/proc/sys/net/ipv4/ip_forward", "w") as f:
                f.write("1")
            
            logger.info("Network bridge setup completed")
            
        except subprocess.CalledProcessError as e:
            logger.error(f"Failed to setup network bridge: {e}")
            # Fallback to proxy-only mode
            logger.info("Falling back to proxy-only mode")

    async def connect_to_vpn(self):
        """Connect to the VPN using Tailscale"""
        logger.info("Connecting to VPN...")
        
        try:
            # Check if tailscale is already running
            result = subprocess.run(["tailscale", "status"], capture_output=True, text=True)
            
            if result.returncode == 0 and "logged in" in result.stdout.lower():
                logger.info("Already connected to VPN")
                self.is_connected = True
                return
            
            # Get auth key from environment
            auth_key = os.getenv("HEADSCALE_PREAUTH_KEY")
            headscale_url = os.getenv("HEADSCALE_URL", "http://headscale:8080")
            
            if not auth_key:
                logger.error("No HEADSCALE_PREAUTH_KEY provided")
                return
            
            # Connect to headscale
            cmd = [
                "tailscale", "up",
                f"--login-server={headscale_url}",
                f"--authkey={auth_key}",
                "--hostname=tv-bridge",
                "--accept-routes",
                "--accept-dns=false"
            ]
            
            result = subprocess.run(cmd, capture_output=True, text=True)
            
            if result.returncode == 0:
                logger.info("Successfully connected to VPN")
                self.is_connected = True
            else:
                logger.error(f"Failed to connect to VPN: {result.stderr}")
                
        except Exception as e:
            logger.error(f"VPN connection error: {e}")

    async def discover_services(self):
        """Discover available services through the VPN"""
        logger.info("Discovering services...")
        
        if not self.is_connected:
            logger.warning("Not connected to VPN, cannot discover services")
            return
        
        # Get services from environment or discovery API
        services_config = os.getenv("BRIDGE_SERVICES", "")
        
        if services_config:
            try:
                services = json.loads(services_config)
                for service in services:
                    self.services[service["name"]] = service
                logger.info(f"Loaded {len(services)} services from configuration")
            except json.JSONDecodeError:
                logger.error("Invalid services configuration")
        
        # Try to discover services automatically
        await self.auto_discover_services()

    async def auto_discover_services(self):
        """Automatically discover common services"""
        common_services = [
            {"name": "jellyfin", "port": 8096, "path": "/web/index.html"},
            {"name": "plex", "port": 32400, "path": "/web/index.html"},
            {"name": "homeassistant", "port": 8123, "path": "/"},
            {"name": "nextcloud", "port": 443, "path": "/"},
        ]
        
        # Get tailscale network range
        try:
            result = subprocess.run(["tailscale", "status", "--json"], capture_output=True, text=True)
            if result.returncode == 0:
                status = json.loads(result.stdout)
                peers = status.get("Peer", {})
                
                for peer_id, peer in peers.items():
                    peer_ip = peer.get("TailscaleIPs", [None])[0]
                    if peer_ip:
                        await self.probe_peer_services(peer_ip, common_services)
                        
        except Exception as e:
            logger.error(f"Failed to auto-discover services: {e}")

    async def probe_peer_services(self, ip: str, services: List[Dict]):
        """Probe a peer for common services"""
        async with aiohttp.ClientSession(timeout=aiohttp.ClientTimeout(total=5)) as session:
            for service in services:
                try:
                    url = f"http://{ip}:{service['port']}{service['path']}"
                    async with session.get(url) as response:
                        if response.status == 200:
                            service_info = {
                                "name": service["name"].title(),
                                "url": f"http://{ip}:{service['port']}",
                                "local_url": f"http://{self.bridge_ip}:8080/service/{service['name']}",
                                "icon": self.get_service_icon(service["name"]),
                                "category": self.get_service_category(service["name"])
                            }
                            self.services[service["name"]] = service_info
                            logger.info(f"Discovered service: {service['name']} at {ip}:{service['port']}")
                            
                except Exception:
                    continue  # Service not available

    def get_service_icon(self, service_name: str) -> str:
        """Get icon for service"""
        icons = {
            "jellyfin": "🎬",
            "plex": "🎭", 
            "homeassistant": "🏠",
            "nextcloud": "☁️",
            "pihole": "🛡️"
        }
        return icons.get(service_name.lower(), "🌐")

    def get_service_category(self, service_name: str) -> str:
        """Get category for service"""
        categories = {
            "jellyfin": "media",
            "plex": "media",
            "homeassistant": "automation",
            "nextcloud": "cloud",
            "pihole": "network"
        }
        return categories.get(service_name.lower(), "other")

    async def advertise_services(self):
        """Advertise services via mDNS for TV discovery"""
        logger.info("Advertising services via mDNS...")
        
        for service_name, service in self.services.items():
            try:
                # Create mDNS service info
                info = ServiceInfo(
                    "_http._tcp.local.",
                    f"{service_name}._http._tcp.local.",
                    addresses=[self.bridge_ip.encode()],
                    port=8080,
                    properties={
                        "path": f"/service/{service_name}/",
                        "name": service["name"],
                        "category": service["category"]
                    }
                )
                
                self.zeroconf.register_service(info)
                logger.info(f"Advertised service: {service_name}")
                
            except Exception as e:
                logger.error(f"Failed to advertise service {service_name}: {e}")

    async def proxy_request(self, service_name: str, path: str, request: Request):
        """Proxy request to actual service"""
        if service_name not in self.services:
            return JSONResponse({"error": "Service not found"}, status_code=404)
        
        service = self.services[service_name]
        target_url = f"{service['url']}/{path}"
        
        # Remove host header to avoid issues
        headers = dict(request.headers)
        headers.pop("host", None)
        
        try:
            async with aiohttp.ClientSession() as session:
                async with session.request(
                    method=request.method,
                    url=target_url,
                    headers=headers,
                    data=await request.body()
                ) as response:
                    content = await response.read()
                    
                    # Modify content to fix relative URLs
                    if response.content_type and "text/html" in response.content_type:
                        content = self.fix_html_urls(content.decode(), service_name)
                        content = content.encode()
                    
                    return Response(
                        content=content,
                        status_code=response.status,
                        headers=dict(response.headers)
                    )
                    
        except Exception as e:
            logger.error(f"Proxy error for {service_name}: {e}")
            return JSONResponse({"error": "Service unavailable"}, status_code=503)

    def fix_html_urls(self, html: str, service_name: str) -> str:
        """Fix relative URLs in HTML to work through proxy"""
        # Simple URL rewriting - in production, use a proper HTML parser
        html = html.replace('href="/', f'href="/service/{service_name}/')
        html = html.replace("href='/", f"href='/service/{service_name}/")
        html = html.replace('src="/', f'src="/service/{service_name}/')
        html = html.replace("src='/", f"src='/service/{service_name}/")
        return html

    def generate_connection_qr(self) -> str:
        """Generate QR code for TV connection"""
        connection_info = {
            "type": "tv_bridge",
            "bridge_ip": self.bridge_ip,
            "services": list(self.services.keys()),
            "setup_url": f"http://{self.bridge_ip}:8080"
        }
        
        qr = qrcode.QRCode(version=1, box_size=10, border=5)
        qr.add_data(json.dumps(connection_info))
        qr.make(fit=True)
        
        # Convert to base64 for web display
        import io
        import base64
        
        img = qr.make_image(fill_color="black", back_color="white")
        buffer = io.BytesIO()
        img.save(buffer, format='PNG')
        img_str = base64.b64encode(buffer.getvalue()).decode()
        
        return f"data:image/png;base64,{img_str}"

    async def render_dashboard(self, request: Request) -> str:
        """Render the web dashboard"""
        html = f"""
<!DOCTYPE html>
<html>
<head>
    <title>TV Bridge Dashboard</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        body {{ font-family: Arial, sans-serif; margin: 20px; background: #f5f5f5; }}
        .container {{ max-width: 800px; margin: 0 auto; background: white; padding: 20px; border-radius: 10px; }}
        .status {{ padding: 10px; border-radius: 5px; margin: 10px 0; }}
        .connected {{ background: #d4edda; color: #155724; }}
        .disconnected {{ background: #f8d7da; color: #721c24; }}
        .service {{ border: 1px solid #ddd; padding: 15px; margin: 10px 0; border-radius: 5px; }}
        .service h3 {{ margin: 0 0 10px 0; }}
        .qr-code {{ text-align: center; margin: 20px 0; }}
        .instructions {{ background: #e7f3ff; padding: 15px; border-radius: 5px; margin: 20px 0; }}
    </style>
</head>
<body>
    <div class="container">
        <h1>📺 TV Bridge Dashboard</h1>
        
        <div class="status {'connected' if self.is_connected else 'disconnected'}">
            <strong>Status:</strong> {'🟢 Connected to VPN' if self.is_connected else '🔴 Not Connected'}
        </div>
        
        <div class="instructions">
            <h3>📱 TV Setup Instructions</h3>
            <ol>
                <li><strong>Connect TV to Network:</strong> Connect your TV to the same network as this bridge device</li>
                <li><strong>Open TV Browser:</strong> Open the web browser on your smart TV</li>
                <li><strong>Navigate to Bridge:</strong> Go to <code>http://{self.bridge_ip}:8080</code></li>
                <li><strong>Access Services:</strong> Click on any service below to access it</li>
            </ol>
        </div>
        
        <h2>🎯 Available Services ({len(self.services)})</h2>
        """
        
        for service_name, service in self.services.items():
            html += f"""
        <div class="service">
            <h3>{service['icon']} {service['name']}</h3>
            <p><strong>Category:</strong> {service['category']}</p>
            <p><strong>TV URL:</strong> <a href="/service/{service_name}/" target="_blank">http://{self.bridge_ip}:8080/service/{service_name}/</a></p>
            <p><strong>Original:</strong> {service['url']}</p>
        </div>
            """
        
        if not self.services:
            html += "<p>No services discovered yet. Make sure you're connected to the VPN and services are running.</p>"
        
        html += f"""
        <div class="qr-code">
            <h3>📱 Quick Setup QR Code</h3>
            <p>Scan with your phone to get connection details:</p>
            <img src="/api/qr" alt="Connection QR Code" style="max-width: 200px;">
        </div>
        
        <h2>🔧 Bridge Information</h2>
        <ul>
            <li><strong>Bridge IP:</strong> {self.bridge_ip}</li>
            <li><strong>VPN Status:</strong> {'Connected' if self.is_connected else 'Disconnected'}</li>
            <li><strong>Services:</strong> {len(self.services)} discovered</li>
            <li><strong>Uptime:</strong> {self.get_uptime()}</li>
        </ul>
        
        <script>
            // Auto-refresh every 30 seconds
            setTimeout(() => location.reload(), 30000);
        </script>
    </div>
</body>
</html>
        """
        
        return html

    def get_uptime(self) -> str:
        """Get system uptime"""
        try:
            with open("/proc/uptime", "r") as f:
                uptime_seconds = float(f.readline().split()[0])
                hours = int(uptime_seconds // 3600)
                minutes = int((uptime_seconds % 3600) // 60)
                return f"{hours}h {minutes}m"
        except:
            return "Unknown"

    async def start_web_interface(self):
        """Start the web interface"""
        import uvicorn
        
        config = uvicorn.Config(
            app=self.app,
            host="0.0.0.0",
            port=8080,
            log_level="info"
        )
        
        server = uvicorn.Server(config)
        await server.serve()

if __name__ == "__main__":
    bridge = TVBridge()
    asyncio.run(bridge.start())