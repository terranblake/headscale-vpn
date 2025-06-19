#!/bin/bash

# Progress Tracker for Family Network Platform
# Monitors overall project progress and generates stakeholder reports

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
MONITORING_DIR="$SCRIPT_DIR"
TIMESTAMP=$(date '+%Y-%m-%d_%H-%M-%S')
PROGRESS_FILE="$MONITORING_DIR/progress-reports/progress-$TIMESTAMP.md"
STATUS_DIR="$SCRIPT_DIR/../coordination/status"

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Initialize progress report
init_progress_report() {
    cat > "$PROGRESS_FILE" << EOF
# Family Network Platform - Progress Report
**Generated**: $(date)  
**Project**: Family Network Platform  
**Repository**: https://github.com/terranblake/headscale-vpn  

## Executive Summary
This report provides a comprehensive overview of project progress across all agents and phases.

EOF
}

# Calculate task completion percentage
calculate_task_completion() {
    local phase=$1
    local completed=0
    local total=0
    
    case $phase in
        "phase_1")
            # Phase 1 tasks
            [[ -f "docs/02-technical-reference/vpn-management.md" ]] && ((completed++))
            [[ -f "docs/02-technical-reference/monitoring-commands.md" ]] && ((completed++))
            [[ -f "docs/02-technical-reference/security-procedures.md" ]] && ((completed++))
            [[ -f "templates/services/media-service.yml" ]] && ((completed++))
            [[ -f "scripts/deploy.sh" ]] && ((completed++))
            [[ -f "tests/integration/test_vpn_connectivity.py" ]] && ((completed++))
            total=6
            ;;
        "phase_2")
            # Phase 2 tasks
            [[ -f "docs/03-family-docs/services/photos.md" ]] && ((completed++))
            [[ -f "docs/03-family-docs/troubleshooting.md" ]] && ((completed++))
            [[ -f "scripts/create-family-user.sh" ]] && ((completed++))
            [[ -f "scripts/add-service.sh" ]] && ((completed++))
            total=4
            ;;
        "phase_3")
            # Phase 3 tasks
            [[ -f "config/grafana/dashboards/family-network-overview.json" ]] && ((completed++))
            [[ -f "scripts/schedule-backups.sh" ]] && ((completed++))
            [[ -f "scripts/security-audit.sh" ]] && ((completed++))
            total=3
            ;;
        "phase_4")
            # Phase 4 tasks
            [[ -f "services/photoprism/docker-compose.yml" ]] && ((completed++))
            [[ -f "scripts/optimize-database.sh" ]] && ((completed++))
            [[ -f "config/family-profiles.yml" ]] && ((completed++))
            total=3
            ;;
    esac
    
    if [[ $total -gt 0 ]]; then
        echo "scale=1; $completed * 100 / $total" | bc
    else
        echo "0"
    fi
}

# Get agent status
get_agent_status() {
    local agent=$1
    local status_file="$STATUS_DIR/${agent}.log"
    
    if [[ -f "$status_file" ]]; then
        local last_update=$(tail -1 "$status_file" | grep -o '[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}' || echo "Unknown")
        local activity_count=$(wc -l < "$status_file")
        echo "Active (Last: $last_update, Entries: $activity_count)"
    else
        echo "No activity"
    fi
}

# Check git branch activity
check_branch_activity() {
    local branch=$1
    
    if git show-ref --verify --quiet refs/heads/$branch; then
        local commits=$(git rev-list --count $branch ^main 2>/dev/null || echo "0")
        local last_commit=$(git log -1 --format="%cr" $branch 2>/dev/null || echo "Never")
        echo "Active ($commits commits, Last: $last_commit)"
    else
        echo "Not created"
    fi
}

# Generate phase progress report
generate_phase_progress() {
    echo "## Phase Progress Overview" >> "$PROGRESS_FILE"
    echo "" >> "$PROGRESS_FILE"
    
    for phase in phase_1 phase_2 phase_3 phase_4; do
        local completion=$(calculate_task_completion $phase)
        local status_icon="🔄"
        
        if (( $(echo "$completion >= 100" | bc -l) )); then
            status_icon="✅"
        elif (( $(echo "$completion >= 50" | bc -l) )); then
            status_icon="🟡"
        elif (( $(echo "$completion > 0" | bc -l) )); then
            status_icon="🔄"
        else
            status_icon="⭕"
        fi
        
        case $phase in
            "phase_1") echo "### $status_icon Phase 1: Technical Infrastructure - ${completion}% Complete" >> "$PROGRESS_FILE" ;;
            "phase_2") echo "### $status_icon Phase 2: Family Experience - ${completion}% Complete" >> "$PROGRESS_FILE" ;;
            "phase_3") echo "### $status_icon Phase 3: Operations & Maintenance - ${completion}% Complete" >> "$PROGRESS_FILE" ;;
            "phase_4") echo "### $status_icon Phase 4: Service Expansion - ${completion}% Complete" >> "$PROGRESS_FILE" ;;
        esac
        
        echo "" >> "$PROGRESS_FILE"
    done
}

