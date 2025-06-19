#!/bin/bash

# Alert System for Family Network Platform
# Monitors for critical issues and sends notifications

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
MONITORING_DIR="$SCRIPT_DIR"
ALERTS_DIR="$MONITORING_DIR/alerts"
TIMESTAMP=$(date '+%Y-%m-%d_%H-%M-%S')

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Alert levels
CRITICAL=1
WARNING=2
INFO=3

# Initialize alert system
init_alert_system() {
    mkdir -p "$ALERTS_DIR"
    
    # Create alert log if it doesn't exist
    if [[ ! -f "$ALERTS_DIR/alert.log" ]]; then
        echo "$(date): Alert system initialized" > "$ALERTS_DIR/alert.log"
    fi
}

# Function to send alert
send_alert() {
    local level=$1
    local category=$2
    local message=$3
    local details=$4
    
    local level_text=""
    local level_emoji=""
    local color=""
    
    case $level in
        $CRITICAL)
            level_text="CRITICAL"
            level_emoji="🚨"
            color="$RED"
            ;;
        $WARNING)
            level_text="WARNING"
            level_emoji="⚠️"
            color="$YELLOW"
            ;;
        $INFO)
            level_text="INFO"
            level_emoji="ℹ️"
            color="$BLUE"
            ;;
    esac
    
    # Log alert
    echo "$(date): [$level_text] [$category] $message" >> "$ALERTS_DIR/alert.log"
    
    # Display alert
    echo -e "${color}${level_emoji} [$level_text] [$category] $message${NC}"
    [[ -n "$details" ]] && echo -e "${color}   Details: $details${NC}"
    
    # Create alert file
    local alert_file="$ALERTS_DIR/alert-$TIMESTAMP-$level_text.md"
    cat > "$alert_file" << EOF
# $level_emoji $level_text Alert: $category

**Time**: $(date)  
**Category**: $category  
**Message**: $message  

## Details
$details

## Recommended Actions
EOF
    
    # Add recommended actions based on category
    case $category in
        "Core Principle Violation")
            echo "1. Review the violating implementation immediately" >> "$alert_file"
            echo "2. Correct the implementation to align with core principles" >> "$alert_file"
            echo "3. Update documentation if necessary" >> "$alert_file"
            echo "4. Re-run quality audit to verify correction" >> "$alert_file"
            ;;
        "Family Experience")
            echo "1. Test the family workflow immediately" >> "$alert_file"
            echo "2. Simplify any complex procedures" >> "$alert_file"
            echo "3. Ensure setup time remains under 10 minutes" >> "$alert_file"
            echo "4. Update family documentation as needed" >> "$alert_file"
            ;;
        "Integration Failure")
            echo "1. Identify the conflicting components" >> "$alert_file"
            echo "2. Coordinate between affected agents" >> "$alert_file"
            echo "3. Resolve conflicts maintaining all requirements" >> "$alert_file"
            echo "4. Test integration thoroughly" >> "$alert_file"
            ;;
        "Timeline Drift")
            echo "1. Assess current progress against milestones" >> "$alert_file"
            echo "2. Identify blockers and resource needs" >> "$alert_file"
            echo "3. Adjust timeline or increase resources" >> "$alert_file"
            echo "4. Communicate changes to stakeholders" >> "$alert_file"
            ;;
        "Quality Degradation")
            echo "1. Review recent changes for quality issues" >> "$alert_file"
            echo "2. Implement additional quality checks" >> "$alert_file"
            echo "3. Provide additional guidance to agents" >> "$alert_file"
            echo "4. Increase review frequency" >> "$alert_file"
            ;;
    esac
    
    echo "" >> "$alert_file"
    echo "**Alert File**: \`$alert_file\`" >> "$alert_file"
    
    # For critical alerts, also create a summary
    if [[ $level -eq $CRITICAL ]]; then
        echo "$level_emoji **CRITICAL ALERT**: $message" >> "$ALERTS_DIR/critical-summary.md"
        echo "   - Time: $(date)" >> "$ALERTS_DIR/critical-summary.md"
        echo "   - Category: $category" >> "$ALERTS_DIR/critical-summary.md"
        echo "   - Details: $alert_file" >> "$ALERTS_DIR/critical-summary.md"
        echo "" >> "$ALERTS_DIR/critical-summary.md"
    fi
}

# Check for core principle violations
check_principle_violations() {
    local violations=0
    
    # Check for platform-specific implementations
    if grep -r -i "ios\|android\|windows\|macos\|linux" docs/03-family-docs/ --include="*.md" 2>/dev/null | grep -v "compatible\|supports\|works with"; then
        send_alert $CRITICAL "Core Principle Violation" "Platform-specific references in family documentation" "Universal compatibility principle violated"
        ((violations++))
    fi
    
    # Check for manual VPN management
    if grep -r -i "connect.*vpn\|vpn.*connect\|tailscale.*up\|tailscale.*down" docs/03-family-docs/ 2>/dev/null; then
        send_alert $CRITICAL "Core Principle Violation" "Manual VPN management in family documentation" "Transparent operation principle violated"
        ((violations++))
    fi
    
    # Check for hardcoded service endpoints
    if grep -r "http://.*:.*\|https://.*:" config/ scripts/ --include="*.yml" --include="*.yaml" --include="*.sh" 2>/dev/null | grep -v "example\|template\|variable\|localhost"; then
        send_alert $WARNING "Core Principle Violation" "Hardcoded service endpoints detected" "Infinite scalability principle may be compromised"
        ((violations++))
    fi
    
    return $violations
}

# Check family experience compliance
check_family_experience() {
    local issues=0
    
    # Check for technical jargon in family docs
    if find docs/03-family-docs/ -name "*.md" -exec grep -l "docker\|container\|yaml\|json\|ssh\|cli\|terminal\|command line\|config" {} \; 2>/dev/null; then
        send_alert $WARNING "Family Experience" "Technical jargon found in family documentation" "Family-first experience principle compromised"
        ((issues++))
    fi
    
    # Check setup time estimates
    if grep -r "hour\|hours" docs/03-family-docs/ 2>/dev/null; then
        send_alert $CRITICAL "Family Experience" "Setup procedures may exceed 10-minute goal" "Setup time requirement violated"
        ((issues++))
    fi
    
    # Check for missing family onboarding automation
    if [[ ! -f "scripts/create-family-user.sh" ]] || [[ ! -f "scripts/generate-setup-qr.py" ]]; then
        send_alert $WARNING "Family Experience" "Family onboarding automation incomplete" "Automated setup tools missing"
        ((issues++))
    fi
    
    return $issues
}

# Check integration status
check_integration_status() {
    local issues=0
    
    # Check for merge conflicts
    if git status --porcelain | grep -E "^UU|^AA|^DD"; then
        send_alert $CRITICAL "Integration Failure" "Git merge conflicts detected" "Agent work conflicts require resolution"
        ((issues++))
    fi
    
    # Check for incomplete implementations
    if find . -name "*.md" -exec grep -l "TODO\|FIXME\|XXX\|PLACEHOLDER" {} \; 2>/dev/null | head -1; then
        send_alert $WARNING "Integration Failure" "Incomplete implementations detected" "TODO/FIXME markers found in deliverables"
        ((issues++))
    fi
    
    # Check for missing dependencies
    if [[ -f "scripts/deploy.sh" ]] && ! grep -q "validate-environment" scripts/deploy.sh; then
        send_alert $WARNING "Integration Failure" "Deployment script missing environment validation" "Dependencies may not be properly checked"
        ((issues++))
    fi
    
    return $issues
}

