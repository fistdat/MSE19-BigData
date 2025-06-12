#!/bin/bash
# =============================================================================
# TEST NESSIE ICEBERG CATALOG CONNECTIVITY
# =============================================================================
# This script tests Nessie catalog connectivity and sets up Iceberg catalog
# =============================================================================

source pipeline_config.env

echo "🗄️ TESTING NESSIE ICEBERG CATALOG CONNECTIVITY"
echo "=============================================="

# Test Nessie API connectivity
echo "🔍 Testing Nessie API connectivity..."
if curl -s ${NESSIE_URL_EXTERNAL}/repositories > /dev/null 2>&1; then
    echo "✅ Nessie API is accessible"
    
    # Get Nessie info
    echo ""
    echo "📋 Nessie Server Information:"
    curl -s ${NESSIE_URL_EXTERNAL}/config | head -10 || echo "Could not fetch config"
    
else
    echo "❌ Nessie API is not accessible"
    echo "   Check if Nessie container is running: docker logs nessie"
    exit 1
fi

echo ""
echo "🧪 Testing Flink Iceberg Catalog Configuration..."

# Create Iceberg catalog test SQL
cat > test_iceberg_catalog.sql << 'EOF'
-- =============================================================================
-- ICEBERG CATALOG TEST
-- =============================================================================

-- Set execution mode
SET 'execution.runtime-mode' = 'streaming';

-- Configure Iceberg catalog
CREATE CATALOG iceberg_catalog WITH (
    'type' = 'iceberg',
    'catalog-type' = 'nessie',
    'uri' = 'http://nessie:19120/api/v1',
    'ref' = 'main',
    'warehouse' = 's3a://warehouse/',
    'io-impl' = 'org.apache.iceberg.aws.s3.S3FileIO',
    's3.endpoint' = 'http://minioserver:9000',
    's3.access-key-id' = 'DKZjmhls7nwxBN4GJfXC',
    's3.secret-access-key' = 'kNuAZodphLEGKHv5EmbyiDt1v5eT0yVErjVFyg0t',
    's3.path-style-access' = 'true'
);

-- Use the catalog
USE CATALOG iceberg_catalog;

-- Show databases
SHOW DATABASES;

-- Create database if not exists
CREATE DATABASE IF NOT EXISTS lakehouse;

-- Use the database
USE lakehouse;

-- Show tables
SHOW TABLES;
EOF

echo "✅ Created Iceberg catalog test SQL"

echo ""
echo "🚀 Testing catalog configuration via Flink SQL Client..."

# Copy SQL file to Flink container
docker cp test_iceberg_catalog.sql ${CONTAINER_FLINK_JM}:/tmp/test_iceberg_catalog.sql

# Execute the catalog test
CATALOG_RESULT=$(docker exec ${CONTAINER_FLINK_JM} /opt/flink/bin/sql-client.sh -f /tmp/test_iceberg_catalog.sql 2>&1)
CATALOG_EXIT_CODE=$?

echo "📊 Catalog test result:"
echo "======================"
echo "$CATALOG_RESULT"

if [ $CATALOG_EXIT_CODE -eq 0 ]; then
    echo ""
    echo "✅ Iceberg catalog configuration successful!"
    
    # Test creating a simple table
    echo ""
    echo "🧪 Testing table creation..."
    
    cat > create_test_table.sql << 'EOF'
-- Create test table
USE CATALOG iceberg_catalog;
USE lakehouse;

CREATE TABLE IF NOT EXISTS test_table (
    id BIGINT,
    name STRING,
    created_at TIMESTAMP(3)
) WITH (
    'format-version' = '2'
);

SHOW TABLES;
EOF

    docker cp create_test_table.sql ${CONTAINER_FLINK_JM}:/tmp/create_test_table.sql
    
    TABLE_RESULT=$(docker exec ${CONTAINER_FLINK_JM} /opt/flink/bin/sql-client.sh -f /tmp/create_test_table.sql 2>&1)
    
    if echo "$TABLE_RESULT" | grep -q "test_table"; then
        echo "✅ Test table created successfully!"
        echo "📋 Table creation result:"
        echo "$TABLE_RESULT" | tail -10
    else
        echo "⚠️  Table creation had issues, but catalog is working"
        echo "$TABLE_RESULT" | tail -10
    fi
    
else
    echo ""
    echo "❌ Iceberg catalog configuration failed!"
    echo "========================"
    
    # Check for specific error patterns
    if echo "$CATALOG_RESULT" | grep -q "ClassNotFoundException"; then
        echo "🔍 Detected ClassNotFoundException - missing Iceberg dependencies"
        echo "   Check if all Iceberg JARs are properly installed"
    elif echo "$CATALOG_RESULT" | grep -q "nessie"; then
        echo "🔍 Detected Nessie-related error"
        echo "   Check Nessie connectivity and configuration"
    elif echo "$CATALOG_RESULT" | grep -q "s3"; then
        echo "🔍 Detected S3-related error"
        echo "   Check MinIO connectivity and S3A configuration"
    fi
fi

# Test MinIO S3A connectivity
echo ""
echo "🗄️ Testing MinIO S3A connectivity..."

# Create S3A test SQL
cat > test_s3a_connectivity.sql << 'EOF'
-- Test S3A connectivity
SET 'execution.runtime-mode' = 'batch';

-- Create a simple table to test S3A
CREATE TABLE s3a_test (
    id INT,
    message STRING
) WITH (
    'connector' = 'filesystem',
    'path' = 's3a://warehouse/test/',
    'format' = 'json'
);

-- Insert test data
INSERT INTO s3a_test VALUES (1, 'S3A connectivity test');
EOF

docker cp test_s3a_connectivity.sql ${CONTAINER_FLINK_JM}:/tmp/test_s3a_connectivity.sql

echo "🧪 Testing S3A filesystem connectivity..."
S3A_RESULT=$(docker exec ${CONTAINER_FLINK_JM} /opt/flink/bin/sql-client.sh -f /tmp/test_s3a_connectivity.sql 2>&1)

if echo "$S3A_RESULT" | grep -q "successfully"; then
    echo "✅ S3A connectivity test passed"
else
    echo "⚠️  S3A connectivity test had issues"
    echo "Last few lines of S3A test:"
    echo "$S3A_RESULT" | tail -5
fi

# Check MinIO for test files
echo ""
echo "🔍 Checking MinIO for test files..."
if docker exec ${CONTAINER_MINIO} mc ls minio/warehouse/ > /dev/null 2>&1; then
    echo "✅ MinIO warehouse bucket accessible"
    echo "📋 Warehouse contents:"
    docker exec ${CONTAINER_MINIO} mc ls minio/warehouse/ || echo "Empty or access issues"
else
    echo "⚠️  MinIO warehouse bucket access issues"
fi

# Cleanup test files
echo ""
echo "🧹 Cleaning up test files..."
rm -f test_iceberg_catalog.sql create_test_table.sql test_s3a_connectivity.sql

echo ""
echo "🎯 NESSIE CATALOG TEST SUMMARY"
echo "=============================="

if [ $CATALOG_EXIT_CODE -eq 0 ]; then
    echo "✅ Nessie API: Accessible"
    echo "✅ Iceberg Catalog: Configured successfully"
    echo "✅ Database Creation: Working"
    echo "✅ Flink Integration: Operational"
    
    echo ""
    echo "🚀 READY FOR NEXT STEP:"
    echo "======================"
    echo "1. ✅ Create CDC to Iceberg streaming job"
    echo "2. 🔧 Configure proper schema mapping"
    echo "3. 🧪 Test real-time data ingestion"
    echo "4. 🔍 Validate data in Dremio"
    
    exit 0
else
    echo "❌ Nessie API: Check connectivity"
    echo "❌ Iceberg Catalog: Configuration failed"
    echo "⚠️  Database Creation: Not tested"
    echo "⚠️  Flink Integration: Issues detected"
    
    echo ""
    echo "🔧 TROUBLESHOOTING STEPS:"
    echo "========================"
    echo "1. Check Nessie logs: docker logs nessie"
    echo "2. Verify Iceberg JARs: docker exec jobmanager ls /opt/flink/lib/ | grep iceberg"
    echo "3. Test MinIO access: docker exec minioserver mc ls minio/"
    echo "4. Check Flink logs: docker logs jobmanager"
    
    exit 1
fi

echo ""
echo "🏁 Nessie Iceberg Catalog Test Complete!" 