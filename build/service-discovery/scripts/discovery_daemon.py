#!/usr/bin/env python3
"""
Service Discovery Daemon
Automatically discovers and catalogs services on the home network
"""

import asyncio
import json
import logging
import os
import time
from datetime import datetime, timedelta
from typing import Dict, List, Optional

import nmap
import requests
from zeroconf import ServiceBrowser, ServiceListener, Zeroconf
from sqlalchemy import create_engine, Column, Integer, String, DateTime, Text, Boolean
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Database setup
DATABASE_URL = os.getenv("DATABASE_URL", "postgresql://headscale:password@headscale-db:5432/headscale")
engine = create_engine(DATABASE_URL)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()

class DiscoveredService(Base):
    __tablename__ = "discovered_services"
    
    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, index=True)
    description = Column(Text)
    internal_url = Column(String, unique=True, index=True)
    external_url = Column(String)
    category = Column(String)
    icon_url = Column(String)
    health_check_url = Column(String)
    service_type = Column(String)
    port = Column(Integer)
    protocol = Column(String)
    is_active = Column(Boolean, default=True)
    last_seen = Column(DateTime, default=datetime.utcnow)
    created_at = Column(DateTime, default=datetime.utcnow)
    metadata = Column(Text)  # JSON string for additional data

# Create tables
Base.metadata.create_all(bind=engine)

