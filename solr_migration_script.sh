#!/bin/bash

# Apache Solr Migration Script
# This script helps migrate Solr from one node to another
# Usage: ./solr_migration_script.sh [source|destination] [backup_dir] [new_node_ip]

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration - Modify these paths according to your setup
SOLR_HOME="/workspace/solr"
SOLR_BIN="$SOLR_HOME/bin/solr"
SOLR_SERVER="$SOLR_HOME/server"
SOLR_DATA_DIR="$SOLR_SERVER/solr"
ZK_DATA_DIR="$SOLR_DATA_DIR/zoo_data"
BACKUP_BASE_DIR="${2:-/tmp/solr_migration_backup}"
NEW_NODE_IP="${3:-localhost}"

# Kerberos Configuration
KERBEROS_ENABLED="${SOLR_KERBEROS_ENABLED:-false}"
KERBEROS_PRINCIPAL="${SOLR_KERBEROS_PRINCIPAL:-}"
KERBEROS_KEYTAB="${SOLR_KERBEROS_KEYTAB:-}"
KERBEROS_REALM="${SOLR_KERBEROS_REALM:-}"
JAAS_CONFIG_FILE="${SOLR_JAAS_CONFIG:-}"
KRB5_CONFIG="${KRB5_CONFIG:-/etc/krb5.conf}"

# Function to print colored output
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

# Function to check if Solr is running
check_solr_status() {
    if pgrep -f "start.jar" > /dev/null; then
        return 0  # Solr is running
    else
        return 1  # Solr is not running
    fi
}

# Function to check Kerberos configuration
check_kerberos_config() {
    if [ "$KERBEROS_ENABLED" = "true" ]; then
        print_status "Checking Kerberos configuration..."
        
        local errors=0
        
        # Check KDC connectivity
        if [ -f "$KRB5_CONFIG" ]; then
            print_success "Kerberos config found: $KRB5_CONFIG"
        else
            print_error "Kerberos config not found: $KRB5_CONFIG"
            errors=$((errors + 1))
        fi
        
        # Check principal
        if [ -n "$KERBEROS_PRINCIPAL" ]; then
            print_success "Kerberos principal configured: $KERBEROS_PRINCIPAL"
        else
            print_error "Kerberos principal not specified"
            errors=$((errors + 1))
        fi
        
        # Check keytab
        if [ -n "$KERBEROS_KEYTAB" ] && [ -f "$KERBEROS_KEYTAB" ]; then
            print_success "Kerberos keytab found: $KERBEROS_KEYTAB"
            
            # Test keytab validity
            if command -v klist &> /dev/null; then
                if klist -k "$KERBEROS_KEYTAB" &> /dev/null; then
                    print_success "Keytab is valid"
                else
                    print_warning "Keytab validation failed"
                fi
            fi
        else
            print_error "Kerberos keytab not found: $KERBEROS_KEYTAB"
            errors=$((errors + 1))
        fi
        
        # Check JAAS config
        if [ -n "$JAAS_CONFIG_FILE" ] && [ -f "$JAAS_CONFIG_FILE" ]; then
            print_success "JAAS config found: $JAAS_CONFIG_FILE"
        else
            print_warning "JAAS config not specified or not found: $JAAS_CONFIG_FILE"
        fi
        
        return $errors
    else
        print_status "Kerberos authentication disabled"
        return 0
    fi
}

# Function to backup Kerberos configuration
backup_kerberos_config() {
    if [ "$KERBEROS_ENABLED" = "true" ]; then
        print_status "Backing up Kerberos configuration..."
        
        local kerberos_backup_dir="$BACKUP_BASE_DIR/kerberos_backup"
        mkdir -p "$kerberos_backup_dir"
        
        # Backup krb5.conf
        if [ -f "$KRB5_CONFIG" ]; then
            cp "$KRB5_CONFIG" "$kerberos_backup_dir/"
            print_success "Backed up Kerberos config: $KRB5_CONFIG"
        fi
        
        # Backup keytab (if specified and exists)
        if [ -n "$KERBEROS_KEYTAB" ] && [ -f "$KERBEROS_KEYTAB" ]; then
            cp "$KERBEROS_KEYTAB" "$kerberos_backup_dir/"
            print_success "Backed up Kerberos keytab: $KERBEROS_KEYTAB"
        fi
        
        # Backup JAAS config
        if [ -n "$JAAS_CONFIG_FILE" ] && [ -f "$JAAS_CONFIG_FILE" ]; then
            cp "$JAAS_CONFIG_FILE" "$kerberos_backup_dir/"
            print_success "Backed up JAAS config: $JAAS_CONFIG_FILE"
        fi
        
        # Create Kerberos environment info
        cat > "$kerberos_backup_dir/kerberos_env.sh" << EOF
#!/bin/bash
# Kerberos environment configuration for migration

export SOLR_KERBEROS_ENABLED="$KERBEROS_ENABLED"
export SOLR_KERBEROS_PRINCIPAL="$KERBEROS_PRINCIPAL"
export SOLR_KERBEROS_KEYTAB="$KERBEROS_KEYTAB"
export SOLR_KERBEROS_REALM="$KERBEROS_REALM"
export SOLR_JAAS_CONFIG="$JAAS_CONFIG_FILE"
export KRB5_CONFIG="$KRB5_CONFIG"

# Java system properties for Kerberos
export SOLR_OPTS="\$SOLR_OPTS -Djava.security.krb5.conf=\$KRB5_CONFIG"
export SOLR_OPTS="\$SOLR_OPTS -Djava.security.auth.login.config=\$SOLR_JAAS_CONFIG"
export SOLR_OPTS="\$SOLR_OPTS -Dsolr.kerberos.principal=\$SOLR_KERBEROS_PRINCIPAL"
export SOLR_OPTS="\$SOLR_OPTS -Dsolr.kerberos.keytab=\$SOLR_KERBEROS_KEYTAB"
export SOLR_OPTS="\$SOLR_OPTS -Dsolr.kerberos.name.rules=DEFAULT"

echo "Kerberos environment configured for Solr migration"
EOF
        chmod +x "$kerberos_backup_dir/kerberos_env.sh"
        
        print_success "Kerberos configuration backed up to $kerberos_backup_dir"
    else
        print_status "Kerberos disabled, skipping Kerberos backup"
    fi
}

# Function to restore Kerberos configuration
restore_kerberos_config() {
    if [ "$KERBEROS_ENABLED" = "true" ]; then
        print_status "Restoring Kerberos configuration..."
        
        local kerberos_backup_dir="$BACKUP_BASE_DIR/kerberos_backup"
        
        if [ ! -d "$kerberos_backup_dir" ]; then
            print_error "Kerberos backup directory not found: $kerberos_backup_dir"
            return 1
        fi
        
        # Restore krb5.conf
        if [ -f "$kerberos_backup_dir/krb5.conf" ]; then
            sudo cp "$kerberos_backup_dir/krb5.conf" "$KRB5_CONFIG" 2>/dev/null || {
                print_warning "Could not copy krb5.conf to $KRB5_CONFIG (permission denied)"
                print_status "Please manually copy $kerberos_backup_dir/krb5.conf to $KRB5_CONFIG"
            }
        fi
        
        # Restore keytab
        if [ -f "$kerberos_backup_dir/$(basename "$KERBEROS_KEYTAB")" ] && [ -n "$KERBEROS_KEYTAB" ]; then
            mkdir -p "$(dirname "$KERBEROS_KEYTAB")"
            cp "$kerberos_backup_dir/$(basename "$KERBEROS_KEYTAB")" "$KERBEROS_KEYTAB"
            chmod 600 "$KERBEROS_KEYTAB"  # Secure the keytab
            print_success "Restored Kerberos keytab: $KERBEROS_KEYTAB"
        fi
        
        # Restore JAAS config
        if [ -f "$kerberos_backup_dir/$(basename "$JAAS_CONFIG_FILE")" ] && [ -n "$JAAS_CONFIG_FILE" ]; then
            mkdir -p "$(dirname "$JAAS_CONFIG_FILE")"
            cp "$kerberos_backup_dir/$(basename "$JAAS_CONFIG_FILE")" "$JAAS_CONFIG_FILE"
            print_success "Restored JAAS config: $JAAS_CONFIG_FILE"
        fi
        
        # Source the Kerberos environment
        if [ -f "$kerberos_backup_dir/kerberos_env.sh" ]; then
            source "$kerberos_backup_dir/kerberos_env.sh"
            print_success "Kerberos environment variables loaded"
        fi
        
        print_success "Kerberos configuration restored"
    else
        print_status "Kerberos disabled, skipping Kerberos restore"
    fi
}

# Function to authenticate with Kerberos
kerberos_authenticate() {
    if [ "$KERBEROS_ENABLED" = "true" ]; then
        print_status "Authenticating with Kerberos..."
        
        if [ -n "$KERBEROS_KEYTAB" ] && [ -f "$KERBEROS_KEYTAB" ] && [ -n "$KERBEROS_PRINCIPAL" ]; then
            # Authenticate using keytab
            if command -v kinit &> /dev/null; then
                kinit -kt "$KERBEROS_KEYTAB" "$KERBEROS_PRINCIPAL"
                if [ $? -eq 0 ]; then
                    print_success "Kerberos authentication successful"
                    
                    # Show current ticket
                    if command -v klist &> /dev/null; then
                        print_status "Current Kerberos ticket:"
                        klist | head -5
                    fi
                else
                    print_error "Kerberos authentication failed"
                    return 1
                fi
            else
                print_error "kinit command not found. Install Kerberos client tools."
                return 1
            fi
        else
            print_warning "Kerberos enabled but keytab or principal not properly configured"
            return 1
        fi
    fi
    
    return 0
}

# Function to stop Solr services
stop_solr_services() {
    print_status "Stopping Solr services..."
    
    if check_solr_status; then
        print_status "Solr is running. Attempting to stop..."
        
        # Try graceful shutdown first
        if [ -f "$SOLR_BIN" ]; then
            $SOLR_BIN stop -all || true
            sleep 5
        fi
        
        # Force kill if still running
        if check_solr_status; then
            print_warning "Graceful shutdown failed. Force killing Solr processes..."
            pkill -f "start.jar" || true
            sleep 3
        fi
        
        if check_solr_status; then
            print_error "Failed to stop Solr services"
            exit 1
        else
            print_success "Solr services stopped successfully"
        fi
    else
        print_status "Solr is not running"
    fi
}

# Function to backup ZooKeeper znodes
backup_zookeeper_znodes() {
    print_status "Creating backup of ZooKeeper znodes..."
    
    local zk_backup_dir="$BACKUP_BASE_DIR/zookeeper_backup"
    mkdir -p "$zk_backup_dir"
    
    # Authenticate with Kerberos if needed
    kerberos_authenticate
    
    # Check if ZooKeeper data directory exists
    if [ -d "$ZK_DATA_DIR" ]; then
        print_status "Backing up ZooKeeper data from $ZK_DATA_DIR"
        cp -r "$ZK_DATA_DIR" "$zk_backup_dir/"
        print_success "ZooKeeper data backed up to $zk_backup_dir"
    else
        print_warning "ZooKeeper data directory not found at $ZK_DATA_DIR"
        print_status "Looking for alternative ZooKeeper data locations..."
        
        # Look for other possible ZK data directories
        find "$SOLR_DATA_DIR" -name "zoo_data" -type d 2>/dev/null | while read zkdir; do
            print_status "Found ZooKeeper data at: $zkdir"
            cp -r "$zkdir" "$zk_backup_dir/$(basename $(dirname $zkdir))_zoo_data"
        done
    fi
    
    # Create a script to export ZK configuration if Solr is running with embedded ZK
    cat > "$zk_backup_dir/zk_export.sh" << 'EOF'
#!/bin/bash
# ZooKeeper export script with Kerberos support
# This script can be used to export ZK configuration when Solr is running

SOLR_BIN="$1"
ZK_HOST="${2:-localhost:9983}"
KERBEROS_ENABLED="${3:-false}"

# Set up Kerberos environment if enabled
if [ "$KERBEROS_ENABLED" = "true" ] && [ -f "./kerberos_env.sh" ]; then
    echo "Loading Kerberos environment..."
    source ./kerberos_env.sh
fi

if [ -f "$SOLR_BIN" ]; then
    echo "Exporting ZooKeeper configuration..."
    
    # Export with Kerberos authentication if enabled
    if [ "$KERBEROS_ENABLED" = "true" ]; then
        echo "Using Kerberos authentication for ZK export..."
        # Set JAAS config for Solr ZK commands
        export SOLR_OPTS="$SOLR_OPTS -Djava.security.auth.login.config=$SOLR_JAAS_CONFIG"
    fi
    
    $SOLR_BIN zk -z $ZK_HOST -cmd list / -r > zk_tree_structure.txt 2>&1 || echo "ZK export failed or ZK not accessible"
    $SOLR_BIN zk -z $ZK_HOST -cmd get /clusterstate.json > clusterstate.json 2>&1 || echo "Clusterstate export failed"
    $SOLR_BIN zk -z $ZK_HOST -cmd get /security.json > security.json 2>&1 || echo "Security config export failed (normal if not using security)"
    $SOLR_BIN zk -z $ZK_HOST -cmd get /solr.xml > solr_zk.xml 2>&1 || echo "Solr ZK config export failed"
    
    echo "ZK export completed"
fi
EOF
    chmod +x "$zk_backup_dir/zk_export.sh"
}

# Function to backup Solr data directory
backup_solr_data() {
    print_status "Creating backup of Solr data directory..."
    
    local solr_backup_dir="$BACKUP_BASE_DIR/solr_data_backup"
    mkdir -p "$solr_backup_dir"
    
    if [ -d "$SOLR_DATA_DIR" ]; then
        print_status "Backing up Solr data from $SOLR_DATA_DIR"
        
        # Backup the entire solr data directory
        rsync -av --progress "$SOLR_DATA_DIR/" "$solr_backup_dir/" \
            --exclude="zoo_data/version-*" \
            --exclude="*.lock" \
            --exclude="*.lck"
            
        print_success "Solr data backed up to $solr_backup_dir"
        
        # Create a manifest of backed up collections
        find "$solr_backup_dir" -name "core.properties" -exec dirname {} \; | \
        sed "s|$solr_backup_dir/||" > "$solr_backup_dir/collections_manifest.txt"
        
        print_status "Collections found:"
        cat "$solr_backup_dir/collections_manifest.txt"
        
    else
        print_error "Solr data directory not found at $SOLR_DATA_DIR"
        exit 1
    fi
}

# Function to import znodes to new node
import_zookeeper_znodes() {
    print_status "Importing ZooKeeper znodes to new node..."
    
    local zk_backup_dir="$BACKUP_BASE_DIR/zookeeper_backup"
    
    if [ ! -d "$zk_backup_dir" ]; then
        print_error "ZooKeeper backup directory not found at $zk_backup_dir"
        exit 1
    fi
    
    # Restore ZooKeeper data
    if [ -d "$zk_backup_dir/zoo_data" ]; then
        print_status "Restoring ZooKeeper data to $ZK_DATA_DIR"
        mkdir -p "$(dirname "$ZK_DATA_DIR")"
        cp -r "$zk_backup_dir/zoo_data" "$ZK_DATA_DIR"
        print_success "ZooKeeper data restored"
    else
        print_warning "No zoo_data directory found in backup"
        # Look for other backed up zoo_data directories
        find "$zk_backup_dir" -name "*zoo_data" -type d | head -1 | while read zkdir; do
            if [ -n "$zkdir" ]; then
                print_status "Restoring ZooKeeper data from $zkdir"
                cp -r "$zkdir" "$ZK_DATA_DIR"
            fi
        done
    fi
}

# Function to import Solr data directory
import_solr_data() {
    print_status "Importing Solr data directory to new node..."
    
    local solr_backup_dir="$BACKUP_BASE_DIR/solr_data_backup"
    
    if [ ! -d "$solr_backup_dir" ]; then
        print_error "Solr backup directory not found at $solr_backup_dir"
        exit 1
    fi
    
    print_status "Restoring Solr data to $SOLR_DATA_DIR"
    mkdir -p "$SOLR_DATA_DIR"
    
    # Restore Solr data
    rsync -av --progress "$solr_backup_dir/" "$SOLR_DATA_DIR/" \
        --exclude="*.lock" \
        --exclude="*.lck"
    
    print_success "Solr data restored to $SOLR_DATA_DIR"
    
    # Display restored collections
    if [ -f "$solr_backup_dir/collections_manifest.txt" ]; then
        print_status "Restored collections:"
        cat "$solr_backup_dir/collections_manifest.txt"
    fi
}

# Function to start Solr services
start_solr_services() {
    print_status "Starting Solr services..."
    
    if check_solr_status; then
        print_warning "Solr is already running"
        return 0
    fi
    
    # Authenticate with Kerberos before starting Solr
    kerberos_authenticate
    
    if [ -f "$SOLR_BIN" ]; then
        # Configure Kerberos environment for Solr startup
        if [ "$KERBEROS_ENABLED" = "true" ]; then
            print_status "Configuring Kerberos environment for Solr startup..."
            
            # Set Kerberos-related SOLR_OPTS
            export SOLR_OPTS="$SOLR_OPTS -Djava.security.krb5.conf=$KRB5_CONFIG"
            if [ -n "$JAAS_CONFIG_FILE" ]; then
                export SOLR_OPTS="$SOLR_OPTS -Djava.security.auth.login.config=$JAAS_CONFIG_FILE"
            fi
            export SOLR_OPTS="$SOLR_OPTS -Dsolr.kerberos.principal=$KERBEROS_PRINCIPAL"
            export SOLR_OPTS="$SOLR_OPTS -Dsolr.kerberos.keytab=$KERBEROS_KEYTAB"
            export SOLR_OPTS="$SOLR_OPTS -Dsolr.kerberos.name.rules=DEFAULT"
            
            print_status "Kerberos environment configured for Solr"
        fi
        
        # Start Solr in cloud mode with embedded ZooKeeper
        print_status "Starting Solr in cloud mode..."
        if [ "$KERBEROS_ENABLED" = "true" ]; then
            print_status "Starting with Kerberos authentication enabled..."
        fi
        
        $SOLR_BIN start -c -p 8983 -s "$SOLR_DATA_DIR"
        
        # Wait for Solr to start
        local attempts=0
        local max_attempts=30
        
        while [ $attempts -lt $max_attempts ]; do
            if curl -s "http://localhost:8983/solr/admin/info/system" > /dev/null 2>&1; then
                print_success "Solr started successfully"
                return 0
            fi
            print_status "Waiting for Solr to start... (attempt $((attempts + 1))/$max_attempts)"
            sleep 5
            attempts=$((attempts + 1))
        done
        
        print_error "Solr failed to start within expected time"
        return 1
    else
        print_error "Solr binary not found at $SOLR_BIN"
        return 1
    fi
}

# Function to test Solr services
test_solr_services() {
    print_status "Testing Solr services..."
    
    # Prepare curl command with Kerberos authentication if needed
    local curl_cmd="curl -s"
    if [ "$KERBEROS_ENABLED" = "true" ]; then
        print_status "Testing with Kerberos authentication..."
        curl_cmd="curl -s --negotiate -u :"
    fi
    
    # Test basic connectivity
    if $curl_cmd "http://localhost:8983/solr/admin/info/system" > /dev/null; then
        print_success "Solr is responding to HTTP requests"
    else
        print_error "Solr is not responding to HTTP requests"
        return 1
    fi
    
    # Test collections status
    print_status "Checking collections status..."
    local collections_status=$($curl_cmd "http://localhost:8983/solr/admin/collections?action=CLUSTERSTATUS&wt=json" | jq -r '.cluster.collections | keys[]' 2>/dev/null || echo "")
    
    if [ -n "$collections_status" ]; then
        print_success "Collections found:"
        echo "$collections_status"
    else
        print_warning "No collections found or unable to retrieve collection status"
    fi
    
    # Test ZooKeeper connectivity
    print_status "Testing ZooKeeper connectivity..."
    local zk_status=$($curl_cmd "http://localhost:8983/solr/admin/zookeeper?detail=true&path=/&wt=json" 2>/dev/null || echo "")
    
    if echo "$zk_status" | grep -q "znode"; then
        print_success "ZooKeeper is accessible and contains data"
    else
        print_warning "ZooKeeper connectivity test failed or no data found"
    fi
    
    # Test Kerberos authentication if enabled
    if [ "$KERBEROS_ENABLED" = "true" ]; then
        print_status "Testing Kerberos authentication..."
        local auth_test=$($curl_cmd "http://localhost:8983/solr/admin/authentication" 2>/dev/null || echo "")
        if echo "$auth_test" | grep -q "authentication"; then
            print_success "Kerberos authentication is working"
        else
            print_warning "Kerberos authentication test inconclusive"
        fi
    fi
    
    print_success "Solr service testing completed"
}

# Main execution logic
main() {
    local operation="$1"
    
    print_status "Apache Solr Migration Script"
    print_status "Operation: $operation"
    print_status "Backup Directory: $BACKUP_BASE_DIR"
    print_status "New Node IP: $NEW_NODE_IP"
    echo
    
    case "$operation" in
        "source")
            print_status "=== SOURCE NODE MIGRATION STEPS ==="
            check_kerberos_config
            stop_solr_services
            backup_kerberos_config
            backup_zookeeper_znodes
            backup_solr_data
            print_success "Source node backup completed!"
            print_status "Backup location: $BACKUP_BASE_DIR"
            if [ "$KERBEROS_ENABLED" = "true" ]; then
                print_status "Kerberos configuration included in backup"
            fi
            print_status "Transfer this backup to the destination node and run:"
            print_status "./solr_migration_script.sh destination $BACKUP_BASE_DIR"
            ;;
            
        "destination")
            print_status "=== DESTINATION NODE MIGRATION STEPS ==="
            stop_solr_services
            restore_kerberos_config
            check_kerberos_config
            import_zookeeper_znodes
            import_solr_data
            start_solr_services
            sleep 10  # Give Solr time to fully initialize
            test_solr_services
            print_success "Destination node setup completed!"
            ;;
            
        "full")
            print_status "=== FULL MIGRATION (SINGLE NODE) ==="
            check_kerberos_config
            stop_solr_services
            backup_kerberos_config
            backup_zookeeper_znodes
            backup_solr_data
            restore_kerberos_config
            import_zookeeper_znodes
            import_solr_data
            start_solr_services
            sleep 10
            test_solr_services
            print_success "Full migration completed!"
            ;;
            
        *)
            print_error "Invalid operation. Usage:"
            echo "  $0 source [backup_dir] [new_node_ip]     - Backup current node"
            echo "  $0 destination [backup_dir] [new_node_ip] - Restore to new node"
            echo "  $0 full [backup_dir] [new_node_ip]       - Full migration on single node"
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"