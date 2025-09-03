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
# ZooKeeper export script
# This script can be used to export ZK configuration when Solr is running

SOLR_BIN="$1"
ZK_HOST="${2:-localhost:9983}"

if [ -f "$SOLR_BIN" ]; then
    echo "Exporting ZooKeeper configuration..."
    $SOLR_BIN zk -z $ZK_HOST -cmd list / -r > zk_tree_structure.txt 2>&1 || echo "ZK export failed or ZK not accessible"
    $SOLR_BIN zk -z $ZK_HOST -cmd get /clusterstate.json > clusterstate.json 2>&1 || echo "Clusterstate export failed"
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
    
    if [ -f "$SOLR_BIN" ]; then
        # Start Solr in cloud mode with embedded ZooKeeper
        print_status "Starting Solr in cloud mode..."
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
    
    # Test basic connectivity
    if curl -s "http://localhost:8983/solr/admin/info/system" > /dev/null; then
        print_success "Solr is responding to HTTP requests"
    else
        print_error "Solr is not responding to HTTP requests"
        return 1
    fi
    
    # Test collections status
    print_status "Checking collections status..."
    local collections_status=$(curl -s "http://localhost:8983/solr/admin/collections?action=CLUSTERSTATUS&wt=json" | jq -r '.cluster.collections | keys[]' 2>/dev/null || echo "")
    
    if [ -n "$collections_status" ]; then
        print_success "Collections found:"
        echo "$collections_status"
    else
        print_warning "No collections found or unable to retrieve collection status"
    fi
    
    # Test ZooKeeper connectivity
    print_status "Testing ZooKeeper connectivity..."
    local zk_status=$(curl -s "http://localhost:8983/solr/admin/zookeeper?detail=true&path=/&wt=json" 2>/dev/null || echo "")
    
    if echo "$zk_status" | grep -q "znode"; then
        print_success "ZooKeeper is accessible and contains data"
    else
        print_warning "ZooKeeper connectivity test failed or no data found"
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
            stop_solr_services
            backup_zookeeper_znodes
            backup_solr_data
            print_success "Source node backup completed!"
            print_status "Backup location: $BACKUP_BASE_DIR"
            print_status "Transfer this backup to the destination node and run:"
            print_status "./solr_migration_script.sh destination $BACKUP_BASE_DIR"
            ;;
            
        "destination")
            print_status "=== DESTINATION NODE MIGRATION STEPS ==="
            stop_solr_services
            import_zookeeper_znodes
            import_solr_data
            start_solr_services
            sleep 10  # Give Solr time to fully initialize
            test_solr_services
            print_success "Destination node setup completed!"
            ;;
            
        "full")
            print_status "=== FULL MIGRATION (SINGLE NODE) ==="
            stop_solr_services
            backup_zookeeper_znodes
            backup_solr_data
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