class ServiceDetector:
    """Detects and categorizes network services"""
    
    def __init__(self):
        self.known_services = {
            8096: {"name": "Jellyfin", "category": "media", "icon": "🎬"},
            32400: {"name": "Plex", "category": "media", "icon": "🎭"},
            8123: {"name": "Home Assistant", "category": "automation", "icon": "🏠"},
            8080: {"name": "Web Service", "category": "web", "icon": "🌐"},
            443: {"name": "HTTPS Service", "category": "web", "icon": "🔒"},
            80: {"name": "HTTP Service", "category": "web", "icon": "🌐"},
            3000: {"name": "Development Server", "category": "development", "icon": "💻"},
            8000: {"name": "Development Server", "category": "development", "icon": "💻"},
            9000: {"name": "Portainer", "category": "management", "icon": "🐳"},
            5000: {"name": "Flask/Development", "category": "development", "icon": "🐍"},
            3001: {"name": "Grafana", "category": "monitoring", "icon": "📊"},
            9090: {"name": "Prometheus", "category": "monitoring", "icon": "📈"},
            8086: {"name": "InfluxDB", "category": "database", "icon": "📊"},
            5432: {"name": "PostgreSQL", "category": "database", "icon": "🗄️"},
            3306: {"name": "MySQL", "category": "database", "icon": "🗄️"},
            6379: {"name": "Redis", "category": "database", "icon": "⚡"},
            22: {"name": "SSH", "category": "system", "icon": "🔧"},
            21: {"name": "FTP", "category": "file", "icon": "📁"},
            445: {"name": "SMB/CIFS", "category": "file", "icon": "📁"},
            139: {"name": "NetBIOS", "category": "file", "icon": "📁"},
            2049: {"name": "NFS", "category": "file", "icon": "📁"},
        }
        
        self.service_patterns = {
            "jellyfin": {
                "paths": ["/web/index.html", "/health"],
                "headers": {"X-Application": "Jellyfin"},
                "category": "media"
            },
            "plex": {
                "paths": ["/web/index.html", "/identity"],
                "headers": {"X-Plex-Product": "Plex Media Server"},
                "category": "media"
            },
            "homeassistant": {
                "paths": ["/", "/api/"],
                "content": ["Home Assistant", "hass"],
                "category": "automation"
            },
            "nextcloud": {
                "paths": ["/", "/status.php"],
                "headers": {"X-Powered-By": "Nextcloud"},
                "category": "cloud"
            },
            "pihole": {
                "paths": ["/admin/", "/"],
                "content": ["Pi-hole", "pihole"],
                "category": "network"
            }
        }

    async def scan_network(self, network_range: str = "192.168.1.0/24") -> List[Dict]:
        """Scan network for active hosts and services"""
        logger.info(f"Scanning network: {network_range}")
        
        nm = nmap.PortScanner()
        
        # Scan for common service ports
        common_ports = "21,22,23,25,53,80,110,143,443,993,995,1723,3000,3001,3306,5000,5432,6379,8000,8080,8086,8096,8123,9000,9090,32400"
        
        try:
            nm.scan(network_range, common_ports, arguments='-sS -O --version-detection')
        except Exception as e:
            logger.error(f"Network scan failed: {e}")
            return []
        
        discovered_services = []
        
        for host in nm.all_hosts():
            if nm[host].state() == 'up':
                logger.info(f"Scanning host: {host}")
                
                for protocol in nm[host].all_protocols():
                    ports = nm[host][protocol].keys()
                    
                    for port in ports:
                        port_info = nm[host][protocol][port]
                        if port_info['state'] == 'open':
                            service = await self.identify_service(host, port, port_info)
                            if service:
                                discovered_services.append(service)
        
        return discovered_services

    async def identify_service(self, host: str, port: int, port_info: Dict) -> Optional[Dict]:
        """Identify and categorize a service"""
        service_name = port_info.get('name', 'unknown')
        service_product = port_info.get('product', '')
        service_version = port_info.get('version', '')
        
        # Get base service info
        base_info = self.known_services.get(port, {
            "name": f"Service on {port}",
            "category": "unknown",
            "icon": "❓"
        })
        
        # Try to get more specific information via HTTP
        service_details = await self.probe_http_service(host, port)
        
        service = {
            "name": service_details.get("name", base_info["name"]),
            "description": f"{service_product} {service_version}".strip(),
            "internal_url": f"http://{host}:{port}",
            "category": service_details.get("category", base_info["category"]),
            "icon_url": base_info["icon"],
            "service_type": service_name,
            "port": port,
            "protocol": "tcp",
            "host": host,
            "metadata": json.dumps({
                "product": service_product,
                "version": service_version,
                "nmap_info": port_info,
                "http_info": service_details
            })
        }
        
        # Set health check URL
        if port in [80, 443, 8080, 8096, 32400, 8123]:
            service["health_check_url"] = service["internal_url"]
        
        return service

    async def probe_http_service(self, host: str, port: int) -> Dict:
        """Probe HTTP service for more details"""
        details = {}
        
        for scheme in ['http', 'https']:
            if scheme == 'https' and port not in [443, 8443]:
                continue
            if scheme == 'http' and port == 443:
                continue
                
            url = f"{scheme}://{host}:{port}"
            
            try:
                response = requests.get(url, timeout=5, verify=False)
                
                # Check headers for service identification
                for service_name, patterns in self.service_patterns.items():
                    if self.matches_service_pattern(response, patterns):
                        details.update({
                            "name": service_name.title(),
                            "category": patterns["category"],
                            "detected_via": "http_probe"
                        })
                        break
                
                # Store response info
                details.update({
                    "status_code": response.status_code,
                    "headers": dict(response.headers),
                    "title": self.extract_title(response.text) if response.text else None
                })
                
                break  # Success, no need to try other schemes
                
            except Exception as e:
                logger.debug(f"HTTP probe failed for {url}: {e}")
                continue
        
        return details

    def matches_service_pattern(self, response, patterns: Dict) -> bool:
        """Check if HTTP response matches service patterns"""
        # Check headers
        if "headers" in patterns:
            for header, value in patterns["headers"].items():
                if response.headers.get(header) == value:
                    return True
        
        # Check content
        if "content" in patterns and response.text:
            for content in patterns["content"]:
                if content.lower() in response.text.lower():
                    return True
        
        return False

    def extract_title(self, html: str) -> Optional[str]:
        """Extract title from HTML"""
        try:
            import re
            match = re.search(r'<title[^>]*>([^<]+)</title>', html, re.IGNORECASE)
            return match.group(1).strip() if match else None
        except:
            return None

