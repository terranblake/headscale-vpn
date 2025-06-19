#!/bin/bash

# Multi-Agent Startup Script for Family Network Platform
# This script sets up and starts multiple OpenHands agents simultaneously

set -e

PROJECT_DIR=$(pwd)
COORDINATION_DIR=".openhands/coordination"

echo "🚀 Starting Multi-Agent Execution for Family Network Platform"
echo "Project Directory: $PROJECT_DIR"
echo ""

# Function to check if OpenHands is available
check_openhands() {
    if ! command -v openhands &> /dev/null; then
        echo "❌ OpenHands not found in PATH"
        echo "Please install OpenHands or ensure it's available in your PATH"
        exit 1
    fi
    echo "✅ OpenHands found: $(which openhands)"
}

# Function to setup coordination infrastructure
setup_coordination() {
    echo "📋 Setting up coordination infrastructure..."
    
    # Create coordination directories
    mkdir -p "$COORDINATION_DIR/status"
    mkdir -p "$COORDINATION_DIR/logs"
    mkdir -p "$COORDINATION_DIR/shared"
    
    # Initialize status files
    for agent in documentation infrastructure family-experience operations; do
        echo "$(date): $agent agent initialized" > "$COORDINATION_DIR/status/${agent}.log"
    done
    
    echo "✅ Coordination infrastructure ready"
}

# Function to create agent branches
setup_branches() {
    echo "🌿 Setting up agent branches..."
    
    # Ensure we're on main branch
    git checkout main
    
    # Create agent branches if they don't exist
    for branch in agent/documentation agent/infrastructure agent/family-experience agent/operations agent/monitor; do
        if git show-ref --verify --quiet refs/heads/$branch; then
            echo "Branch $branch already exists"
        else
            git checkout -b $branch
            git checkout main
            echo "Created branch $branch"
        fi
    done
    
    echo "✅ Agent branches ready"
}

# Function to start an agent in a new terminal
start_agent() {
    local agent_name=$1
    local agent_config=".openhands/agents/${agent_name}-agent.yaml"
    local branch="agent/${agent_name}"
    
    echo "🤖 Starting $agent_name agent..."
    
    # Check if config exists
    if [[ ! -f "$agent_config" ]]; then
        echo "❌ Agent config not found: $agent_config"
        return 1
    fi
    
    # Platform-specific terminal launching
    case "$OSTYPE" in
        linux*)
            # Linux with gnome-terminal
            if command -v gnome-terminal &> /dev/null; then
                gnome-terminal --tab --title="$agent_name Agent" -- bash -c "
                    cd '$PROJECT_DIR' && 
                    git checkout $branch && 
                    echo 'Starting $agent_name agent...' &&
                    echo 'Config: $agent_config' &&
                    echo 'Branch: $branch' &&
                    echo 'Press Enter to start agent or Ctrl+C to cancel' &&
                    read &&
                    openhands --config '$agent_config' --workspace-dir . --agent-name '$agent_name Specialist'
                "
            else
                echo "⚠️  gnome-terminal not found. Please start agent manually:"
                echo "   cd $PROJECT_DIR && git checkout $branch && openhands --config $agent_config"
            fi
            ;;
        darwin*)
            # macOS with Terminal.app
            osascript -e "
                tell application \"Terminal\"
                    do script \"cd '$PROJECT_DIR' && git checkout $branch && echo 'Starting $agent_name agent...' && openhands --config '$agent_config' --workspace-dir . --agent-name '$agent_name Specialist'\"
                end tell
            "
            ;;
        msys*|cygwin*)
            # Windows
            echo "⚠️  Windows detected. Please start agent manually in a new terminal:"
            echo "   cd $PROJECT_DIR && git checkout $branch && openhands --config $agent_config"
            ;;
        *)
            echo "⚠️  Unknown OS. Please start agent manually:"
            echo "   cd $PROJECT_DIR && git checkout $branch && openhands --config $agent_config"
            ;;
    esac
}

# Function to display monitoring instructions
show_monitoring() {
    echo ""
    echo "📊 Monitoring Multi-Agent Progress:"
    echo ""
    echo "1. Check agent status:"
    echo "   ./.openhands/coordination/agent-status-report.sh documentation"
    echo "   ./.openhands/coordination/agent-status-report.sh infrastructure"
    echo "   ./.openhands/coordination/agent-status-report.sh family-experience"
    echo "   ./.openhands/coordination/agent-status-report.sh operations"
    echo ""
    echo "2. View agent logs:"
    echo "   tail -f .openhands/coordination/status/*.log"
    echo ""
    echo "3. Monitor git branches:"
    echo "   git branch -a"
    echo "   git log --oneline --graph --all"
    echo ""
    echo "4. Integration testing:"
    echo "   # After agents complete their work, merge branches and test"
    echo "   git checkout main"
    echo "   git merge agent/documentation"
    echo "   git merge agent/infrastructure"
    echo "   git merge agent/family-experience"
    echo "   git merge agent/operations"
    echo ""
}

# Function to show agent assignments
show_agent_assignments() {
    echo "🎯 Agent Task Assignments:"
    echo ""
    echo "📝 Documentation Agent (Branch: agent/documentation):"
    echo "   - Technical reference documentation"
    echo "   - Family-facing user guides"
    echo "   - Security procedures"
    echo "   - Service-specific documentation"
    echo ""
    echo "🏗️  Infrastructure Agent (Branch: agent/infrastructure):"
    echo "   - Deployment automation scripts"
    echo "   - Testing framework"
    echo "   - Service templates"
    echo "   - Environment validation"
    echo ""
    echo "👨‍👩‍👧‍👦 Family Experience Agent (Branch: agent/family-experience):"
    echo "   - Family onboarding automation"
    echo "   - User experience optimization"
    echo "   - Setup process simplification"
    echo "   - Advanced family features"
    echo ""
    echo "⚙️  Operations Agent (Branch: agent/operations):"
    echo "   - Monitoring and alerting"
    echo "   - Backup and disaster recovery"
    echo "   - Security hardening"
    echo "   - Performance optimization"
    echo ""
    echo "🔍 Monitor Agent (Branch: agent/monitor):"
    echo "   - Quality assurance and oversight"
    echo "   - Progress monitoring and reporting"
    echo "   - Core principle compliance checking"
    echo "   - Integration validation and alerts"
    echo ""
}

# Main execution
main() {
    echo "Starting multi-agent setup..."
    
    # Pre-flight checks
    check_openhands
    
    # Setup
    setup_coordination
    setup_branches
    
    # Show assignments
    show_agent_assignments
    
    # Start agents
    echo "🚀 Launching agents..."
    echo ""
    
    start_agent "documentation"
    sleep 2
    start_agent "infrastructure"
    sleep 2
    start_agent "family-experience"
    sleep 2
    start_agent "operations"
    sleep 2
    start_agent "monitor"
    
    echo ""
    echo "✅ All agents launched!"
    
    # Show monitoring info
    show_monitoring
    
    echo ""
    echo "🎉 Multi-agent execution started successfully!"
    echo ""
    echo "Next steps:"
    echo "1. Monitor agent progress using the commands above"
    echo "2. Coordinate between agents as needed"
    echo "3. Merge branches when agents complete their work"
    echo "4. Run integration tests"
    echo ""
    echo "For detailed coordination instructions, see:"
    echo ".openhands/coordination/multi-agent-orchestration.md"
}

# Handle command line arguments
case "${1:-start}" in
    "start")
        main
        ;;
    "status")
        echo "📊 Multi-Agent Status:"
        for agent in documentation infrastructure family-experience operations monitor; do
            echo ""
            echo "=== $agent Agent ==="
            if [[ -f "$COORDINATION_DIR/status/${agent}.log" ]]; then
                tail -3 "$COORDINATION_DIR/status/${agent}.log"
            else
                echo "No status file found"
            fi
        done
        ;;
    "help"|"-h"|"--help")
        echo "Multi-Agent Startup Script"
        echo ""
        echo "Usage: $0 [command]"
        echo ""
        echo "Commands:"
        echo "  start    Start all agents (default)"
        echo "  status   Show current agent status"
        echo "  help     Show this help message"
        echo ""
        echo "For detailed instructions, see:"
        echo ".openhands/coordination/multi-agent-orchestration.md"
        ;;
    *)
        echo "Unknown command: $1"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac