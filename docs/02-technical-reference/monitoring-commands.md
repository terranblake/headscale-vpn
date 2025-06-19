# Monitoring Commands Guide

Comprehensive monitoring and observability commands for the Family Network Platform.

## Table of Contents

- [System Health Monitoring](#system-health-monitoring)
- [Prometheus Metrics](#prometheus-metrics)
- [Grafana Dashboards](#grafana-dashboards)
- [Log Analysis](#log-analysis)
- [Performance Monitoring](#performance-monitoring)
- [Alerting](#alerting)
- [Troubleshooting Commands](#troubleshooting-commands)

## System Health Monitoring

### Quick Health Check

#### Built-in Health Check
```bash
# Run comprehensive health check
make health-check

# Check specific services
make health-check SERVICE=headscale
make health-check SERVICE=streamyfin
make health-check SERVICE=traefik
```

#### Manual Health Verification
```bash
# Check all containers status
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Check container health
docker inspect --format='{{.State.Health.Status}}' headscale
docker inspect --format='{{.State.Health.Status}}' streamyfin
docker inspect --format='{{.State.Health.Status}}' traefik
```

### Service Availability

#### HTTP Service Checks
```bash
# Check web services
curl -I https://streamyfin.family.local
curl -I https://photos.family.local
curl -I https://docs.family.local

# Check with timeout
curl -I --max-time 5 https://streamyfin.family.local

# Check internal services
curl -I http://localhost:8096  # Streamyfin internal
curl -I http://localhost:8080  # Traefik dashboard
```

#### VPN Connectivity Checks
```bash
# Check headscale API
curl -I http://localhost:8080/health

# List connected nodes
docker exec -it headscale headscale nodes list

# Check node connectivity
docker exec -it headscale headscale debug ping <node-name>
```

### Resource Monitoring

#### Container Resource Usage
```bash
# Real-time resource monitoring
docker stats

# Specific container stats
docker stats headscale streamyfin traefik --no-stream

# Memory usage details
docker exec headscale cat /proc/meminfo | head -5
docker exec streamyfin cat /proc/meminfo | head -5
```

#### System Resources
```bash
# CPU and memory overview
htop

# Disk usage
df -h
du -sh /var/lib/docker/volumes/*

# Network interfaces
ip addr show
ss -tuln | grep -E ':(80|443|8080|8096|9090|3000)'
```

## Prometheus Metrics

### Accessing Metrics

#### Prometheus Web Interface
```bash
# Access Prometheus UI
open http://localhost:9090

# Or via curl
curl http://localhost:9090/api/v1/query?query=up
```

#### Raw Metrics Endpoints
```bash
# Headscale metrics
curl http://localhost:9090/metrics | grep headscale

# Node exporter metrics (if enabled)
curl http://localhost:9100/metrics

# Container metrics
curl http://localhost:8080/metrics | grep container
```

### Key Metrics Queries

#### System Health Metrics
```promql
# Service uptime
up{job="headscale"}
up{job="streamyfin"}
up{job="traefik"}

# Container restart count
increase(container_start_time_seconds[1h])

# Memory usage percentage
(container_memory_usage_bytes / container_spec_memory_limit_bytes) * 100
```

#### VPN-Specific Metrics
```promql
# Connected nodes count
headscale_nodes_total

# Active connections
headscale_connections_active

# Data transfer rates
rate(headscale_bytes_sent_total[5m])
rate(headscale_bytes_received_total[5m])
```

#### Performance Metrics
```promql
# HTTP request duration
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))

# Error rates
rate(http_requests_total{status=~"5.."}[5m])

# Disk I/O
rate(container_fs_reads_bytes_total[5m])
rate(container_fs_writes_bytes_total[5m])
```

### Custom Metric Queries

#### Family Usage Patterns
```bash
# Query active users in last 24h
curl -G 'http://localhost:9090/api/v1/query' \
  --data-urlencode 'query=increase(headscale_user_connections_total[24h])'

# Service access patterns
curl -G 'http://localhost:9090/api/v1/query' \
  --data-urlencode 'query=rate(traefik_service_requests_total[1h])'
```

#### Performance Analysis
```bash
# Average response times
curl -G 'http://localhost:9090/api/v1/query' \
  --data-urlencode 'query=avg(rate(http_request_duration_seconds_sum[5m]) / rate(http_request_duration_seconds_count[5m]))'

# Resource utilization trends
curl -G 'http://localhost:9090/api/v1/query_range' \
  --data-urlencode 'query=container_memory_usage_bytes{name="streamyfin"}' \
  --data-urlencode 'start=2024-06-19T00:00:00Z' \
  --data-urlencode 'end=2024-06-19T23:59:59Z' \
  --data-urlencode 'step=1h'
```

## Grafana Dashboards

### Accessing Grafana

#### Web Interface
```bash
# Access Grafana UI
open http://localhost:3000

# Default credentials (change after first login)
# Username: admin
# Password: admin
```

#### Dashboard Management
```bash
# Import dashboard via API
curl -X POST \
  http://admin:admin@localhost:3000/api/dashboards/db \
  -H 'Content-Type: application/json' \
  -d @config/grafana/dashboards/family-network.json

# Export dashboard
curl -H 'Authorization: Bearer <api-key>' \
  http://localhost:3000/api/dashboards/uid/<dashboard-uid> > dashboard-backup.json
```

### Key Dashboards

#### Family Network Overview
- **URL:** `http://localhost:3000/d/family-overview`
- **Panels:**
  - Active family members
  - Service availability
  - Data transfer rates
  - System resource usage

#### Service Performance
- **URL:** `http://localhost:3000/d/service-performance`
- **Panels:**
  - Response times by service
  - Error rates
  - Throughput metrics
  - Resource utilization

#### VPN Connectivity
- **URL:** `http://localhost:3000/d/vpn-connectivity`
- **Panels:**
  - Connected devices
  - Connection stability
  - Geographic distribution
  - Authentication events

### Dashboard Queries

#### Family Activity Panel
```promql
# Active family members (last 1h)
count(increase(headscale_user_last_seen[1h]) > 0)

# Most active services
topk(5, rate(traefik_service_requests_total[1h]))
```

#### System Health Panel
```promql
# Service availability
avg(up{job=~"headscale|streamyfin|traefik"}) * 100

# Memory usage by service
container_memory_usage_bytes{name=~"headscale|streamyfin|traefik"}
```

## Log Analysis

### Container Logs

#### Basic Log Viewing
```bash
# View recent logs
docker logs headscale --tail 100
docker logs streamyfin --tail 100
docker logs traefik --tail 100

# Follow logs in real-time
docker logs headscale --follow

# Logs with timestamps
docker logs headscale --timestamps --since 1h
```

#### Filtered Log Analysis
```bash
# Filter by log level
docker logs headscale 2>&1 | grep -E "(ERROR|WARN)"

# Filter by user activity
docker logs headscale 2>&1 | grep "alice"

# Filter by service access
docker logs traefik 2>&1 | grep "streamyfin.family.local"
```

### Structured Log Analysis

#### JSON Log Parsing
```bash
# Parse JSON logs with jq
docker logs headscale --since 1h 2>&1 | \
  grep '^{' | jq -r 'select(.level=="error") | .msg'

# Extract specific fields
docker logs traefik --since 1h 2>&1 | \
  grep '^{' | jq -r '.ClientHost + " -> " + .RequestHost'
```

#### Log Aggregation
```bash
# Count log levels
docker logs headscale --since 24h 2>&1 | \
  grep -oE "(INFO|WARN|ERROR|DEBUG)" | sort | uniq -c

# Top error messages
docker logs headscale --since 24h 2>&1 | \
  grep ERROR | sort | uniq -c | sort -nr | head -10
```

### System Logs

#### Service Logs
```bash
# Systemd service logs (if applicable)
journalctl -u docker --since "1 hour ago"

# System authentication logs
sudo tail -f /var/log/auth.log

# Firewall logs
sudo tail -f /var/log/ufw.log
```

#### Network Logs
```bash
# Connection tracking
sudo netstat -tuln | grep -E ':(80|443|8080|8096)'

# Active connections
sudo ss -tuln | grep LISTEN

# Network interface statistics
cat /proc/net/dev
```

## Performance Monitoring

### Response Time Monitoring

#### HTTP Response Times
```bash
# Test service response times
time curl -s https://streamyfin.family.local > /dev/null
time curl -s https://photos.family.local > /dev/null

# Detailed timing with curl
curl -w "@curl-format.txt" -s https://streamyfin.family.local > /dev/null

# Create curl timing format file
cat > curl-format.txt << 'EOF'
     time_namelookup:  %{time_namelookup}\n
        time_connect:  %{time_connect}\n
     time_appconnect:  %{time_appconnect}\n
    time_pretransfer:  %{time_pretransfer}\n
       time_redirect:  %{time_redirect}\n
  time_starttransfer:  %{time_starttransfer}\n
                     ----------\n
          time_total:  %{time_total}\n
EOF
```

#### VPN Performance
```bash
# Test VPN latency
docker exec -it headscale headscale debug ping <node-name>

# Bandwidth testing between nodes
# (requires iperf3 on client devices)
iperf3 -s -p 5201  # On server
iperf3 -c <server-ip> -p 5201  # On client
```

### Resource Performance

#### CPU Monitoring
```bash
# CPU usage by container
docker stats --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}"

# System CPU usage
top -bn1 | grep "Cpu(s)"
vmstat 1 5
```

#### Memory Analysis
```bash
# Memory usage details
free -h
cat /proc/meminfo | grep -E "(MemTotal|MemFree|MemAvailable|Cached)"

# Container memory details
docker exec headscale cat /proc/meminfo | head -10
```

#### Disk I/O Monitoring
```bash
# Disk I/O statistics
iostat -x 1 5

# Disk usage by container volumes
docker system df -v

# File system usage
df -h
du -sh /var/lib/docker/volumes/*
```

### Network Performance

#### Bandwidth Monitoring
```bash
# Network interface statistics
cat /proc/net/dev

# Real-time network monitoring
iftop -i eth0
nethogs

# Connection statistics
ss -s
netstat -i
```

#### DNS Performance
```bash
# DNS resolution timing
dig @8.8.8.8 streamyfin.family.local +stats
nslookup streamyfin.family.local

# Local DNS cache performance
systemd-resolve --statistics
```

## Alerting

### Prometheus Alerting Rules

#### Service Availability Alerts
```yaml
# config/prometheus/alerts/service-availability.yml
groups:
  - name: service-availability
    rules:
      - alert: ServiceDown
        expr: up == 0
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Service {{ $labels.instance }} is down"
          
      - alert: HighErrorRate
        expr: rate(http_requests_total{status=~"5.."}[5m]) > 0.1
        for: 2m
        labels:
          severity: warning
        annotations:
          summary: "High error rate on {{ $labels.service }}"
```

#### Resource Usage Alerts
```yaml
# config/prometheus/alerts/resource-usage.yml
groups:
  - name: resource-usage
    rules:
      - alert: HighMemoryUsage
        expr: (container_memory_usage_bytes / container_spec_memory_limit_bytes) * 100 > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High memory usage on {{ $labels.name }}"
          
      - alert: DiskSpaceLow
        expr: (node_filesystem_avail_bytes / node_filesystem_size_bytes) * 100 < 10
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Disk space low on {{ $labels.mountpoint }}"
```

### Alert Testing

#### Manual Alert Testing
```bash
# Test alert rules syntax
docker exec prometheus promtool check rules /etc/prometheus/alerts/*.yml

# Query alert status
curl http://localhost:9090/api/v1/alerts

# Test specific alert condition
curl -G 'http://localhost:9090/api/v1/query' \
  --data-urlencode 'query=up == 0'
```

#### Alertmanager Configuration
```bash
# Check alertmanager status
curl http://localhost:9093/api/v1/status

# View active alerts
curl http://localhost:9093/api/v1/alerts

# Test notification
curl -X POST http://localhost:9093/api/v1/alerts \
  -H 'Content-Type: application/json' \
  -d '[{"labels":{"alertname":"TestAlert","severity":"warning"}}]'
```

## Troubleshooting Commands

### Quick Diagnostics

#### System Overview
```bash
# One-command system overview
echo "=== System Status ===" && \
docker ps --format "table {{.Names}}\t{{.Status}}" && \
echo -e "\n=== Resource Usage ===" && \
docker stats --no-stream && \
echo -e "\n=== Disk Usage ===" && \
df -h | grep -E "(Filesystem|/dev/)"
```

#### Service Connectivity
```bash
# Test all service endpoints
services=("streamyfin.family.local" "photos.family.local" "docs.family.local")
for service in "${services[@]}"; do
  echo "Testing $service:"
  curl -I --max-time 5 "https://$service" 2>/dev/null | head -1 || echo "  FAILED"
done
```

### Performance Diagnostics

#### Identify Performance Bottlenecks
```bash
# CPU-intensive processes
docker exec headscale top -bn1 | head -20

# Memory usage by process
docker exec streamyfin ps aux --sort=-%mem | head -10

# I/O wait times
iostat -x 1 3 | grep -E "(Device|avg-cpu)"
```

#### Network Diagnostics
```bash
# Check listening ports
ss -tuln | grep -E ':(80|443|8080|8096|9090|3000)'

# Test internal connectivity
docker exec headscale ping -c 3 streamyfin
docker exec streamyfin ping -c 3 headscale

# DNS resolution test
docker exec headscale nslookup streamyfin.family.local
```

### Log-Based Troubleshooting

#### Error Pattern Analysis
```bash
# Find common error patterns
docker logs headscale --since 1h 2>&1 | \
  grep -i error | \
  sed 's/[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}T[0-9:]*Z/TIMESTAMP/g' | \
  sort | uniq -c | sort -nr

# Authentication failures
docker logs headscale --since 24h 2>&1 | grep -i "auth.*fail"

# Connection issues
docker logs traefik --since 1h 2>&1 | grep -E "(timeout|refused|unreachable)"
```

#### Performance Issue Detection
```bash
# Slow requests
docker logs traefik --since 1h 2>&1 | \
  grep -oE '"duration":[0-9]+' | \
  sed 's/"duration"://' | \
  sort -n | tail -10

# High memory usage events
docker logs streamyfin --since 1h 2>&1 | grep -i "memory\|oom"
```

## Monitoring Scripts

### Automated Health Checks

#### Create Monitoring Script
```bash
# Create comprehensive monitoring script
cat > scripts/monitor-system.sh << 'EOF'
#!/bin/bash

echo "=== Family Network Platform Health Check ==="
echo "Timestamp: $(date)"
echo

# Service status
echo "=== Service Status ==="
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "(headscale|streamyfin|traefik)"
echo

# Resource usage
echo "=== Resource Usage ==="
docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}"
echo

# Service connectivity
echo "=== Service Connectivity ==="
services=("streamyfin.family.local" "photos.family.local")
for service in "${services[@]}"; do
  if curl -I --max-time 5 "https://$service" &>/dev/null; then
    echo "✓ $service - OK"
  else
    echo "✗ $service - FAILED"
  fi
done
echo

# VPN status
echo "=== VPN Status ==="
node_count=$(docker exec -it headscale headscale nodes list 2>/dev/null | grep -c "^[0-9]" || echo "0")
echo "Connected nodes: $node_count"
echo

echo "=== Health Check Complete ==="
EOF

chmod +x scripts/monitor-system.sh
```

#### Scheduled Monitoring
```bash
# Add to crontab for regular monitoring
echo "*/15 * * * * /path/to/headscale-vpn/scripts/monitor-system.sh >> /var/log/family-network-health.log 2>&1" | crontab -
```

### Performance Monitoring

#### Create Performance Monitor
```bash
cat > scripts/performance-monitor.sh << 'EOF'
#!/bin/bash

LOG_FILE="/var/log/family-network-performance.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Function to log with timestamp
log_metric() {
  echo "[$TIMESTAMP] $1" >> "$LOG_FILE"
}

# CPU usage
CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//')
log_metric "CPU_USAGE: $CPU_USAGE"

# Memory usage
MEM_USAGE=$(free | grep Mem | awk '{printf "%.1f", $3/$2 * 100.0}')
log_metric "MEMORY_USAGE: $MEM_USAGE%"

# Disk usage
DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}')
log_metric "DISK_USAGE: $DISK_USAGE"

# Service response times
for service in streamyfin.family.local photos.family.local; do
  RESPONSE_TIME=$(curl -w "%{time_total}" -s -o /dev/null "https://$service" 2>/dev/null || echo "timeout")
  log_metric "RESPONSE_TIME_${service}: ${RESPONSE_TIME}s"
done

# Connected VPN nodes
VPN_NODES=$(docker exec -it headscale headscale nodes list 2>/dev/null | grep -c "^[0-9]" || echo "0")
log_metric "VPN_NODES: $VPN_NODES"
EOF

chmod +x scripts/performance-monitor.sh
```

## Quick Reference

### Essential Commands
```bash
# Health check
make health-check

# View all logs
docker logs headscale --tail 50
docker logs streamyfin --tail 50
docker logs traefik --tail 50

# Resource monitoring
docker stats --no-stream

# Service connectivity
curl -I https://streamyfin.family.local

# VPN status
docker exec -it headscale headscale nodes list

# Prometheus metrics
curl http://localhost:9090/metrics | grep headscale

# System resources
htop
df -h
```

### Emergency Commands
```bash
# Restart all services
docker restart headscale streamyfin traefik

# Check critical errors
docker logs headscale 2>&1 | grep -i error | tail -10

# Free up disk space
docker system prune -f

# Reset networking (if needed)
docker network prune -f
```

---

This monitoring guide provides comprehensive observability for the Family Network Platform. Use these commands regularly to maintain optimal performance and quickly identify issues. For automated monitoring, consider implementing the provided scripts and Prometheus alerting rules.