# Check timeline progress
check_timeline_progress() {
    local issues=0
    
    # Calculate expected vs actual progress
    local days_since_start=7  # Assuming project started 7 days ago
    local expected_progress=25  # Expected 25% progress per week
    
    # Calculate actual progress
    local phase1_progress=$(.openhands/monitoring/progress-tracker.sh summary | grep "Phase 1" | grep -o '[0-9]*%' | tr -d '%')
    local phase2_progress=$(.openhands/monitoring/progress-tracker.sh summary | grep "Phase 2" | grep -o '[0-9]*%' | tr -d '%')
    local actual_progress=$(echo "scale=1; ($phase1_progress + $phase2_progress) / 2" | bc 2>/dev/null || echo "0")
    
    if (( $(echo "$actual_progress < $expected_progress" | bc -l 2>/dev/null || echo "0") )); then
        send_alert $WARNING "Timeline Drift" "Project progress behind schedule" "Actual: ${actual_progress}%, Expected: ${expected_progress}%"
        ((issues++))
    fi
    
    # Check for stale agent activity
    local stale_agents=0
    for agent in documentation infrastructure family-experience operations; do
        local status_file=".openhands/coordination/status/${agent}.log"
        if [[ -f "$status_file" ]]; then
            local last_update=$(stat -c %Y "$status_file" 2>/dev/null || echo "0")
            local current_time=$(date +%s)
            local hours_since_update=$(( (current_time - last_update) / 3600 ))
            
            if [[ $hours_since_update -gt 24 ]]; then
                send_alert $WARNING "Timeline Drift" "Agent $agent inactive for $hours_since_update hours" "Agent may be blocked or need attention"
                ((stale_agents++))
            fi
        fi
    done
    
    if [[ $stale_agents -gt 2 ]]; then
        send_alert $CRITICAL "Timeline Drift" "Multiple agents inactive" "$stale_agents agents have been inactive for >24 hours"
        ((issues++))
    fi
    
    return $issues
}

# Check quality metrics
check_quality_metrics() {
    local issues=0
    
    # Run quality audit and check results
    if .openhands/monitoring/quality-audit.sh audit >/dev/null 2>&1; then
        local exit_code=$?
        if [[ $exit_code -eq 2 ]]; then
            send_alert $CRITICAL "Quality Degradation" "Quality audit failed with major issues" "Multiple quality violations detected"
            ((issues++))
        elif [[ $exit_code -eq 1 ]]; then
            send_alert $WARNING "Quality Degradation" "Quality audit found minor issues" "Some quality improvements needed"
            ((issues++))
        fi
    fi
    
    # Check for missing critical files
    local critical_files=(
        "scripts/deploy.sh"
        "scripts/create-family-user.sh"
        "docs/03-family-docs/initial-setup.md"
        "PROJECT_COMPLETION_PLAN.md"
    )
    
    for file in "${critical_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            send_alert $WARNING "Quality Degradation" "Critical file missing: $file" "Essential project component not found"
            ((issues++))
        fi
    done
    
    return $issues
}

# Check for major milestone completion
check_milestone_completion() {
    local new_milestones=0
    local milestone_file="$ALERTS_DIR/completed-milestones.log"
    
    # Initialize milestone tracking if needed
    if [[ ! -f "$milestone_file" ]]; then
        touch "$milestone_file"
    fi
    
    # Check for newly completed milestones
    local milestones=(
        "scripts/deploy.sh:Deployment Automation"
        "tests/integration/test_vpn_connectivity.py:Testing Framework"
        "scripts/create-family-user.sh:Family Onboarding"
        "config/grafana/dashboards/family-network-overview.json:Monitoring Dashboards"
        "scripts/schedule-backups.sh:Backup Procedures"
        "scripts/security-audit.sh:Security Hardening"
    )
    
    for milestone in "${milestones[@]}"; do
        local file="${milestone%%:*}"
        local name="${milestone##*:}"
        
        if [[ -f "$file" ]] && ! grep -q "$name" "$milestone_file"; then
            send_alert $INFO "Milestone Completed" "$name milestone achieved" "File: $file"
            echo "$(date): $name" >> "$milestone_file"
            ((new_milestones++))
        fi
    done
    
    return $new_milestones
}

# Generate alert summary
generate_alert_summary() {
    local total_alerts=$1
    
    echo ""
    echo -e "${PURPLE}=== ALERT SUMMARY ===${NC}"
    echo "Total alerts generated: $total_alerts"
    
    if [[ -f "$ALERTS_DIR/critical-summary.md" ]]; then
        local critical_count=$(grep -c "CRITICAL ALERT" "$ALERTS_DIR/critical-summary.md" 2>/dev/null || echo "0")
        echo -e "${RED}Critical alerts: $critical_count${NC}"
    fi
    
    local warning_count=$(grep -c "WARNING" "$ALERTS_DIR/alert.log" 2>/dev/null || echo "0")
    echo -e "${YELLOW}Warning alerts: $warning_count${NC}"
    
    local info_count=$(grep -c "INFO" "$ALERTS_DIR/alert.log" 2>/dev/null || echo "0")
    echo -e "${BLUE}Info alerts: $info_count${NC}"
    
    echo ""
    echo "Recent alerts:"
    tail -5 "$ALERTS_DIR/alert.log" 2>/dev/null || echo "No recent alerts"
}

# Main monitoring loop
main() {
    echo -e "${PURPLE}🔔 Running Alert System for Family Network Platform${NC}"
    echo "Monitoring for critical issues and milestone completion..."
    echo ""
    
    # Initialize alert system
    init_alert_system
    
    local total_alerts=0
    
    # Run all checks
    check_principle_violations
    total_alerts=$((total_alerts + $?))
    
    check_family_experience
    total_alerts=$((total_alerts + $?))
    
    check_integration_status
    total_alerts=$((total_alerts + $?))
    
    check_timeline_progress
    total_alerts=$((total_alerts + $?))
    
    check_quality_metrics
    total_alerts=$((total_alerts + $?))
    
    check_milestone_completion
    total_alerts=$((total_alerts + $?))
    
    # Generate summary
    generate_alert_summary $total_alerts
    
    echo ""
    echo -e "${GREEN}✅ Alert System Check Complete${NC}"
    echo "Alert log: $ALERTS_DIR/alert.log"
    
    # Return appropriate exit code
    if grep -q "CRITICAL" "$ALERTS_DIR/alert.log" | tail -10; then
        exit 2
    elif [[ $total_alerts -gt 0 ]]; then
        exit 1
    else
        exit 0
    fi
}

# Handle command line arguments
case "${1:-monitor}" in
    "monitor")
        main
        ;;
    "status")
        echo "=== ALERT STATUS ==="
        if [[ -f "$ALERTS_DIR/alert.log" ]]; then
            echo "Recent alerts:"
            tail -10 "$ALERTS_DIR/alert.log"
        else
            echo "No alerts logged"
        fi
        ;;
    "critical")
        echo "=== CRITICAL ALERTS ==="
        if [[ -f "$ALERTS_DIR/critical-summary.md" ]]; then
            cat "$ALERTS_DIR/critical-summary.md"
        else
            echo "No critical alerts"
        fi
        ;;
    "clear")
        echo "Clearing alert logs..."
        rm -f "$ALERTS_DIR/alert.log"
        rm -f "$ALERTS_DIR/critical-summary.md"
        rm -f "$ALERTS_DIR"/alert-*.md
        echo "Alert logs cleared"
        ;;
    "help"|"-h"|"--help")
        echo "Alert System for Family Network Platform"
        echo ""
        echo "Usage: $0 [command]"
        echo ""
        echo "Commands:"
        echo "  monitor   Run complete alert monitoring (default)"
        echo "  status    Show recent alert status"
        echo "  critical  Show critical alerts only"
        echo "  clear     Clear all alert logs"
        echo "  help      Show this help message"
        echo ""
        echo "Exit codes:"
        echo "  0         No alerts"
        echo "  1         Warnings present"
        echo "  2         Critical alerts present"
        ;;
    *)
        echo "Unknown command: $1"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac