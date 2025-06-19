# Troubleshooting Guide

## Common Issues

### 1. Headscale container won't start
**Symptoms**: Container exits immediately, database connection errors

**Solutions**:
- Check database password in .env matches docker-compose.yml
- Ensure headscale-db container is healthy: `docker-compose ps`
- Check logs: `docker logs headscale-db`

### 2. VPN exit node can't connect to NordVPN
**Symptoms**: No internet through exit node, OpenVPN errors

**Solutions**:
- Verify NordVPN credentials in .env
- Check if container has proper privileges: `--privileged=true`
- Test NordVPN credentials manually
- Try different server region in NORDVPN_SERVER

### 3. Devices can't authenticate with Headscale
**Symptoms**: Authentication failures, "failed to connect" errors

**Solutions**:
- Check if Headscale is accessible: `curl http://your-server:8080/health`
- Verify auth key: `docker exec headscale headscale preauthkeys list`
- Create new auth key: `docker exec headscale headscale preauthkeys create --user admin`

### 4. Traffic not going through VPN
**Symptoms**: Real IP visible, no anonymization

**Solutions**:
- Enable exit node: `tailscale up --exit-node=vpn-exit-node`
- Check exit node status: `docker exec vpn-exit-node tailscale status`
- Verify VPN connection: `docker exec vpn-exit-node curl ifconfig.me`

### 5. Bypass rules not working
**Symptoms**: Local traffic going through VPN

**Solutions**:
- Check bypass configuration in config/vpn-exit/config.sh
- Verify routing rules: `docker exec vpn-exit-node ip rule list`
- Check DNS resolution for bypass domains

## Debug Commands

### Check Headscale status
```bash
docker exec headscale headscale nodes list
docker exec headscale headscale users list
docker exec headscale headscale routes list
```

### Check network connectivity
```bash
# From VPN exit node
docker exec vpn-exit-node curl ifconfig.me
docker exec vpn-exit-node ping google.com

# From proxy gateway  
docker exec proxy-gateway curl ifconfig.me
docker exec proxy-gateway tailscale status
```

### Check routing
```bash
# On exit node
docker exec vpn-exit-node ip route
docker exec vpn-exit-node ip rule list
docker exec vpn-exit-node iptables -t nat -L
```

### View logs
```bash
docker logs headscale
docker logs vpn-exit-node
docker logs proxy-gateway
docker logs headscale-db
```
