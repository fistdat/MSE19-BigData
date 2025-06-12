#!/bin/bash

# Rebuild Flink Containers với Apache Iceberg Support
# Following Dremio CDC best practices
# ====================================================

set -e

echo "🔧 REBUILDING FLINK CONTAINERS WITH ICEBERG SUPPORT"
echo "=================================================="

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
}

# 1. Stop current Flink containers
log "1. Stopping current Flink containers..."
docker-compose stop jobmanager taskmanager 2>/dev/null || true
docker-compose rm -f jobmanager taskmanager 2>/dev/null || true

# 2. Remove old Flink images
log "2. Removing old Flink images..."
docker rmi project04_jobmanager project04_taskmanager 2>/dev/null || true

# 3. Build new Flink containers with Iceberg
log "3. Building enhanced Flink containers with Iceberg JARs..."
info "This may take 5-10 minutes to download all dependencies..."

docker-compose build --no-cache jobmanager taskmanager

if [ $? -eq 0 ]; then
    echo "✅ Flink containers built successfully with Iceberg support"
else
    error "Failed to build Flink containers"
    exit 1
fi

# 4. Start new containers
log "4. Starting enhanced Flink containers..."
docker-compose up -d jobmanager taskmanager

# Wait for services to start
sleep 15

# 5. Verify Iceberg JARs are loaded
log "5. Verifying Iceberg JARs in containers..."

echo "📦 JobManager JARs:"
docker exec jobmanager ls -la /opt/flink/lib/ | grep -E "(iceberg|nessie)" || echo "No Iceberg/Nessie JARs found"

echo ""
echo "📦 TaskManager JARs:"
docker exec taskmanager ls -la /opt/flink/lib/ | grep -E "(iceberg|nessie)" || echo "No Iceberg/Nessie JARs found"

# 6. Check Flink Web UI
log "6. Checking Flink Web UI accessibility..."
if curl -s http://localhost:8081 > /dev/null; then
    echo "✅ Flink Web UI accessible at http://localhost:8081"
else
    warning "Flink Web UI not accessible yet, may need more time to start"
fi

# 7. Test Iceberg catalog creation
log "7. Testing Iceberg catalog availability..."

# Create test SQL file
cat > test_iceberg_catalog.sql << 'EOF'
-- Test Iceberg Catalog Creation
CREATE CATALOG iceberg_test WITH (
    'type' = 'iceberg',
    'catalog-type' = 'nessie',
    'uri' = 'http://nessie:19120/api/v1',
    'ref' = 'main',
    'warehouse' = 's3://lakehouse'
);

SHOW CATALOGS;
EOF

# Copy and test
docker cp test_iceberg_catalog.sql jobmanager:/opt/flink/conf/

info "Testing Iceberg catalog creation..."
TEST_RESULT=$(docker exec jobmanager /opt/flink/bin/sql-client.sh -f /opt/flink/conf/test_iceberg_catalog.sql 2>&1)

if echo "$TEST_RESULT" | grep -q "iceberg_test"; then
    echo "✅ Iceberg catalog creation successful!"
else
    warning "Iceberg catalog test failed, but containers are running"
    echo "Test output:"
    echo "$TEST_RESULT"
fi

# Cleanup test file
rm -f test_iceberg_catalog.sql
docker exec jobmanager rm -f /opt/flink/conf/test_iceberg_catalog.sql

echo ""
echo "🎯 NEXT STEPS:"
echo "============="
echo "1. ✅ Flink containers rebuilt with Iceberg support"
echo "2. 🔄 Next: Create proper Iceberg tables with Nessie catalog"
echo "3. 🔄 Next: Configure Dremio Iceberg sources"
echo "4. 🔄 Next: Setup end-to-end CDC pipeline"
echo ""

echo "🔗 MONITORING URLS:"
echo "=================="
echo "Flink Dashboard:   http://localhost:8081"
echo "Nessie API:        http://localhost:19120/api/v1"
echo "MinIO Console:     http://localhost:9001"
echo "Dremio UI:         http://localhost:9047"
echo ""

log "✅ Flink Iceberg rebuild completed!" 