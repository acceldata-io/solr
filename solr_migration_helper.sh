#!/bin/bash

# Solr Migration Helper Script
# Additional utilities for Solr migration

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to create a detailed system report
create_system_report() {
    local report_file="${1:-/tmp/solr_system_report.txt}"
    
    print_status "Creating system report: $report_file"
    
    {
        echo "=== SOLR MIGRATION SYSTEM REPORT ==="
        echo "Generated on: $(date)"
        echo "Hostname: $(hostname)"
        echo "User: $(whoami)"
        echo
        
        echo "=== SYSTEM INFORMATION ==="
        echo "OS: $(uname -a)"
        echo "Memory: $(free -h)"
        echo "Disk Space:"
        df -h
        echo
        
        echo "=== JAVA INFORMATION ==="
        if command -v java &> /dev/null; then
            java -version 2>&1
        else
            echo "Java not found in PATH"
        fi
        echo
        
        echo "=== SOLR PROCESS INFORMATION ==="
        ps aux | grep -i solr || echo "No Solr processes found"
        echo
        
        echo "=== NETWORK PORTS ==="
        netstat -tlnp 2>/dev/null | grep -E ":(8983|9983|2181)" || echo "No Solr/ZK ports found listening"
        echo
        
        echo "=== SOLR DIRECTORY STRUCTURE ==="
        if [ -d "/workspace/solr" ]; then
            find /workspace/solr -type d -maxdepth 3 | head -20
        else
            echo "Solr directory not found at /workspace/solr"
        fi
        echo
        
        echo "=== SOLR CONFIGURATION FILES ==="
        find /workspace -name "solr.xml" -o -name "zoo.cfg" -o -name "solrconfig.xml" 2>/dev/null | head -10
        echo
        
        echo "=== COLLECTIONS AND CORES ==="
        if [ -d "/workspace/solr/server/solr" ]; then
            find /workspace/solr/server/solr -name "core.properties" -exec dirname {} \; 2>/dev/null | sed 's|.*/||'
        else
            echo "Solr server directory not found"
        fi
        
    } > "$report_file"
    
    print_success "System report created: $report_file"
}

