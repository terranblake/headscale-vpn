# Headscale VPN Management
# Simple commands for common operations

.PHONY: help setup up down logs status clean

help: ## Show this help message
	@echo "Headscale VPN Management Commands:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

setup: ## Initial setup (run once)
	@./setup.sh

up: ## Start all services
	@docker-compose up -d

down: ## Stop all services
	@docker-compose down

logs: ## Show logs for all services
	@docker-compose logs -f

status: ## Show status of all services
	@docker-compose ps

clean: ## Remove all containers and volumes (destructive!)
	@docker-compose down -v --remove-orphans
	@docker system prune -f

# Headscale operations
user-create: ## Create new user (usage: make user-create USER=username)
	@docker exec headscale headscale users create $(USER)

user-list: ## List all users
	@docker exec headscale headscale users list

key-create: ## Create auth key (usage: make key-create USER=username)
	@docker exec headscale headscale preauthkeys create --user $(USER)

key-list: ## List all auth keys
	@docker exec headscale headscale preauthkeys list

nodes-list: ## List all connected nodes
	@docker exec headscale headscale nodes list

routes-list: ## List all routes
	@docker exec headscale headscale routes list

routes-enable: ## Enable route (usage: make routes-enable ROUTE=route-id)
	@docker exec headscale headscale routes enable -r $(ROUTE)

# VPN operations
vpn-status: ## Check VPN exit node status
	@docker exec vpn-exit-node tailscale status

vpn-ip: ## Show VPN exit node external IP
	@docker exec vpn-exit-node curl -s ifconfig.me

# Proxy operations  
proxy-status: ## Check proxy gateway status
	@docker exec proxy-gateway tailscale status

proxy-certs: ## Show proxy certificates location
	@echo "Proxy certificates are in: ./data/proxy/certs/"
	@docker exec proxy-gateway ls -la /root/.mitmproxy/

# Testing and monitoring
test: ## Run integration tests
	@./tests/integration_test.sh

health: ## Run health check
	@./scripts/health-check.sh check

monitor: ## Start continuous health monitoring
	@./scripts/health-check.sh monitor

# Backup and restore
backup: ## Create backup
	@./scripts/backup.sh

restore: ## Restore from backup (usage: make restore BACKUP=backup-file.tar.gz)
	@./scripts/restore.sh $(BACKUP)

# Development
build: ## Build custom Docker images
	@docker-compose build

rebuild: ## Rebuild custom Docker images without cache
	@docker-compose build --no-cache

# Chromecast integration
deploy-chromecast-bridge: ## Deploy Chromecast bridge for Jellyfin
	@echo "Deploying Chromecast bridge..."
	@sudo ./scripts/deploy-chromecast-bridge.sh

generate-device-qr: ## Generate device QR code (usage: make generate-device-qr USER_EMAIL=user@example.com DEVICE_NAME=device DEVICE_TYPE=mobile)
	@echo "Generating device QR code..."
	@python3 ./scripts/generate-device-qr.py $(USER_EMAIL) $(DEVICE_NAME) --device-type $(DEVICE_TYPE)

# Service discovery
start-service-discovery: ## Start service discovery container
	@echo "Starting service discovery..."
	@docker-compose up -d service-discovery

# Smart TV bridge
start-tv-bridge: ## Start Smart TV bridge container
	@echo "Starting Smart TV bridge..."
	@docker-compose up -d smart-tv-bridge
