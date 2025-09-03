# Apache Solr Migration Guide

This guide provides comprehensive instructions for migrating Apache Solr from one node to another, including ZooKeeper data and Solr collections.

## Overview

The migration process involves:
1. Stopping Solr services on the source node
2. Backing up ZooKeeper znodes
3. Backing up Solr data directory
4. Transferring backups to the destination node
5. Importing znodes and data on the destination node
6. Starting services on the destination node
7. Testing the migration

## Prerequisites

Before starting the migration, ensure you have:

- Java installed on both source and destination nodes
- Sufficient disk space for backups
- Network access between nodes (if applicable)
- Administrative access to both nodes
- curl and rsync utilities (recommended)

### For Kerberos-Enabled Environments:

- Kerberos client tools (kinit, klist, kdestroy)
- Valid Kerberos keytab file
- Properly configured krb5.conf
- JAAS configuration file for Solr
- curl with SPNEGO/Negotiate support

Check prerequisites with:
```bash
./solr_migration_helper.sh prerequisites
```

## Migration Scripts

Two main scripts are provided:

1. **`solr_migration_script.sh`** - Main migration script
2. **`solr_migration_helper.sh`** - Additional utilities and validation

## Quick Start

### For Same-Node Migration (Refresh/Restore)
```bash
chmod +x solr_migration_script.sh
./solr_migration_script.sh full /tmp/solr_backup
```

### For Different-Node Migration

#### On Source Node:
```bash
chmod +x solr_migration_script.sh
./solr_migration_script.sh source /tmp/solr_backup
```

#### Transfer backup to destination node, then:
```bash
./solr_migration_script.sh destination /tmp/solr_backup
```

### For Kerberos-Enabled Environments

#### Set up Kerberos environment:
```bash
# Configure Kerberos (see kerberos_setup_example.sh)
export SOLR_KERBEROS_ENABLED="true"
export SOLR_KERBEROS_PRINCIPAL="HTTP/$(hostname -f)@YOUR-REALM.COM"
export SOLR_KERBEROS_KEYTAB="/etc/security/keytabs/solr.keytab"
export SOLR_JAAS_CONFIG="/path/to/jaas.conf"

# Run migration
./solr_migration_script.sh full /tmp/solr_backup
```

## Detailed Steps

### Step 1: Create System Report (Optional but Recommended)

Before migration, create a system report:
```bash
chmod +x solr_migration_helper.sh
./solr_migration_helper.sh report /tmp/pre_migration_report.txt
```

### Step 2: Source Node Backup

Run the backup process on the source node:
```bash
./solr_migration_script.sh source /path/to/backup/directory
```

This will:
- Stop Solr services gracefully
- Backup ZooKeeper data (znodes)
- Backup Solr data directory including:
  - Collections and cores
  - Configuration files
  - Index data
  - Schema definitions

### Step 3: Validate Backup

Verify backup integrity:
```bash
./solr_migration_helper.sh validate /path/to/backup/directory
```

### Step 4: Transfer Backup (If Different Nodes)

Transfer the backup directory to the destination node using:
- `scp -r /path/to/backup user@destination:/path/to/backup`
- `rsync -av /path/to/backup/ user@destination:/path/to/backup/`
- Or any other preferred method

### Step 5: Destination Node Restore

On the destination node, run:
```bash
./solr_migration_script.sh destination /path/to/backup/directory
```

This will:
- Stop any existing Solr services
- Import ZooKeeper znodes
- Import Solr data directory
- Start Solr services
- Perform basic connectivity tests

### Step 6: Verify Migration

Test the migrated Solr instance:
```bash
./solr_migration_helper.sh test http://localhost:8983/solr
```

## Configuration

The migration scripts use these default paths (modify as needed):

- **Solr Home**: `/workspace/solr`
- **Solr Binary**: `/workspace/solr/bin/solr`
- **Solr Data**: `/workspace/solr/server/solr`
- **ZooKeeper Data**: `/workspace/solr/server/solr/zoo_data`
- **Default Backup Location**: `/tmp/solr_migration_backup`

### Kerberos Configuration

For Kerberos-enabled environments, set these environment variables:

- **SOLR_KERBEROS_ENABLED**: Set to "true" to enable Kerberos
- **SOLR_KERBEROS_PRINCIPAL**: Service principal (e.g., "HTTP/hostname@REALM.COM")
- **SOLR_KERBEROS_KEYTAB**: Path to keytab file
- **SOLR_KERBEROS_REALM**: Kerberos realm
- **SOLR_JAAS_CONFIG**: Path to JAAS configuration file
- **KRB5_CONFIG**: Path to krb5.conf (default: /etc/krb5.conf)

To modify these paths, edit the configuration section in `solr_migration_script.sh`.

## Backup Structure

The backup directory contains:
```
backup_directory/
├── kerberos_backup/       # (If Kerberos enabled)
│   ├── krb5.conf         # Kerberos configuration
│   ├── solr.keytab       # Service keytab file
│   ├── jaas.conf         # JAAS configuration
│   └── kerberos_env.sh   # Environment setup script
├── zookeeper_backup/
│   ├── zoo_data/          # ZooKeeper data files
│   └── zk_export.sh       # ZK export utility (Kerberos-aware)
└── solr_data_backup/
    ├── collections/       # Collection data
    ├── configsets/       # Configuration sets
    ├── solr.xml          # Solr configuration
    └── collections_manifest.txt  # List of collections
```

## Troubleshooting

### Common Issues

1. **Solr Won't Stop**
   - The script will force-kill processes if graceful shutdown fails
   - Check for file locks in the data directory

2. **Insufficient Disk Space**
   - Ensure adequate space for backups (typically 2x data size)
   - Use `df -h` to check available space

3. **Permission Issues**
   - Ensure the user has read/write permissions to Solr directories
   - Check file ownership after restore

4. **Port Conflicts**
   - Default Solr port is 8983, ZooKeeper is 9983
   - Modify ports in solr.in.sh if needed

5. **Java Issues**
   - Ensure Java is installed and in PATH
   - Check Java version compatibility with Solr

6. **Kerberos Authentication Issues**
   - Verify keytab file permissions (should be 600)
   - Test authentication: `kinit -kt /path/to/keytab principal@REALM.COM`
   - Check ticket status: `klist`
   - Ensure hostname resolution works properly
   - Verify JAAS configuration syntax
   - Check krb5.conf for correct realm and KDC settings

### Validation Commands

```bash
# Check Solr status
curl http://localhost:8983/solr/admin/info/system

# List collections
curl http://localhost:8983/solr/admin/collections?action=LIST

# Check cluster status
curl http://localhost:8983/solr/admin/collections?action=CLUSTERSTATUS

# ZooKeeper status
curl http://localhost:8983/solr/admin/zookeeper?detail=true&path=/
```

## Kerberos Integration

### Setting Up Kerberos Environment

1. **Configure Environment Variables:**
```bash
# Use the provided example script
source ./kerberos_setup_example.sh

# Or set manually:
export SOLR_KERBEROS_ENABLED="true"
export SOLR_KERBEROS_PRINCIPAL="HTTP/$(hostname -f)@YOUR-REALM.COM"
export SOLR_KERBEROS_KEYTAB="/etc/security/keytabs/solr.keytab"
export SOLR_JAAS_CONFIG="/path/to/jaas.conf"
```

2. **Create JAAS Configuration:**
```bash
# Use the provided template
cp kerberos_solr_template.conf /path/to/jaas.conf
# Edit the file to match your environment
```

3. **Test Kerberos Authentication:**
```bash
kinit -kt $SOLR_KERBEROS_KEYTAB $SOLR_KERBEROS_PRINCIPAL
klist
```

### Kerberos Migration Features

The migration scripts automatically handle:

- **Kerberos Configuration Backup**: krb5.conf, keytab files, JAAS config
- **Authentication During Migration**: Automatic kinit before operations
- **Secure ZooKeeper Export**: Uses Kerberos for ZK operations
- **Environment Restoration**: Recreates Kerberos environment on destination
- **Authentication Testing**: Validates Kerberos functionality post-migration

### Kerberos-Specific Commands

```bash
# Check Kerberos prerequisites
SOLR_KERBEROS_ENABLED=true ./solr_migration_helper.sh prerequisites

# Test with Kerberos authentication
SOLR_KERBEROS_ENABLED=true ./solr_migration_helper.sh test http://localhost:8983/solr

# Validate Kerberos backup
SOLR_KERBEROS_ENABLED=true ./solr_migration_helper.sh validate /tmp/backup
```

## Advanced Options

### Custom ZooKeeper Export

If you need to export ZooKeeper configuration while Solr is running:
```bash
cd /path/to/backup/zookeeper_backup
./zk_export.sh /workspace/solr/bin/solr localhost:9983 true  # true for Kerberos
```

### Selective Collection Migration

To migrate specific collections only, modify the rsync command in the script to include/exclude specific directories.

### Cleanup Old Backups

Remove backups older than 7 days:
```bash
./solr_migration_helper.sh cleanup /tmp 7
```

## Security Considerations

- Backup files contain sensitive data - secure them appropriately
- Use encrypted transfer methods for network transfers
- Verify backup integrity before and after transfer
- Clean up temporary files after migration

## Performance Tips

- Use rsync for large data transfers (faster than cp)
- Compress backups for network transfer if bandwidth is limited
- Schedule migrations during low-traffic periods
- Monitor disk I/O during migration

## Support

For issues or questions:
1. Check the system report output
2. Validate backup integrity
3. Review Solr logs in the server/logs directory
4. Consult Solr documentation for version-specific issues

## Script Versions

- **solr_migration_script.sh**: Main migration automation
- **solr_migration_helper.sh**: Utilities and validation tools
- **README_MIGRATION.md**: This documentation

Last updated: $(date)