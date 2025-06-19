#!/bin/bash

# Quality Audit Script for Family Network Platform
# Automated quality checks to detect principle violations and ensure success criteria adherence

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
MONITORING_DIR="$SCRIPT_DIR"
TIMESTAMP=$(date '+%Y-%m-%d_%H-%M-%S')
REPORT_FILE="$MONITORING_DIR/quality-reports/audit-$TIMESTAMP.md"

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Initialize report
init_report() {
    cat > "$REPORT_FILE" << EOF
# Quality Audit Report
**Generated**: $(date)  
**Project**: Family Network Platform  
**Audit Type**: Automated Quality Check  

## Executive Summary
This report validates adherence to core principles and success criteria across all agent work.

EOF
}

# Function to log findings
log_finding() {
    local level=$1
    local category=$2
    local message=$3
    local file=$4
    
    echo -e "${level}: [$category] $message" >&2
    echo "- **$level**: [$category] $message" >> "$REPORT_FILE"
    [[ -n "$file" ]] && echo "  - File: \`$file\`" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
}

# Check for universal compatibility violations
check_universal_compatibility() {
    echo -e "${BLUE}Checking Universal Compatibility...${NC}"
    echo "## Universal Compatibility Check" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    local violations=0
    
    # Check for platform-specific references
    if grep -r -i "ios\|android\|windows\|macos\|linux" docs/ --include="*.md" | grep -v "universal\|compatible\|supports"; then
        log_finding "🚨 VIOLATION" "Universal Compatibility" "Platform-specific references found in documentation"
        ((violations++))
    fi
    
    # Check for device-specific scripts
    if find scripts/ -name "*ios*" -o -name "*android*" -o -name "*windows*" -o -name "*mac*" 2>/dev/null | head -1; then
        log_finding "🚨 VIOLATION" "Universal Compatibility" "Device-specific scripts detected"
        ((violations++))
    fi
    
    # Check for hardcoded platform assumptions
    if grep -r "apt-get\|yum\|brew\|choco" scripts/ 2>/dev/null | grep -v "detect\|check\|if"; then
        log_finding "⚠️ WARNING" "Universal Compatibility" "Platform-specific package managers without detection"
        ((violations++))
    fi
    
    if [[ $violations -eq 0 ]]; then
        log_finding "✅ PASS" "Universal Compatibility" "No violations detected"
    fi
    
    return $violations
}

# Check family-first experience
check_family_experience() {
    echo -e "${BLUE}Checking Family-First Experience...${NC}"
    echo "## Family-First Experience Check" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    local violations=0
    
    # Check family documentation for technical jargon
    if find docs/03-family-docs/ -name "*.md" -exec grep -l "docker\|container\|yaml\|json\|ssh\|cli\|terminal\|command line" {} \; 2>/dev/null; then
        log_finding "🚨 VIOLATION" "Family Experience" "Technical jargon found in family documentation"
        ((violations++))
    fi
    
    # Check for manual VPN management instructions
    if grep -r -i "connect.*vpn\|vpn.*connect\|tailscale.*up\|tailscale.*down" docs/03-family-docs/ 2>/dev/null; then
        log_finding "🚨 VIOLATION" "Family Experience" "Manual VPN management instructions in family docs"
        ((violations++))
    fi
    
    # Check setup time estimates
    if grep -r "minutes\|hours" docs/03-family-docs/ | grep -v "under.*10.*minutes\|less.*than.*10"; then
        log_finding "⚠️ WARNING" "Family Experience" "Setup time estimates may exceed 10-minute goal"
        ((violations++))
    fi
    
    # Check for complex troubleshooting in family docs
    if grep -r -i "log\|debug\|trace\|verbose\|config.*file" docs/03-family-docs/ 2>/dev/null; then
        log_finding "⚠️ WARNING" "Family Experience" "Complex troubleshooting found in family documentation"
        ((violations++))
    fi
    
    if [[ $violations -eq 0 ]]; then
        log_finding "✅ PASS" "Family Experience" "No violations detected"
    fi
    
    return $violations
}

# Check transparent operation
check_transparent_operation() {
    echo -e "${BLUE}Checking Transparent Operation...${NC}"
    echo "## Transparent Operation Check" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    local violations=0
    
    # Check for manual network configuration
    if grep -r "ip route\|iptables\|netplan\|network.*config" docs/ scripts/ 2>/dev/null | grep -v "automated\|automatic"; then
        log_finding "⚠️ WARNING" "Transparent Operation" "Manual network configuration detected"
        ((violations++))
    fi
    
    # Check for visible VPN management
    if grep -r "tailscale.*status\|tailscale.*ping\|check.*vpn" docs/03-family-docs/ 2>/dev/null; then
        log_finding "🚨 VIOLATION" "Transparent Operation" "Visible VPN management in family workflows"
        ((violations++))
    fi
    
    if [[ $violations -eq 0 ]]; then
        log_finding "✅ PASS" "Transparent Operation" "No violations detected"
    fi
    
    return $violations
}

# Check infinite scalability
check_infinite_scalability() {
    echo -e "${BLUE}Checking Infinite Scalability...${NC}"
    echo "## Infinite Scalability Check" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    local violations=0
    
    # Check for hardcoded service endpoints
    if grep -r "http://.*:.*\|https://.*:" config/ scripts/ --include="*.yml" --include="*.yaml" --include="*.sh" 2>/dev/null | grep -v "example\|template\|variable"; then
        log_finding "⚠️ WARNING" "Infinite Scalability" "Hardcoded service endpoints detected"
        ((violations++))
    fi
    
    # Check for client-side configuration requirements
    if grep -r "client.*config\|configure.*client" docs/ | grep -v "automatic\|automated"; then
        log_finding "⚠️ WARNING" "Infinite Scalability" "Client-side configuration requirements detected"
        ((violations++))
    fi
    
    # Check for wildcard domain usage
    if ! grep -r "\*.family.local\|\*\..*\.local" config/ docs/ 2>/dev/null; then
        log_finding "⚠️ WARNING" "Infinite Scalability" "Wildcard domain strategy not consistently implemented"
        ((violations++))
    fi
    
    if [[ $violations -eq 0 ]]; then
        log_finding "✅ PASS" "Infinite Scalability" "No violations detected"
    fi
    
    return $violations
}

# Check production quality
check_production_quality() {
    echo -e "${BLUE}Checking Production Quality...${NC}"
    echo "## Production Quality Check" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    local violations=0
    
    # Check for hardcoded secrets
    if grep -r "password.*=\|secret.*=\|key.*=" scripts/ config/ --include="*.sh" --include="*.yml" --include="*.yaml" 2>/dev/null | grep -v "example\|template\|placeholder"; then
        log_finding "🚨 VIOLATION" "Production Quality" "Hardcoded secrets or credentials detected"
        ((violations++))
    fi
    
    # Check for missing error handling in scripts
    if find scripts/ -name "*.sh" -exec grep -L "set -e\|trap\|error" {} \; 2>/dev/null | head -1; then
        log_finding "⚠️ WARNING" "Production Quality" "Scripts missing error handling"
        ((violations++))
    fi
    
    # Check for monitoring implementation
    if [[ ! -d "config/grafana" ]] || [[ ! -d "config/prometheus" ]]; then
        log_finding "⚠️ WARNING" "Production Quality" "Monitoring configuration incomplete"
        ((violations++))
    fi
    
    # Check for backup procedures
    if ! find scripts/ -name "*backup*" -o -name "*restore*" 2>/dev/null | head -1; then
        log_finding "⚠️ WARNING" "Production Quality" "Backup and recovery scripts missing"
        ((violations++))
    fi
    
    if [[ $violations -eq 0 ]]; then
        log_finding "✅ PASS" "Production Quality" "No violations detected"
    fi
    
    return $violations
}

# Check success criteria implementation
check_success_criteria() {
    echo -e "${BLUE}Checking Success Criteria Implementation...${NC}"
    echo "## Success Criteria Implementation Check" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    local missing=0
    
    # Check for deployment automation
    if [[ ! -f "scripts/deploy.sh" ]]; then
        log_finding "❌ MISSING" "Success Criteria" "One-command deployment script missing"
        ((missing++))
    fi
    
    # Check for testing framework
    if [[ ! -d "tests/" ]]; then
        log_finding "❌ MISSING" "Success Criteria" "Testing framework missing"
        ((missing++))
    fi
    
    # Check for family onboarding automation
    if [[ ! -f "scripts/create-family-user.sh" ]]; then
        log_finding "❌ MISSING" "Success Criteria" "Family onboarding automation missing"
        ((missing++))
    fi
    
    # Check for monitoring dashboards
    if [[ ! -f "config/grafana/dashboards/family-network-overview.json" ]]; then
        log_finding "❌ MISSING" "Success Criteria" "Monitoring dashboards missing"
        ((missing++))
    fi
    
    if [[ $missing -eq 0 ]]; then
        log_finding "✅ PASS" "Success Criteria" "All key components present"
    fi
    
    return $missing
}