class mDNSListener(ServiceListener):
    """Listen for mDNS/Bonjour services"""
    
    def __init__(self, callback):
        self.callback = callback
        self.services = {}

    def add_service(self, zeroconf, type, name):
        info = zeroconf.get_service_info(type, name)
        if info:
            service = {
                "name": name.split('.')[0],
                "type": type,
                "host": str(info.server),
                "port": info.port,
                "addresses": [str(addr) for addr in info.addresses],
                "properties": {k.decode(): v.decode() if isinstance(v, bytes) else v 
                             for k, v in info.properties.items()}
            }
            self.services[name] = service
            self.callback(service)

    def remove_service(self, zeroconf, type, name):
        if name in self.services:
            del self.services[name]

    def update_service(self, zeroconf, type, name):
        self.add_service(zeroconf, type, name)

class ServiceDiscoveryDaemon:
    """Main service discovery daemon"""
    
    def __init__(self):
        self.detector = ServiceDetector()
        self.db_session = SessionLocal()
        self.scan_interval = int(os.getenv("SCAN_INTERVAL", "300"))  # 5 minutes
        
    async def start(self):
        """Start the discovery daemon"""
        logger.info("Starting Service Discovery Daemon")
        
        # Start mDNS discovery
        asyncio.create_task(self.start_mdns_discovery())
        
        # Start periodic network scanning
        while True:
            try:
                await self.discover_services()
                await asyncio.sleep(self.scan_interval)
            except Exception as e:
                logger.error(f"Discovery cycle failed: {e}")
                await asyncio.sleep(60)  # Wait 1 minute before retry

    async def start_mdns_discovery(self):
        """Start mDNS service discovery"""
        def on_mdns_service(service):
            logger.info(f"Found mDNS service: {service['name']}")
            # Process mDNS service
            
        zeroconf = Zeroconf()
        listener = mDNSListener(on_mdns_service)
        
        # Listen for common service types
        service_types = [
            "_http._tcp.local.",
            "_https._tcp.local.",
            "_plex._tcp.local.",
            "_homeassistant._tcp.local.",
            "_smb._tcp.local.",
            "_ssh._tcp.local.",
        ]
        
        browsers = []
        for service_type in service_types:
            browser = ServiceBrowser(zeroconf, service_type, listener)
            browsers.append(browser)
        
        # Keep mDNS discovery running
        try:
            while True:
                await asyncio.sleep(60)
        finally:
            zeroconf.close()

    async def discover_services(self):
        """Run service discovery cycle"""
        logger.info("Starting service discovery cycle")
        
        # Get network range from environment or detect automatically
        network_range = os.getenv("NETWORK_RANGE", "192.168.1.0/24")
        
        # Scan network
        services = await self.detector.scan_network(network_range)
        
        # Update database
        for service_data in services:
            await self.update_service_in_db(service_data)
        
        # Mark inactive services
        await self.mark_inactive_services()
        
        logger.info(f"Discovery cycle completed. Found {len(services)} services")

    async def update_service_in_db(self, service_data: Dict):
        """Update service in database"""
        try:
            # Check if service already exists
            existing = self.db_session.query(DiscoveredService).filter_by(
                internal_url=service_data["internal_url"]
            ).first()
            
            if existing:
                # Update existing service
                for key, value in service_data.items():
                    if hasattr(existing, key):
                        setattr(existing, key, value)
                existing.last_seen = datetime.utcnow()
                existing.is_active = True
            else:
                # Create new service
                service = DiscoveredService(**service_data)
                self.db_session.add(service)
            
            self.db_session.commit()
            
        except Exception as e:
            logger.error(f"Failed to update service in DB: {e}")
            self.db_session.rollback()

    async def mark_inactive_services(self):
        """Mark services as inactive if not seen recently"""
        cutoff_time = datetime.utcnow() - timedelta(minutes=self.scan_interval * 2)
        
        try:
            inactive_services = self.db_session.query(DiscoveredService).filter(
                DiscoveredService.last_seen < cutoff_time,
                DiscoveredService.is_active == True
            ).all()
            
            for service in inactive_services:
                service.is_active = False
                logger.info(f"Marked service as inactive: {service.name} ({service.internal_url})")
            
            self.db_session.commit()
            
        except Exception as e:
            logger.error(f"Failed to mark inactive services: {e}")
            self.db_session.rollback()

if __name__ == "__main__":
    daemon = ServiceDiscoveryDaemon()
    asyncio.run(daemon.start())