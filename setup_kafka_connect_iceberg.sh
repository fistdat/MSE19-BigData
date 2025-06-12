#!/bin/bash

# Setup Kafka Connect Iceberg Sink Connector
# Following Dremio CDC best practices
# ==========================================

set -e

echo "🔧 SETTING UP KAFKA CONNECT ICEBERG SINK CONNECTOR"
echo "=================================================="

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
}

# 1. Check if Kafka Connect is running
log "1. Checking Kafka Connect status..."
if curl -s http://localhost:8083/connectors > /dev/null; then
    echo "✅ Kafka Connect is accessible"
else
    error "Kafka Connect not accessible at http://localhost:8083"
    exit 1
fi

# 2. Create Iceberg Sink Connector configuration
log "2. Creating Iceberg Sink Connector configuration..."

cat > iceberg_sink_config.json << 'EOF'
{
  "name": "iceberg-demographics-sink",
  "config": {
    "connector.class": "org.apache.iceberg.connect.IcebergSinkConnector",
    "tasks.max": "1",
    "topics": "demographics_server.public.demographics",
    
    "iceberg.catalog.type": "nessie",
    "iceberg.catalog.uri": "http://nessie:19120/api/v1",
    "iceberg.catalog.ref": "main",
    "iceberg.catalog.warehouse": "s3://lakehouse",
    
    "iceberg.catalog.s3.endpoint": "http://minioserver:9000",
    "iceberg.catalog.s3.access-key-id": "minioadmin", 
    "iceberg.catalog.s3.secret-access-key": "minioadmin123",
    "iceberg.catalog.s3.path-style-access": "true",
    
    "iceberg.table.namespace": "demographics_db",
    "iceberg.table.name": "demographics",
    "iceberg.table.auto-create": "true",
    
    "upsert": "true",
    "upsert.keep-deletes": "true",
    
    "key.converter": "org.apache.kafka.connect.json.JsonConverter",
    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
    "key.converter.schemas.enable": "false",
    "value.converter.schemas.enable": "false"
  }
}
EOF

echo "✅ Configuration created: iceberg_sink_config.json"

# 3. Submit connector configuration
log "3. Submitting Iceberg Sink Connector..."

RESPONSE=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  --data @iceberg_sink_config.json \
  http://localhost:8083/connectors)

if echo "$RESPONSE" | grep -q "iceberg-demographics-sink"; then
    echo "✅ Iceberg Sink Connector created successfully"
else
    warning "Connector creation response:"
    echo "$RESPONSE"
    echo ""
    warning "This might be expected if Iceberg connector is not available"
    echo "💡 Alternative: Use Flink with filesystem connector to Parquet format"
fi

# 4. Check connector status
log "4. Checking connector status..."
sleep 2

STATUS=$(curl -s http://localhost:8083/connectors/iceberg-demographics-sink/status 2>/dev/null)
if [ $? -eq 0 ]; then
    echo "📊 Connector status:"
    echo "$STATUS" | python3 -m json.tool 2>/dev/null || echo "$STATUS"
else
    warning "Could not get connector status - likely Iceberg connector not available"
fi

echo ""
echo "📋 ALTERNATIVE APPROACH - Flink Filesystem Connector:"
echo "===================================================="
echo ""
echo "If Iceberg connector is not available, use Flink with filesystem connector:"
echo ""
echo "1. Stream Kafka CDC → Parquet files in MinIO"
echo "2. Configure Dremio to read Parquet files directly"
echo "3. Use Dremio's incremental reflections for optimization"
echo ""
echo "Script: ./setup_flink_parquet_streaming.sh"
echo ""

log "5. Monitoring URLs:"
echo "==================="
echo "Kafka Connect API: http://localhost:8083/connectors"
echo "Kafka UI:          http://localhost:8082" 
echo "MinIO Console:     http://localhost:9001"
echo "Nessie API:        http://localhost:19120/api/v1"
echo ""

echo "✅ Setup completed!" 