# Check agent integration
check_agent_integration() {
    echo -e "${BLUE}Checking Agent Integration...${NC}"
    echo "## Agent Integration Check" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    local issues=0
    
    # Check for conflicting implementations
    if find . -name "*.md" -exec grep -l "TODO\|FIXME\|XXX" {} \; 2>/dev/null | head -1; then
        log_finding "⚠️ WARNING" "Agent Integration" "Incomplete implementations detected"
        ((issues++))
    fi
    
    # Check for consistent documentation patterns
    local doc_patterns=$(find docs/ -name "*.md" -exec grep -l "^#" {} \; | wc -l)
    local inconsistent_docs=$(find docs/ -name "*.md" -exec grep -L "^# " {} \; | wc -l)
    
    if [[ $inconsistent_docs -gt 0 ]]; then
        log_finding "⚠️ WARNING" "Agent Integration" "Inconsistent documentation formatting detected"
        ((issues++))
    fi
    
    if [[ $issues -eq 0 ]]; then
        log_finding "✅ PASS" "Agent Integration" "No integration issues detected"
    fi
    
    return $issues
}

# Generate summary and recommendations
generate_summary() {
    echo "## Summary and Recommendations" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    local total_violations=$1
    
    if [[ $total_violations -eq 0 ]]; then
        echo "🎉 **EXCELLENT**: No principle violations or critical issues detected." >> "$REPORT_FILE"
        echo "The project maintains high adherence to core principles and success criteria." >> "$REPORT_FILE"
    elif [[ $total_violations -le 3 ]]; then
        echo "✅ **GOOD**: Minor issues detected that should be addressed." >> "$REPORT_FILE"
        echo "Overall project quality is good with room for improvement." >> "$REPORT_FILE"
    elif [[ $total_violations -le 6 ]]; then
        echo "⚠️ **NEEDS ATTENTION**: Several issues require immediate attention." >> "$REPORT_FILE"
        echo "Project quality needs improvement to meet standards." >> "$REPORT_FILE"
    else
        echo "🚨 **CRITICAL**: Major issues detected requiring immediate intervention." >> "$REPORT_FILE"
        echo "Project may not meet success criteria without significant corrections." >> "$REPORT_FILE"
    fi
    
    echo "" >> "$REPORT_FILE"
    echo "### Next Steps" >> "$REPORT_FILE"
    echo "1. Address all VIOLATION level issues immediately" >> "$REPORT_FILE"
    echo "2. Plan remediation for WARNING level issues" >> "$REPORT_FILE"
    echo "3. Implement missing SUCCESS CRITERIA components" >> "$REPORT_FILE"
    echo "4. Re-run audit after corrections" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    echo "**Report Location**: \`$REPORT_FILE\`" >> "$REPORT_FILE"
}

# Main execution
main() {
    echo -e "${GREEN}🔍 Starting Quality Audit for Family Network Platform${NC}"
    echo "Report will be generated at: $REPORT_FILE"
    echo ""
    
    # Initialize report
    init_report
    
    # Run all checks
    local total_violations=0
    
    check_universal_compatibility
    total_violations=$((total_violations + $?))
    
    check_family_experience
    total_violations=$((total_violations + $?))
    
    check_transparent_operation
    total_violations=$((total_violations + $?))
    
    check_infinite_scalability
    total_violations=$((total_violations + $?))
    
    check_production_quality
    total_violations=$((total_violations + $?))
    
    check_success_criteria
    total_violations=$((total_violations + $?))
    
    check_agent_integration
    total_violations=$((total_violations + $?))
    
    # Generate summary
    generate_summary $total_violations
    
    echo ""
    echo -e "${GREEN}✅ Quality Audit Complete${NC}"
    echo "Total issues found: $total_violations"
    echo "Report: $REPORT_FILE"
    
    # Return appropriate exit code
    if [[ $total_violations -eq 0 ]]; then
        exit 0
    elif [[ $total_violations -le 3 ]]; then
        exit 1
    else
        exit 2
    fi
}

# Handle command line arguments
case "${1:-audit}" in
    "audit")
        main
        ;;
    "help"|"-h"|"--help")
        echo "Quality Audit Script for Family Network Platform"
        echo ""
        echo "Usage: $0 [command]"
        echo ""
        echo "Commands:"
        echo "  audit    Run complete quality audit (default)"
        echo "  help     Show this help message"
        echo ""
        echo "Exit codes:"
        echo "  0        No issues found"
        echo "  1        Minor issues found"
        echo "  2        Major issues found"
        ;;
    *)
        echo "Unknown command: $1"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac