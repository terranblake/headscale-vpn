#!/bin/bash

# Agent Status Report Script
# Usage: ./agent-status-report.sh [agent_name]

AGENT_NAME=${1:-"unknown"}
STATUS_DIR=".openhands/coordination/status"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Ensure status directory exists
mkdir -p "$STATUS_DIR"

# Function to get git branch info
get_branch_info() {
    local branch=$(git branch --show-current)
    local commit=$(git rev-parse --short HEAD)
    local status=$(git status --porcelain | wc -l)
    echo "Branch: $branch | Commit: $commit | Modified files: $status"
}

# Function to get task progress
get_task_progress() {
    local agent=$1
    local config_file=".openhands/agents/${agent}-agent.yaml"
    
    if [[ -f "$config_file" ]]; then
        echo "Agent config: $config_file"
        # Extract assigned tasks from config
        grep -A 20 "assigned_tasks:" "$config_file" | grep -E "^\s*-\s*\"" | wc -l
    else
        echo "Config file not found: $config_file"
    fi
}

# Function to check file creation progress
check_file_progress() {
    local agent=$1
    local created_files=0
    local total_files=0
    
    case $agent in
        "documentation")
            # Check documentation files
            [[ -f "docs/02-technical-reference/vpn-management.md" ]] && ((created_files++))
            [[ -f "docs/02-technical-reference/monitoring-commands.md" ]] && ((created_files++))
            [[ -f "docs/02-technical-reference/security-procedures.md" ]] && ((created_files++))
            [[ -f "docs/03-family-docs/services/photos.md" ]] && ((created_files++))
            [[ -f "docs/03-family-docs/services/documents.md" ]] && ((created_files++))
            [[ -f "docs/03-family-docs/troubleshooting.md" ]] && ((created_files++))
            [[ -f "docs/03-family-docs/faq.md" ]] && ((created_files++))
            total_files=7
            ;;
        "infrastructure")
            # Check infrastructure files
            [[ -f "scripts/deploy.sh" ]] && ((created_files++))
            [[ -f "scripts/validate-environment.sh" ]] && ((created_files++))
            [[ -f "scripts/setup-ssl.sh" ]] && ((created_files++))
            [[ -f "tests/integration/test_vpn_connectivity.py" ]] && ((created_files++))
            [[ -f "templates/services/media-service.yml" ]] && ((created_files++))
            [[ -f "scripts/add-service.sh" ]] && ((created_files++))
            total_files=6
            ;;
        "family-experience")
            # Check family experience files
            [[ -f "scripts/create-family-user.sh" ]] && ((created_files++))
            [[ -f "scripts/generate-mobile-config.sh" ]] && ((created_files++))
            [[ -f "scripts/generate-setup-qr.py" ]] && ((created_files++))
            [[ -f "config/family-profiles.yml" ]] && ((created_files++))
            total_files=4
            ;;
        "operations")
            # Check operations files
            [[ -f "config/grafana/dashboards/family-network-overview.json" ]] && ((created_files++))
            [[ -f "scripts/schedule-backups.sh" ]] && ((created_files++))
            [[ -f "scripts/security-audit.sh" ]] && ((created_files++))
            [[ -f "scripts/optimize-database.sh" ]] && ((created_files++))
            total_files=4
            ;;
    esac
    
    echo "Files created: $created_files/$total_files"
}

# Main status report
generate_status_report() {
    local agent=$1
    local status_file="$STATUS_DIR/${agent}.log"
    
    echo "=== $AGENT_NAME Agent Status Report ===" | tee -a "$status_file"
    echo "Timestamp: $TIMESTAMP" | tee -a "$status_file"
    echo "" | tee -a "$status_file"
    
    echo "Git Status:" | tee -a "$status_file"
    get_branch_info | tee -a "$status_file"
    echo "" | tee -a "$status_file"
    
    echo "Task Progress:" | tee -a "$status_file"
    get_task_progress "$agent" | tee -a "$status_file"
    echo "" | tee -a "$status_file"
    
    echo "File Creation Progress:" | tee -a "$status_file"
    check_file_progress "$agent" | tee -a "$status_file"
    echo "" | tee -a "$status_file"
    
    echo "Recent Activity:" | tee -a "$status_file"
    git log --oneline -5 | tee -a "$status_file"
    echo "" | tee -a "$status_file"
    
    echo "Current Working Directory Contents:" | tee -a "$status_file"
    ls -la | head -10 | tee -a "$status_file"
    echo "" | tee -a "$status_file"
    
    echo "---" | tee -a "$status_file"
}

# Check if agent name is provided
if [[ "$AGENT_NAME" == "unknown" ]]; then
    echo "Usage: $0 [documentation|infrastructure|family-experience|operations]"
    echo ""
    echo "Available agents:"
    echo "  documentation     - Documentation Specialist"
    echo "  infrastructure    - Infrastructure Specialist" 
    echo "  family-experience - Family Experience Specialist"
    echo "  operations        - Operations Specialist"
    exit 1
fi

# Validate agent name
case $AGENT_NAME in
    "documentation"|"infrastructure"|"family-experience"|"operations")
        generate_status_report "$AGENT_NAME"
        ;;
    *)
        echo "Error: Unknown agent name '$AGENT_NAME'"
        echo "Valid agents: documentation, infrastructure, family-experience, operations"
        exit 1
        ;;
esac

echo "Status report generated for $AGENT_NAME agent"
echo "Log file: $STATUS_DIR/${AGENT_NAME}.log"