# Generate agent status report
generate_agent_status() {
    echo "## Agent Status Report" >> "$PROGRESS_FILE"
    echo "" >> "$PROGRESS_FILE"
    
    echo "| Agent | Status | Branch Activity | Last Update |" >> "$PROGRESS_FILE"
    echo "|-------|--------|-----------------|-------------|" >> "$PROGRESS_FILE"
    
    for agent in documentation infrastructure family-experience operations monitor; do
        local status=$(get_agent_status $agent)
        local branch_activity=$(check_branch_activity "agent/$agent")
        local last_update="N/A"
        
        if [[ -f "$STATUS_DIR/${agent}.log" ]]; then
            last_update=$(stat -c %y "$STATUS_DIR/${agent}.log" 2>/dev/null | cut -d' ' -f1 || echo "Unknown")
        fi
        
        echo "| $agent | $status | $branch_activity | $last_update |" >> "$PROGRESS_FILE"
    done
    
    echo "" >> "$PROGRESS_FILE"
}

# Check milestone achievements
check_milestones() {
    echo "## Milestone Achievements" >> "$PROGRESS_FILE"
    echo "" >> "$PROGRESS_FILE"
    
    local milestones_met=0
    local total_milestones=8
    
    # Documentation milestones
    if [[ -f "docs/02-technical-reference/vpn-management.md" ]] && [[ -f "docs/03-family-docs/initial-setup.md" ]]; then
        echo "✅ **Documentation Foundation Complete** - Technical and family docs established" >> "$PROGRESS_FILE"
        ((milestones_met++))
    else
        echo "⭕ **Documentation Foundation** - In progress" >> "$PROGRESS_FILE"
    fi
    
    # Infrastructure milestones
    if [[ -f "scripts/deploy.sh" ]] && [[ -f "scripts/validate-environment.sh" ]]; then
        echo "✅ **Deployment Automation Complete** - One-command deployment ready" >> "$PROGRESS_FILE"
        ((milestones_met++))
    else
        echo "⭕ **Deployment Automation** - In progress" >> "$PROGRESS_FILE"
    fi
    
    # Testing milestones
    if [[ -d "tests/" ]] && [[ -f "tests/integration/test_vpn_connectivity.py" ]]; then
        echo "✅ **Testing Framework Complete** - Automated testing implemented" >> "$PROGRESS_FILE"
        ((milestones_met++))
    else
        echo "⭕ **Testing Framework** - In progress" >> "$PROGRESS_FILE"
    fi
    
    # Family experience milestones
    if [[ -f "scripts/create-family-user.sh" ]] && [[ -f "scripts/generate-mobile-config.sh" ]]; then
        echo "✅ **Family Onboarding Complete** - Automated user creation ready" >> "$PROGRESS_FILE"
        ((milestones_met++))
    else
        echo "⭕ **Family Onboarding** - In progress" >> "$PROGRESS_FILE"
    fi
    
    # Service management milestones
    if [[ -f "scripts/add-service.sh" ]] && [[ -f "templates/services/media-service.yml" ]]; then
        echo "✅ **Service Management Complete** - Service addition automation ready" >> "$PROGRESS_FILE"
        ((milestones_met++))
    else
        echo "⭕ **Service Management** - In progress" >> "$PROGRESS_FILE"
    fi
    
    # Monitoring milestones
    if [[ -f "config/grafana/dashboards/family-network-overview.json" ]]; then
        echo "✅ **Monitoring Complete** - Dashboards and alerting implemented" >> "$PROGRESS_FILE"
        ((milestones_met++))
    else
        echo "⭕ **Monitoring** - In progress" >> "$PROGRESS_FILE"
    fi
    
    # Security milestones
    if [[ -f "scripts/security-audit.sh" ]] && [[ -f "config/fail2ban/family-network.conf" ]]; then
        echo "✅ **Security Hardening Complete** - Automated security measures implemented" >> "$PROGRESS_FILE"
        ((milestones_met++))
    else
        echo "⭕ **Security Hardening** - In progress" >> "$PROGRESS_FILE"
    fi
    
    # Backup milestones
    if [[ -f "scripts/schedule-backups.sh" ]] && [[ -f "scripts/restore-from-backup.sh" ]]; then
        echo "✅ **Backup & Recovery Complete** - Automated backup procedures ready" >> "$PROGRESS_FILE"
        ((milestones_met++))
    else
        echo "⭕ **Backup & Recovery** - In progress" >> "$PROGRESS_FILE"
    fi
    
    echo "" >> "$PROGRESS_FILE"
    echo "**Milestone Progress**: $milestones_met/$total_milestones completed ($(echo "scale=1; $milestones_met * 100 / $total_milestones" | bc)%)" >> "$PROGRESS_FILE"
    echo "" >> "$PROGRESS_FILE"
}

# Check success criteria status
check_success_criteria() {
    echo "## Success Criteria Status" >> "$PROGRESS_FILE"
    echo "" >> "$PROGRESS_FILE"
    
    echo "### Technical Success Criteria" >> "$PROGRESS_FILE"
    
    # One-command deployment
    if [[ -f "scripts/deploy.sh" ]]; then
        echo "✅ One-command deployment script exists" >> "$PROGRESS_FILE"
    else
        echo "❌ One-command deployment script missing" >> "$PROGRESS_FILE"
    fi
    
    # Comprehensive monitoring
    if [[ -d "config/grafana" ]] && [[ -d "config/prometheus" ]]; then
        echo "✅ Monitoring configuration present" >> "$PROGRESS_FILE"
    else
        echo "❌ Monitoring configuration incomplete" >> "$PROGRESS_FILE"
    fi
    
    # Tested backup procedures
    if [[ -f "scripts/schedule-backups.sh" ]] && [[ -f "scripts/test-backup.sh" ]]; then
        echo "✅ Backup procedures implemented" >> "$PROGRESS_FILE"
    else
        echo "❌ Backup procedures missing" >> "$PROGRESS_FILE"
    fi
    
    echo "" >> "$PROGRESS_FILE"
    echo "### Family Experience Success Criteria" >> "$PROGRESS_FILE"
    
    # 10-minute setup goal
    if [[ -f "scripts/generate-setup-qr.py" ]] && [[ -f "scripts/create-family-user.sh" ]]; then
        echo "✅ Automated setup tools present" >> "$PROGRESS_FILE"
    else
        echo "❌ Automated setup tools missing" >> "$PROGRESS_FILE"
    fi
    
    # Non-technical documentation
    if [[ -d "docs/03-family-docs" ]] && [[ $(find docs/03-family-docs -name "*.md" | wc -l) -gt 3 ]]; then
        echo "✅ Family documentation present" >> "$PROGRESS_FILE"
    else
        echo "❌ Family documentation incomplete" >> "$PROGRESS_FILE"
    fi
    
    echo "" >> "$PROGRESS_FILE"
    echo "### Operational Success Criteria" >> "$PROGRESS_FILE"
    
    # Minimal maintenance overhead
    if [[ -f "scripts/security-updates.sh" ]] && [[ -f "scripts/monitor-services.sh" ]]; then
        echo "✅ Maintenance automation present" >> "$PROGRESS_FILE"
    else
        echo "❌ Maintenance automation missing" >> "$PROGRESS_FILE"
    fi
    
    echo "" >> "$PROGRESS_FILE"
}

# Generate recommendations and next steps
generate_recommendations() {
    echo "## Recommendations and Next Steps" >> "$PROGRESS_FILE"
    echo "" >> "$PROGRESS_FILE"
    
    # Calculate overall progress
    local phase1_progress=$(calculate_task_completion "phase_1")
    local phase2_progress=$(calculate_task_completion "phase_2")
    local phase3_progress=$(calculate_task_completion "phase_3")
    local phase4_progress=$(calculate_task_completion "phase_4")
    
    local overall_progress=$(echo "scale=1; ($phase1_progress + $phase2_progress + $phase3_progress + $phase4_progress) / 4" | bc)
    
    echo "### Overall Project Progress: ${overall_progress}%" >> "$PROGRESS_FILE"
    echo "" >> "$PROGRESS_FILE"
    
    if (( $(echo "$overall_progress < 25" | bc -l) )); then
        echo "🚀 **Early Stage**: Focus on Phase 1 foundation tasks" >> "$PROGRESS_FILE"
        echo "- Prioritize documentation and infrastructure agents" >> "$PROGRESS_FILE"
        echo "- Establish core deployment automation" >> "$PROGRESS_FILE"
        echo "- Create testing framework foundation" >> "$PROGRESS_FILE"
    elif (( $(echo "$overall_progress < 50" | bc -l) )); then
        echo "🔄 **Development Stage**: Continue with Phase 1 and begin Phase 2" >> "$PROGRESS_FILE"
        echo "- Complete remaining Phase 1 tasks" >> "$PROGRESS_FILE"
        echo "- Begin family experience development" >> "$PROGRESS_FILE"
        echo "- Start integration testing between agents" >> "$PROGRESS_FILE"
    elif (( $(echo "$overall_progress < 75" | bc -l) )); then
        echo "⚡ **Integration Stage**: Focus on Phase 2 and 3 completion" >> "$PROGRESS_FILE"
        echo "- Complete family onboarding automation" >> "$PROGRESS_FILE"
        echo "- Implement monitoring and alerting" >> "$PROGRESS_FILE"
        echo "- Begin operational procedures" >> "$PROGRESS_FILE"
    else
        echo "🎯 **Completion Stage**: Finalize all phases and prepare for deployment" >> "$PROGRESS_FILE"
        echo "- Complete remaining Phase 3 and 4 tasks" >> "$PROGRESS_FILE"
        echo "- Conduct comprehensive integration testing" >> "$PROGRESS_FILE"
        echo "- Prepare for production deployment" >> "$PROGRESS_FILE"
    fi
    
    echo "" >> "$PROGRESS_FILE"
    echo "### Immediate Action Items" >> "$PROGRESS_FILE"
    
    # Check for critical missing components
    if [[ ! -f "scripts/deploy.sh" ]]; then
        echo "🚨 **CRITICAL**: Create deployment automation script" >> "$PROGRESS_FILE"
    fi
    
    if [[ ! -f "scripts/create-family-user.sh" ]]; then
        echo "🚨 **CRITICAL**: Implement family user creation automation" >> "$PROGRESS_FILE"
    fi
    
    if [[ ! -d "tests/" ]]; then
        echo "⚠️ **HIGH**: Establish testing framework" >> "$PROGRESS_FILE"
    fi
    
    if [[ ! -f "config/grafana/dashboards/family-network-overview.json" ]]; then
        echo "⚠️ **HIGH**: Create monitoring dashboards" >> "$PROGRESS_FILE"
    fi
    
    echo "" >> "$PROGRESS_FILE"
    echo "**Next Progress Review**: $(date -d '+1 week' '+%Y-%m-%d')" >> "$PROGRESS_FILE"
    echo "" >> "$PROGRESS_FILE"
    echo "**Report Location**: \`$PROGRESS_FILE\`" >> "$PROGRESS_FILE"
}

# Main execution
main() {
    echo -e "${PURPLE}📊 Generating Progress Report for Family Network Platform${NC}"
    echo "Report will be generated at: $PROGRESS_FILE"
    echo ""
    
    # Initialize report
    init_progress_report
    
    # Generate all sections
    generate_phase_progress
    generate_agent_status
    check_milestones
    check_success_criteria
    generate_recommendations
    
    echo ""
    echo -e "${GREEN}✅ Progress Report Complete${NC}"
    echo "Report: $PROGRESS_FILE"
    
    # Display summary to console
    echo ""
    echo -e "${BLUE}=== PROGRESS SUMMARY ===${NC}"
    echo "Phase 1 (Technical): $(calculate_task_completion phase_1)%"
    echo "Phase 2 (Family): $(calculate_task_completion phase_2)%"
    echo "Phase 3 (Operations): $(calculate_task_completion phase_3)%"
    echo "Phase 4 (Expansion): $(calculate_task_completion phase_4)%"
}

# Handle command line arguments
case "${1:-report}" in
    "report")
        main
        ;;
    "summary")
        echo "=== QUICK PROGRESS SUMMARY ==="
        echo "Phase 1 (Technical): $(calculate_task_completion phase_1)%"
        echo "Phase 2 (Family): $(calculate_task_completion phase_2)%"
        echo "Phase 3 (Operations): $(calculate_task_completion phase_3)%"
        echo "Phase 4 (Expansion): $(calculate_task_completion phase_4)%"
        echo ""
        echo "Agent Status:"
        for agent in documentation infrastructure family-experience operations; do
            echo "  $agent: $(get_agent_status $agent)"
        done
        ;;
    "help"|"-h"|"--help")
        echo "Progress Tracker for Family Network Platform"
        echo ""
        echo "Usage: $0 [command]"
        echo ""
        echo "Commands:"
        echo "  report   Generate comprehensive progress report (default)"
        echo "  summary  Show quick progress summary"
        echo "  help     Show this help message"
        ;;
    *)
        echo "Unknown command: $1"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac