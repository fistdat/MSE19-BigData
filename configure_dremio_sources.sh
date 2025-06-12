#!/bin/bash

# ===== CONFIGURE DREMIO DATA SOURCES =====
# Automated configuration of MinIO and Nessie sources in Dremio

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
}

echo "🔧 DREMIO DATA SOURCES CONFIGURATION"
echo "===================================="

# ===== 1. CHECK PREREQUISITES =====
log "1. Checking Prerequisites..."

# Check if Dremio is accessible
if ! curl -s http://localhost:9047 > /dev/null; then
    error "Dremio is not accessible at http://localhost:9047"
    echo "Please ensure Dremio container is running: docker ps | grep dremio"
    exit 1
fi
success "Dremio UI is accessible"

# Check MinIO
if ! curl -s http://localhost:9000/minio/health/live > /dev/null; then
    error "MinIO is not accessible at http://localhost:9000"
    exit 1
fi
success "MinIO server is accessible"

# Check Nessie
if ! curl -s http://localhost:19120/api/v1/repositories > /dev/null; then
    error "Nessie catalog is not accessible at http://localhost:19120"
    exit 1
fi
success "Nessie catalog is accessible"

echo ""

# ===== 2. CREATE MINIO BUCKET IF NOT EXISTS =====
log "2. Setting up MinIO bucket..."

# Check if lakehouse bucket exists and create if needed
docker exec minioserver sh -c "
if [ ! -d /data/lakehouse ]; then
    mkdir -p /data/lakehouse
    echo 'Created lakehouse bucket'
else
    echo 'Lakehouse bucket already exists'
fi
"

echo "📁 MinIO bucket structure:"
docker exec minioserver ls -la /data/ 2>/dev/null || warning "Cannot list MinIO buckets"

echo ""

# ===== 3. DREMIO CONFIGURATION GUIDE =====
log "3. Dremio Configuration Instructions..."

echo ""
echo "🌐 DREMIO MANUAL CONFIGURATION STEPS:"
echo "====================================="
echo ""
echo "1. 🚀 Open Dremio UI:"
echo "   URL: http://localhost:9047"
echo "   Username: admin"
echo "   Password: admin123"
echo ""

echo "2. 🔗 Configure MinIO S3 Source:"
echo "   - Click '+ Add Source' button"
echo "   - Select 'Amazon S3'"
echo "   - Source Name: 'minio-s3' or 'datalake'"
echo "   - AWS Access Key: minioadmin"
echo "   - AWS Secret Key: minioadmin123"
echo "   - Endpoint: http://minioserver:9000"
echo "   - Enable 'Encrypt connection': OFF"
echo "   - Enable 'Path Style Access': ON"
echo "   - Root Path: /lakehouse"
echo "   - Click 'Save'"
echo ""

echo "3. 📚 Configure Nessie Catalog Source:"
echo "   - Click '+ Add Source' button"
echo "   - Select 'Nessie'"
echo "   - Source Name: 'nessie-catalog' or 'Nessie'"
echo "   - Endpoint URL: http://nessie:19120/api/v1"
echo "   - Authentication: None"
echo "   - Click 'Save'"
echo ""

echo "4. 🔄 Refresh Sources:"
echo "   - After adding sources, click refresh icon on each source"
echo "   - Wait for metadata discovery to complete"
echo ""

# ===== 4. VALIDATION STEPS =====
echo "5. 📊 Validation Steps:"
echo "   After configuration, run these SQL queries in Dremio:"
echo ""
echo "   -- Check available sources"
echo "   SHOW SCHEMAS;"
echo ""
echo "   -- List tables in Nessie catalog"
echo "   SHOW TABLES IN \"Nessie\";"
echo ""
echo "   -- Count records from lakehouse"
echo "   SELECT COUNT(*) FROM \"Nessie\".demographics;"
echo ""
echo "   -- Sample data validation"
echo "   SELECT * FROM \"Nessie\".demographics LIMIT 5;"
echo ""

# ===== 5. TROUBLESHOOTING =====
echo "🔧 TROUBLESHOOTING COMMON ISSUES:"
echo "================================="
echo ""
echo "❌ If MinIO source fails to connect:"
echo "   - Verify endpoint uses container name: http://minioserver:9000"
echo "   - Ensure 'Path Style Access' is enabled"
echo "   - Check credentials: minioadmin/minioadmin123"
echo ""

echo "❌ If Nessie source fails to connect:"
echo "   - Verify endpoint: http://nessie:19120/api/v1"
echo "   - Use container name 'nessie', not 'localhost'"
echo "   - Ensure Nessie container is running"
echo ""

echo "❌ If no tables appear:"
echo "   - Ensure Flink streaming jobs are running"
echo "   - Wait 2-3 minutes for data to be written to lakehouse"
echo "   - Check Flink job status: http://localhost:8081"
echo "   - Refresh data sources in Dremio"
echo ""

echo "❌ If data is not up to date:"
echo "   - Check CDC pipeline status"
echo "   - Verify Kafka messages: http://localhost:8082"
echo "   - Check Debezium connector: curl http://localhost:8083/connectors"
echo ""

# ===== 6. AUTO-CONFIGURATION ATTEMPT (API-based) =====
log "4. Attempting automatic configuration via Dremio API..."

# Note: Dremio API configuration is complex and may require authentication tokens
# For now, we'll provide the curl commands that could be used

echo ""
echo "🤖 AUTOMATED CONFIGURATION (Advanced):"
echo "======================================="
echo ""
echo "If you want to automate source creation via API, you can use:"
echo ""

# MinIO S3 source configuration JSON
cat << 'EOF'
# Create MinIO S3 source:
curl -X POST http://localhost:9047/api/v3/catalog \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <your-token>" \
  -d '{
    "entityType": "source",
    "name": "minio-s3",
    "type": "S3",
    "config": {
      "accessKey": "minioadmin",
      "accessSecret": "minioadmin123",
      "endpoint": "minioserver:9000",
      "secure": false,
      "pathStyleAccess": true,
      "rootPath": "/lakehouse"
    }
  }'

# Create Nessie source:
curl -X POST http://localhost:9047/api/v3/catalog \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <your-token>" \
  -d '{
    "entityType": "source", 
    "name": "nessie-catalog",
    "type": "NESSIE",
    "config": {
      "endpoint": "http://nessie:19120/api/v1",
      "authentication": "NONE"
    }
  }'
EOF

echo ""
warning "API configuration requires authentication token - use manual setup above"

echo ""

# ===== 7. VALIDATION SCRIPTS =====
log "5. Validation Scripts Available..."

echo ""
echo "📝 After configuring sources, run validation:"
echo ""
echo "1. Comprehensive pipeline validation:"
echo "   ./comprehensive_data_validation.sh"
echo ""
echo "2. Dremio-specific validation:"
echo "   Use queries from: dremio_validation_queries.sql"
echo ""
echo "3. Quick data consistency check:"
echo "   ./validate_data_consistency.sh"
echo ""

# ===== 8. MONITORING LINKS =====
echo "🔗 MONITORING & ACCESS LINKS:"
echo "============================="
echo "Dremio UI:         http://localhost:9047"
echo "MinIO Console:     http://localhost:9001 (minioadmin/minioadmin123)"
echo "Nessie API:        http://localhost:19120/api/v1"
echo "Flink Dashboard:   http://localhost:8081"
echo "Kafka UI:          http://localhost:8082"
echo ""

success "Configuration guide completed!"
echo ""
echo "🎯 NEXT STEPS:"
echo "1. Follow the manual configuration steps above"
echo "2. Run validation queries in Dremio"
echo "3. Execute comprehensive_data_validation.sh for full pipeline check"
echo "4. Monitor data freshness and consistency regularly"

echo "�� CONFIGURING DREMIO WITH MINIO SOURCE"
echo "======================================="

# Wait for Dremio to be ready
echo "📋 1. Checking Dremio status..."
until curl -s http://localhost:9047/apiv2/login > /dev/null 2>&1; do
    echo "   Waiting for Dremio to be ready..."
    sleep 5
done
echo "   ✅ Dremio is ready!"

# Get Dremio auth token (using default admin credentials)
echo ""
echo "🔐 2. Getting Dremio authentication token..."
AUTH_RESPONSE=$(curl -s -X POST http://localhost:9047/apiv2/login \
  -H "Content-Type: application/json" \
  -d '{"userName":"admin","password":"admin123"}')

if [ $? -eq 0 ]; then
    TOKEN=$(echo $AUTH_RESPONSE | python3 -c "import sys, json; print(json.load(sys.stdin)['token'])" 2>/dev/null)
    if [ -n "$TOKEN" ]; then
        echo "   ✅ Authentication successful!"
    else
        echo "   ❌ Failed to extract token. Response: $AUTH_RESPONSE"
        echo "   Trying with default setup..."
        TOKEN="dummy_token"
    fi
else
    echo "   ❌ Authentication failed. Continuing with manual setup instructions..."
    TOKEN="dummy_token"
fi

echo ""
echo "📦 3. MinIO Source Configuration for Dremio:"
echo "   Source Name: minio_warehouse"
echo "   Source Type: Amazon S3"
echo "   Configuration:"
echo "   - AWS Access Key: DKZjmhls7nwxBN4GJfXC"
echo "   - AWS Secret Key: kNuAZodphLEGKHv5EmbyiDt1v5eT0yVErjVFyg0t"
echo "   - AWS Region: us-east-1"
echo "   - Endpoint: http://minioserver:9000"
echo "   - Path Style Access: true"
echo "   - Secure Connection: false"

echo ""
echo "🔍 4. Test Data Available in MinIO:"
docker exec minioserver mc ls -r minio/warehouse/

echo ""
echo "📋 5. MANUAL DREMIO SETUP INSTRUCTIONS:"
echo "   1. Open Dremio UI: http://localhost:9047"
echo "   2. Login with admin/admin123"
echo "   3. Go to 'Sources' → 'Add Source'"
echo "   4. Select 'Amazon S3'"
echo "   5. Configure with the settings above"
echo "   6. Test connection and save"
echo "   7. Browse to warehouse/test_data/test_data.json"
echo "   8. Preview and create dataset"

echo ""
echo "🎯 6. Expected Test Results:"
echo "   - Should see test_data.json file"
echo "   - Should be able to preview JSON content"
echo "   - Should show demographics data structure"

echo ""
echo "✅ Configuration complete! Please follow manual setup instructions." 