#!/bin/bash

# Docker Multi-Agent Startup Script for Family Network Platform
# This script starts all 5 OpenHands agents using Docker containers

set -e

echo "🐳 Starting Docker Multi-Agent Execution for Family Network Platform"
echo ""

# Check if Docker is installed and running
check_docker() {
    if ! command -v docker &> /dev/null; then
        echo "❌ Docker not found. Please install Docker first:"
        echo "   Ubuntu/Debian: sudo apt install docker.io"
        echo "   macOS: brew install docker"
        echo "   Windows: Download Docker Desktop from docker.com"
        exit 1
    fi
    
    if ! docker info &> /dev/null; then
        echo "❌ Docker daemon not running. Please start Docker first."
        exit 1
    fi
    
    echo "✅ Docker is installed and running"
}

# Check if docker-compose is available
check_compose() {
    if command -v docker-compose &> /dev/null; then
        COMPOSE_CMD="docker-compose"
    elif docker compose version &> /dev/null; then
        COMPOSE_CMD="docker compose"
    else
        echo "❌ docker-compose not found. Please install docker-compose:"
        echo "   pip install docker-compose"
        echo "   or use Docker Desktop which includes compose"
        exit 1
    fi
    
    echo "✅ Docker Compose found: $COMPOSE_CMD"
}

# Setup environment
setup_environment() {
    echo "🔧 Setting up environment..."
    
    # Check for GitHub token
    if [[ -z "$GITHUB_TOKEN" ]]; then
        echo "⚠️  GITHUB_TOKEN not set. Please set it:"
        echo "   export GITHUB_TOKEN='your_github_token_here'"
        echo ""
        echo "You can continue without it, but git operations may fail."
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        echo "✅ GITHUB_TOKEN is set"
    fi
    
    # Create coordination directories
    mkdir -p .openhands/coordination/{status,logs,shared}
    
    # Initialize git branches for agents
    echo "🌿 Setting up agent branches..."
    git checkout main 2>/dev/null || true
    
    for branch in agent/documentation agent/infrastructure agent/family-experience agent/operations agent/monitor; do
        if git show-ref --verify --quiet refs/heads/$branch; then
            echo "Branch $branch already exists"
        else
            git checkout -b $branch 2>/dev/null || true
            git checkout main 2>/dev/null || true
            echo "Created branch $branch"
        fi
    done
    
    echo "✅ Environment setup complete"
}

# Pull latest OpenHands image
pull_image() {
    echo "📥 Pulling latest OpenHands Docker image..."
    docker pull ghcr.io/all-hands-ai/openhands:main
    echo "✅ Image pulled successfully"
}

# Start agents
start_agents() {
    echo "🚀 Starting all agents..."
    echo ""
    
    # Start all services
    $COMPOSE_CMD -f docker-compose-agents.yml up -d
    
    echo ""
    echo "✅ All agents started successfully!"
    echo ""
    
    # Show running containers
    echo "📊 Running agent containers:"
    docker ps --filter "name=*-agent" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    echo ""
}

# Show monitoring commands
show_monitoring() {
    echo "📊 Monitoring Commands:"
    echo ""
    echo "1. View all agent logs:"
    echo "   $COMPOSE_CMD -f docker-compose-agents.yml logs -f"
    echo ""
    echo "2. View specific agent logs:"
    echo "   $COMPOSE_CMD -f docker-compose-agents.yml logs -f documentation-agent"
    echo "   $COMPOSE_CMD -f docker-compose-agents.yml logs -f infrastructure-agent"
    echo "   $COMPOSE_CMD -f docker-compose-agents.yml logs -f family-experience-agent"
    echo "   $COMPOSE_CMD -f docker-compose-agents.yml logs -f operations-agent"
    echo "   $COMPOSE_CMD -f docker-compose-agents.yml logs -f monitor-agent"
    echo ""
    echo "3. Check agent status:"
    echo "   docker ps --filter 'name=*-agent'"
    echo ""
    echo "4. Stop all agents:"
    echo "   $COMPOSE_CMD -f docker-compose-agents.yml down"
    echo ""
    echo "5. Restart specific agent:"
    echo "   $COMPOSE_CMD -f docker-compose-agents.yml restart documentation-agent"
    echo ""
    echo "6. View agent resource usage:"
    echo "   docker stats --format 'table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}'"
    echo ""
}

# Show agent assignments
show_assignments() {
    echo "🎯 Agent Assignments:"
    echo ""
    echo "📝 Documentation Agent (Container: documentation-agent):"
    echo "   - Technical reference documentation"
    echo "   - Family-facing user guides"
    echo "   - Security procedures"
    echo "   - Service-specific documentation"
    echo ""
    echo "🏗️  Infrastructure Agent (Container: infrastructure-agent):"
    echo "   - Deployment automation scripts"
    echo "   - Testing framework"
    echo "   - Service templates"
    echo "   - Environment validation"
    echo ""
    echo "👨‍👩‍👧‍👦 Family Experience Agent (Container: family-experience-agent):"
    echo "   - Family onboarding automation"
    echo "   - User experience optimization"
    echo "   - Setup process simplification"
    echo "   - Advanced family features"
    echo ""
    echo "⚙️  Operations Agent (Container: operations-agent):"
    echo "   - Monitoring and alerting"
    echo "   - Backup and disaster recovery"
    echo "   - Security hardening"
    echo "   - Performance optimization"
    echo ""
    echo "🔍 Monitor Agent (Container: monitor-agent):"
    echo "   - Quality assurance and oversight"
    echo "   - Progress monitoring and reporting"
    echo "   - Core principle compliance checking"
    echo "   - Integration validation and alerts"
    echo ""
}

# Main execution
main() {
    check_docker
    check_compose
    setup_environment
    pull_image
    start_agents
    show_assignments
    show_monitoring
    
    echo "🎉 Docker Multi-Agent Execution Started Successfully!"
    echo ""
    echo "💡 Pro Tips:"
    echo "   - Agents will automatically restart if they crash"
    echo "   - All work is saved to your local filesystem"
    echo "   - Git operations will use your local git config"
    echo "   - Monitor progress with the commands above"
    echo ""
    echo "🔗 For detailed coordination instructions, see:"
    echo "   .openhands/coordination/multi-agent-orchestration.md"
}

# Handle command line arguments
case "${1:-start}" in
    "start")
        main
        ;;
    "stop")
        echo "🛑 Stopping all agents..."
        $COMPOSE_CMD -f docker-compose-agents.yml down
        echo "✅ All agents stopped"
        ;;
    "restart")
        echo "🔄 Restarting all agents..."
        $COMPOSE_CMD -f docker-compose-agents.yml restart
        echo "✅ All agents restarted"
        ;;
    "logs")
        echo "📋 Showing agent logs (Ctrl+C to exit)..."
        $COMPOSE_CMD -f docker-compose-agents.yml logs -f
        ;;
    "status")
        echo "📊 Agent Status:"
        docker ps --filter "name=*-agent" --format "table {{.Names}}\t{{.Status}}\t{{.Created}}"
        echo ""
        echo "📈 Resource Usage:"
        docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" $(docker ps --filter "name=*-agent" -q)
        ;;
    "help"|"-h"|"--help")
        echo "Docker Multi-Agent Startup Script"
        echo ""
        echo "Usage: $0 [command]"
        echo ""
        echo "Commands:"
        echo "  start    Start all agents (default)"
        echo "  stop     Stop all agents"
        echo "  restart  Restart all agents"
        echo "  logs     Show agent logs"
        echo "  status   Show agent status and resource usage"
        echo "  help     Show this help message"
        echo ""
        ;;
    *)
        echo "Unknown command: $1"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac