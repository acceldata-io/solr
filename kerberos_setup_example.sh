#!/bin/bash

# Kerberos Setup Example for Solr Migration
# This script shows how to configure Kerberos environment variables
# Modify these values according to your environment

echo "=== KERBEROS CONFIGURATION EXAMPLE ==="
echo

# Set these environment variables before running the migration
export SOLR_KERBEROS_ENABLED="true"
export SOLR_KERBEROS_PRINCIPAL="HTTP/$(hostname -f)@YOUR-REALM.COM"
export SOLR_KERBEROS_KEYTAB="/etc/security/keytabs/solr.keytab"
export SOLR_KERBEROS_REALM="YOUR-REALM.COM"
export SOLR_JAAS_CONFIG="/workspace/kerberos_solr_template.conf"
export KRB5_CONFIG="/etc/krb5.conf"

echo "Environment variables set:"
echo "SOLR_KERBEROS_ENABLED=$SOLR_KERBEROS_ENABLED"
echo "SOLR_KERBEROS_PRINCIPAL=$SOLR_KERBEROS_PRINCIPAL"
echo "SOLR_KERBEROS_KEYTAB=$SOLR_KERBEROS_KEYTAB"
echo "SOLR_KERBEROS_REALM=$SOLR_KERBEROS_REALM"
echo "SOLR_JAAS_CONFIG=$SOLR_JAAS_CONFIG"
echo "KRB5_CONFIG=$KRB5_CONFIG"
echo

echo "=== SETUP STEPS ==="
echo "1. Update the JAAS configuration file:"
echo "   - Edit $SOLR_JAAS_CONFIG"
echo "   - Replace 'hostname' with your actual hostname"
echo "   - Replace 'YOUR-REALM.COM' with your Kerberos realm"
echo "   - Update keytab path to your actual keytab location"
echo

echo "2. Ensure keytab file exists and is readable:"
echo "   - Check: ls -la $SOLR_KERBEROS_KEYTAB"
echo "   - Test: klist -k $SOLR_KERBEROS_KEYTAB"
echo

echo "3. Test Kerberos authentication:"
echo "   - kinit -kt $SOLR_KERBEROS_KEYTAB $SOLR_KERBEROS_PRINCIPAL"
echo "   - klist"
echo

echo "4. Run migration with Kerberos:"
echo "   - Source this script: source $0"
echo "   - Run migration: ./solr_migration_script.sh [source|destination|full]"
echo

echo "=== SECURITY NOTES ==="
echo "- Keytab files contain sensitive credentials - secure appropriately"
echo "- Use proper file permissions (600) for keytab files"
echo "- Ensure hostname resolution works properly"
echo "- Test authentication before starting migration"
echo

echo "To use these settings, run:"
echo "source $0"
echo "./solr_migration_script.sh full"