# Function to validate backup integrity
validate_backup() {
    local backup_dir="$1"
    
    if [ -z "$backup_dir" ] || [ ! -d "$backup_dir" ]; then
        print_error "Backup directory not specified or doesn't exist"
        return 1
    fi
    
    print_status "Validating backup integrity: $backup_dir"
    
    local errors=0
    
    # Check Kerberos backup if enabled
    if [ "${SOLR_KERBEROS_ENABLED:-false}" = "true" ]; then
        if [ -d "$backup_dir/kerberos_backup" ]; then
            print_success "Kerberos backup directory found"
            
            if [ -f "$backup_dir/kerberos_backup/kerberos_env.sh" ]; then
                print_success "Kerberos environment configuration found"
            else
                print_warning "Kerberos environment configuration missing"
            fi
            
            if [ -f "$backup_dir/kerberos_backup/krb5.conf" ]; then
                print_success "Kerberos configuration (krb5.conf) found in backup"
            else
                print_warning "Kerberos configuration (krb5.conf) not found in backup"
                errors=$((errors + 1))
            fi
        else
            print_error "Kerberos backup directory missing (required when Kerberos enabled)"
            errors=$((errors + 1))
        fi
    fi
    
    # Check ZooKeeper backup
    if [ -d "$backup_dir/zookeeper_backup" ]; then
        print_success "ZooKeeper backup directory found"
        
        if find "$backup_dir/zookeeper_backup" -name "zoo_data" -type d | grep -q .; then
            print_success "ZooKeeper data found in backup"
        else
            print_warning "ZooKeeper data directory not found in backup"
            errors=$((errors + 1))
        fi
    else
        print_error "ZooKeeper backup directory missing"
        errors=$((errors + 1))
    fi
    
    # Check Solr data backup
    if [ -d "$backup_dir/solr_data_backup" ]; then
        print_success "Solr data backup directory found"
        
        if [ -f "$backup_dir/solr_data_backup/solr.xml" ]; then
            print_success "Solr configuration found in backup"
        else
            print_warning "Solr configuration (solr.xml) not found in backup"
            errors=$((errors + 1))
        fi
        
        if [ -f "$backup_dir/solr_data_backup/collections_manifest.txt" ]; then
            local collection_count=$(wc -l < "$backup_dir/solr_data_backup/collections_manifest.txt")
            print_success "Collections manifest found ($collection_count collections)"
        else
            print_warning "Collections manifest not found"
        fi
    else
        print_error "Solr data backup directory missing"
        errors=$((errors + 1))
    fi
    
    # Calculate backup size
    local backup_size=$(du -sh "$backup_dir" 2>/dev/null | cut -f1)
    print_status "Total backup size: $backup_size"
    
    if [ $errors -eq 0 ]; then
        print_success "Backup validation completed successfully"
        return 0
    else
        print_error "Backup validation found $errors error(s)"
        return 1
    fi
}

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking migration prerequisites..."
    
    local errors=0
    
    # Check Java
    if command -v java &> /dev/null; then
        print_success "Java found: $(java -version 2>&1 | head -1)"
    else
        print_error "Java not found. Solr requires Java to run."
        errors=$((errors + 1))
    fi
    
    # Check Kerberos tools if Kerberos is enabled
    if [ "${SOLR_KERBEROS_ENABLED:-false}" = "true" ]; then
        print_status "Checking Kerberos prerequisites..."
        
        if command -v kinit &> /dev/null; then
            print_success "kinit found"
        else
            print_error "kinit not found. Install Kerberos client tools (krb5-user)."
            errors=$((errors + 1))
        fi
        
        if command -v klist &> /dev/null; then
            print_success "klist found"
        else
            print_error "klist not found. Install Kerberos client tools (krb5-user)."
            errors=$((errors + 1))
        fi
        
        if command -v kdestroy &> /dev/null; then
            print_success "kdestroy found"
        else
            print_warning "kdestroy not found. Ticket cleanup may be manual."
        fi
        
        # Check if curl supports SPNEGO/Negotiate
        if curl --help all 2>&1 | grep -q "negotiate"; then
            print_success "curl supports Kerberos authentication (--negotiate)"
        else
            print_warning "curl may not support Kerberos authentication"
        fi
    fi
    
    # Check curl
    if command -v curl &> /dev/null; then
        print_success "curl found"
    else
        print_error "curl not found. Required for testing Solr services."
        errors=$((errors + 1))
    fi
    
    # Check rsync
    if command -v rsync &> /dev/null; then
        print_success "rsync found"
    else
        print_warning "rsync not found. Will use cp for file operations."
    fi
    
    # Check jq (optional)
    if command -v jq &> /dev/null; then
        print_success "jq found (JSON processing)"
    else
        print_warning "jq not found. JSON processing will be limited."
    fi
    
    # Check disk space
    local available_space=$(df /tmp | tail -1 | awk '{print $4}')
    if [ "$available_space" -gt 1048576 ]; then  # 1GB in KB
        print_success "Sufficient disk space available"
    else
        print_warning "Low disk space. Migration may fail if backups are large."
    fi
    
    # Check Solr directory
    if [ -d "/workspace/solr" ]; then
        print_success "Solr directory found"
        
        if [ -f "/workspace/solr/bin/solr" ]; then
            print_success "Solr binary found"
        else
            print_error "Solr binary not found at /workspace/solr/bin/solr"
            errors=$((errors + 1))
        fi
    else
        print_error "Solr directory not found at /workspace/solr"
        errors=$((errors + 1))
    fi
    
    if [ $errors -eq 0 ]; then
        print_success "All prerequisites check passed"
        return 0
    else
        print_error "Prerequisites check found $errors error(s)"
        return 1
    fi
}

# Function to cleanup old backups
cleanup_old_backups() {
    local backup_base_dir="${1:-/tmp}"
    local days_to_keep="${2:-7}"
    
    print_status "Cleaning up backups older than $days_to_keep days in $backup_base_dir"
    
    find "$backup_base_dir" -name "solr_migration_backup*" -type d -mtime +$days_to_keep -exec rm -rf {} + 2>/dev/null || true
    
    print_success "Cleanup completed"
}

# Function to create a quick migration test
quick_migration_test() {
    local solr_url="${1:-http://localhost:8983/solr}"
    
    print_status "Running quick migration test against $solr_url"
    
    # Prepare curl command with Kerberos authentication if needed
    local curl_cmd="curl -s"
    if [ "${SOLR_KERBEROS_ENABLED:-false}" = "true" ]; then
        print_status "Using Kerberos authentication for testing..."
        curl_cmd="curl -s --negotiate -u :"
        
        # Check if we have a valid Kerberos ticket
        if command -v klist &> /dev/null; then
            if klist -s 2>/dev/null; then
                print_success "Valid Kerberos ticket found"
            else
                print_warning "No valid Kerberos ticket. You may need to run 'kinit'"
            fi
        fi
    fi
    
    # Test 1: Basic connectivity
    if $curl_cmd "$solr_url/admin/info/system" > /dev/null; then
        print_success "✓ Solr is accessible"
    else
        print_error "✗ Cannot connect to Solr"
        return 1
    fi
    
    # Test 2: Admin API
    local admin_response=$($curl_cmd "$solr_url/admin/cores?action=STATUS&wt=json")
    if echo "$admin_response" | grep -q "responseHeader"; then
        print_success "✓ Admin API is working"
    else
        print_error "✗ Admin API is not responding correctly"
        return 1
    fi
    
    # Test 3: Collections (if in cloud mode)
    local collections_response=$($curl_cmd "$solr_url/admin/collections?action=CLUSTERSTATUS&wt=json" 2>/dev/null)
    if echo "$collections_response" | grep -q "cluster"; then
        print_success "✓ Cloud mode is active"
        local collection_count=$(echo "$collections_response" | jq -r '.cluster.collections | length' 2>/dev/null || echo "unknown")
        print_status "  Collections found: $collection_count"
    else
        print_status "✓ Standalone mode (no collections API)"
    fi
    
    # Test ZooKeeper connectivity
    print_status "Testing ZooKeeper connectivity..."
    local zk_status=$($curl_cmd "$solr_url/admin/zookeeper?detail=true&path=/&wt=json" 2>/dev/null || echo "")
    
    if echo "$zk_status" | grep -q "znode"; then
        print_success "✓ ZooKeeper is accessible and contains data"
    else
        print_warning "ZooKeeper connectivity test failed or no data found"
    fi
    
    # Test Kerberos authentication if enabled
    if [ "${SOLR_KERBEROS_ENABLED:-false}" = "true" ]; then
        print_status "Testing Kerberos authentication..."
        local auth_test=$($curl_cmd "$solr_url/admin/authentication" 2>/dev/null || echo "")
        if echo "$auth_test" | grep -q "authentication"; then
            print_success "✓ Kerberos authentication is working"
        else
            print_warning "Kerberos authentication test inconclusive"
        fi
        
        # Check current Kerberos ticket
        if command -v klist &> /dev/null; then
            if klist -s 2>/dev/null; then
                print_success "✓ Valid Kerberos ticket present"
                klist | head -3 | tail -1
            else
                print_warning "No valid Kerberos ticket found"
            fi
        fi
    fi
    
    print_success "Quick migration test completed"
}

# Main function
main() {
    local command="$1"
    
    case "$command" in
        "report")
            create_system_report "$2"
            ;;
        "validate")
            validate_backup "$2"
            ;;
        "prerequisites"|"prereq")
            check_prerequisites
            ;;
        "cleanup")
            cleanup_old_backups "$2" "$3"
            ;;
        "test")
            quick_migration_test "$2"
            ;;
        *)
            echo "Solr Migration Helper Script"
            echo "Usage: $0 <command> [options]"
            echo
            echo "Commands:"
            echo "  report [file]              - Create system report"
            echo "  validate <backup_dir>      - Validate backup integrity"
            echo "  prerequisites              - Check migration prerequisites"
            echo "  cleanup [dir] [days]       - Clean old backups (default: /tmp, 7 days)"
            echo "  test [solr_url]           - Quick migration test"
            echo
            echo "Examples:"
            echo "  $0 report /tmp/system_report.txt"
            echo "  $0 validate /tmp/solr_migration_backup"
            echo "  $0 prerequisites"
            echo "  $0 test http://localhost:8983/solr"
            exit 1
            ;;
    esac
}

main "$@"