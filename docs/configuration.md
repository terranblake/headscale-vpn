# Configuration Guide

## Initial Setup

1. **Clone and setup**:
   ```bash
   git clone <this-repo>
   cd headscale-vpn
   ./setup.sh
   ```

2. **Edit environment variables**:
   ```bash
   nano .env
   ```
   Set your NordVPN credentials and other preferences.

3. **Start the deployment**:
   ```bash
   docker-compose up -d
   ```

## Managing Users and Devices

### Create a user
```bash
docker exec headscale headscale users create admin
```

### Generate device auth key
```bash
docker exec headscale headscale preauthkeys create --user admin
```

### List devices
```bash
docker exec headscale headscale nodes list
```

### Enable exit node
```bash
docker exec headscale headscale routes enable -r <route-id>
```

## Client Setup

### Linux/macOS
```bash
# Install tailscale (use package manager or download)
sudo tailscale up --login-server=http://your-headscale-server:8080 --authkey=<your-auth-key>
```

### Use exit node
```bash
tailscale up --exit-node=vpn-exit-node
```

### Use proxy gateway
Configure your device to use the proxy gateway IP:8080 as HTTP/HTTPS proxy.

## Monitoring

### Check headscale status
```bash
docker exec headscale headscale nodes list
docker logs headscale
```

### Check VPN exit node
```bash
docker logs vpn-exit-node
docker exec vpn-exit-node tailscale status
```

### Check proxy gateway
```bash
docker logs proxy-gateway
# Web UI: http://proxy-gateway-ip:8081
```

## Troubleshooting

### Headscale not accessible
- Check if port 8080 is open
- Verify HEADSCALE_SERVER_URL in .env

### VPN connection fails
- Check NordVPN credentials in .env
- Verify docker container has privileged access

### Devices can't connect
- Ensure auth key is valid: `docker exec headscale headscale preauthkeys list`
- Check firewall rules on host
