#!/bin/bash

# ===== COMPREHENSIVE DATA CONSISTENCY VALIDATION =====
# Validates data consistency across the entire pipeline:
# PostgreSQL -> Debezium -> Kafka -> Flink -> Iceberg/MinIO -> Dremio

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
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

echo "🔍 COMPREHENSIVE DATA CONSISTENCY VALIDATION"
echo "============================================="
echo ""

# Global variables for data consistency
PG_COUNT=0
KAFKA_MESSAGES=0
FLINK_JOBS_RUNNING=0
LAKEHOUSE_FILES=0
DREMIO_ACCESSIBLE=false

# ===== 1. POSTGRESQL SOURCE VALIDATION =====
log "1. Validating PostgreSQL Source Data..."

# Check PostgreSQL connection
if docker exec postgres pg_isready -U admin -d bigdata_db > /dev/null 2>&1; then
    success "PostgreSQL is accessible"
    
    # Get record count
    PG_COUNT=$(docker exec postgres psql -U admin -d bigdata_db -t -c "SELECT COUNT(*) FROM demographics;" 2>/dev/null | tr -d ' \n')
    if [[ "$PG_COUNT" =~ ^[0-9]+$ ]] && [ "$PG_COUNT" -gt 0 ]; then
        success "PostgreSQL records: $PG_COUNT"
        
        # Show sample data
        echo "📊 Sample PostgreSQL data:"
        docker exec postgres psql -U admin -d bigdata_db -c "
        SELECT 
            id, city, population, 
            TO_CHAR(created_at, 'YYYY-MM-DD HH24:MI:SS') as created_at
        FROM demographics 
        ORDER BY created_at DESC 
        LIMIT 3;
        " 2>/dev/null
        
        # Show data distribution
        echo "📈 Data distribution by city:"
        docker exec postgres psql -U admin -d bigdata_db -c "
        SELECT 
            city, 
            population,
            created_at
        FROM demographics 
        ORDER BY population DESC 
        LIMIT 5;
        " 2>/dev/null
    else
        error "No data found in PostgreSQL demographics table"
        PG_COUNT=0
    fi
else
    error "Cannot connect to PostgreSQL"
    exit 1
fi

echo ""

# ===== 2. KAFKA CDC STREAM VALIDATION =====
log "2. Validating Kafka CDC Stream..."

# Check Kafka topics
TOPICS=$(docker exec kafka kafka-topics --bootstrap-server localhost:9092 --list 2>/dev/null)
if echo "$TOPICS" | grep -q "demographics"; then
    success "Kafka CDC topic found"
    
    # Count messages in topic using Kafka UI API
    echo "📮 Checking CDC messages..."
    KAFKA_OFFSET=$(curl -s http://localhost:8082/api/clusters/local/topics/demographics_server.public.demographics | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    partitions = data.get('partitions', [])
    if partitions:
        print(partitions[0].get('offsetMax', 0))
    else:
        print(0)
except:
    print(0)
" 2>/dev/null)
    
    KAFKA_MESSAGES=${KAFKA_OFFSET:-0}
    if [[ "$KAFKA_MESSAGES" =~ ^[0-9]+$ ]] && [ "$KAFKA_MESSAGES" -gt 0 ]; then
        success "Kafka CDC messages: $KAFKA_MESSAGES"
    else
        warning "No CDC messages found in Kafka topic"
        KAFKA_MESSAGES=0
    fi
    
    # Show CDC message info using Kafka UI
    echo "📄 CDC messages info:"
    echo "   Topic: demographics_server.public.demographics"
    echo "   Total messages: $KAFKA_MESSAGES"
    echo "   Latest offset: $KAFKA_OFFSET"
else
    error "Kafka CDC topic not found"
    echo "Available topics:"
    echo "$TOPICS"
fi

echo ""

# ===== 3. FLINK STREAMING JOBS VALIDATION =====
log "3. Validating Flink Streaming Jobs..."

# Check Flink JobManager accessibility
if curl -s http://localhost:8081/overview > /dev/null 2>&1; then
    success "Flink JobManager accessible"
    
    # Get running jobs
    FLINK_JOBS=$(curl -s http://localhost:8081/jobs 2>/dev/null)
    RUNNING_JOBS=$(echo "$FLINK_JOBS" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    running = [job for job in data.get('jobs', []) if job.get('status') == 'RUNNING']
    print(len(running))
except:
    print(0)
" 2>/dev/null)
    
    if [ "$RUNNING_JOBS" -gt 0 ]; then
        success "Flink jobs running: $RUNNING_JOBS"
        FLINK_JOBS_RUNNING=$RUNNING_JOBS
        
        echo "⚡ Active Flink jobs:"
        echo "$FLINK_JOBS" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    for job in data.get('jobs', []):
        if job.get('status') == 'RUNNING':
            print(f\"   Job ID: {job.get('id', 'unknown')[:8]}... Status: {job.get('status')}\")
except:
    pass
" 2>/dev/null
    else
        warning "No Flink jobs running"
        echo "💡 Run: ./submit_flink_lakehouse_job.sh to start streaming"
        FLINK_JOBS_RUNNING=0
    fi
else
    error "Cannot access Flink JobManager at http://localhost:8081"
fi

echo ""

# ===== 4. MINIO LAKEHOUSE VALIDATION =====
log "4. Validating MinIO Lakehouse Storage..."

# Check MinIO accessibility
if curl -s http://localhost:9000/minio/health/live > /dev/null 2>&1; then
    success "MinIO server accessible"
    
    # Try to list lakehouse bucket contents
    echo "🗂️ Checking lakehouse bucket contents..."
    
    # Use mc (MinIO client) if available in container
    LAKEHOUSE_LISTING=$(docker exec minioserver ls -la /data/lakehouse 2>/dev/null || echo "")
    if [ -n "$LAKEHOUSE_LISTING" ]; then
        LAKEHOUSE_FILES=$(echo "$LAKEHOUSE_LISTING" | grep -c "^-" 2>/dev/null || echo "0")
        if [ "$LAKEHOUSE_FILES" -gt 0 ]; then
            success "Lakehouse files found: $LAKEHOUSE_FILES"
            echo "📁 Lakehouse directory structure:"
            echo "$LAKEHOUSE_LISTING" | head -10
        else
            warning "No files found in lakehouse bucket"
            echo "💡 Directory structure:"
            echo "$LAKEHOUSE_LISTING"
        fi
    else
        warning "Cannot access lakehouse bucket or bucket is empty"
        echo "💡 Access MinIO Console: http://localhost:9001 (minioadmin/minioadmin123)"
    fi
else
    error "Cannot access MinIO server"
fi

echo ""

# ===== 5. NESSIE CATALOG VALIDATION =====
log "5. Validating Nessie Catalog..."

if curl -s http://localhost:19120/api/v1/repositories > /dev/null 2>&1; then
    success "Nessie catalog accessible"
    
    # Try to get catalog information
    echo "📚 Nessie catalog info:"
    curl -s http://localhost:19120/api/v1/repositories | python3 -m json.tool 2>/dev/null | head -10 || echo "   Failed to parse catalog response"
    
    # Try to list namespaces
    echo "📂 Available namespaces:"
    curl -s http://localhost:19120/api/v1/trees/tree/entries | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    entries = data.get('entries', [])
    if entries:
        for entry in entries[:5]:
            print(f\"   {entry.get('name', {}).get('elements', ['unknown'])[0]}\")
    else:
        print('   No entries found')
except:
    print('   Failed to parse entries')
" 2>/dev/null
else
    error "Cannot access Nessie catalog"
fi

echo ""

# ===== 6. DREMIO QUERY ENGINE VALIDATION =====
log "6. Validating Dremio Query Engine..."

if curl -s http://localhost:9047 > /dev/null 2>&1; then
    success "Dremio UI accessible"
    DREMIO_ACCESSIBLE=true
    
    echo "🌐 Dremio access information:"
    echo "   URL: http://localhost:9047"
    echo "   Default credentials: admin/admin123"
    echo ""
    echo "🔍 Manual validation steps for Dremio:"
    echo "   1. Login to Dremio UI"
    echo "   2. Check if data sources are configured:"
    echo "      • MinIO S3 source"
    echo "      • Nessie catalog source"
    echo "   3. Run test queries to verify data accessibility"
else
    error "Cannot access Dremio UI"
fi

echo ""

# ===== 7. DATA CONSISTENCY ANALYSIS =====
log "7. Data Consistency Analysis..."
echo ""

echo "📊 PIPELINE DATA SUMMARY:"
echo "========================="
echo "PostgreSQL Source:    $PG_COUNT records"
echo "Kafka CDC Messages:   $KAFKA_MESSAGES messages"
echo "Flink Jobs Running:   $FLINK_JOBS_RUNNING jobs"
echo "Lakehouse Files:      $LAKEHOUSE_FILES files"
echo "Dremio Accessible:    $DREMIO_ACCESSIBLE"

echo ""
echo "🎯 CONSISTENCY ANALYSIS:"
echo "========================"

# Check pipeline health
PIPELINE_HEALTHY=true

if [ "$PG_COUNT" -eq 0 ]; then
    error "No source data in PostgreSQL"
    PIPELINE_HEALTHY=false
fi

if [ "$KAFKA_MESSAGES" -eq 0 ] && [ "$PG_COUNT" -gt 0 ]; then
    error "Data exists in PostgreSQL but no CDC messages in Kafka"
    echo "💡 Check Debezium connector configuration"
    PIPELINE_HEALTHY=false
fi

if [ "$FLINK_JOBS_RUNNING" -eq 0 ]; then
    warning "No Flink streaming jobs running"
    echo "💡 Data won't flow to lakehouse without Flink jobs"
    if [ "$KAFKA_MESSAGES" -gt 0 ]; then
        echo "💡 Run: ./submit_flink_lakehouse_job.sh"
    fi
    PIPELINE_HEALTHY=false
fi

if [ "$LAKEHOUSE_FILES" -eq 0 ] && [ "$FLINK_JOBS_RUNNING" -gt 0 ]; then
    warning "Flink jobs running but no data in lakehouse yet"
    echo "💡 Wait 2-3 minutes for initial data streaming"
fi

if [ "$DREMIO_ACCESSIBLE" = false ]; then
    error "Dremio not accessible - cannot validate end-to-end data"
    PIPELINE_HEALTHY=false
fi

echo ""

# ===== 8. RECOMMENDATIONS =====
log "8. Recommendations..."

if [ "$PIPELINE_HEALTHY" = true ]; then
    success "PIPELINE APPEARS HEALTHY!"
    echo ""
    echo "🎯 Next steps for validation:"
    echo "1. Login to Dremio UI: http://localhost:9047"
    echo "2. Configure data sources if not already done:"
    echo "   • MinIO S3: http://minioserver:9000"
    echo "   • Nessie: http://nessie:19120/api/v1"
    echo "3. Run these test queries:"
    echo ""
    echo "   -- List available schemas"
    echo "   SHOW SCHEMAS;"
    echo ""
    echo "   -- Query data from lakehouse"
    echo "   SELECT * FROM \"nessie-catalog\".demographics LIMIT 10;"
    echo ""
    echo "   -- Verify record count matches PostgreSQL"
    echo "   SELECT COUNT(*) FROM \"nessie-catalog\".demographics;"
else
    error "PIPELINE ISSUES DETECTED!"
    echo ""
    echo "🔧 Required actions:"
    
    if [ "$PG_COUNT" -eq 0 ]; then
        echo "1. Load data into PostgreSQL demographics table"
    fi
    
    if [ "$KAFKA_MESSAGES" -eq 0 ]; then
        echo "2. Check Debezium connector: curl http://localhost:8083/connectors"
        echo "3. Restart CDC if needed: ./deploy_debezium_flink.sh"
    fi
    
    if [ "$FLINK_JOBS_RUNNING" -eq 0 ]; then
        echo "4. Start Flink streaming: ./submit_flink_lakehouse_job.sh"
    fi
    
    if [ "$DREMIO_ACCESSIBLE" = false ]; then
        echo "5. Check Dremio container: docker logs dremio"
    fi
fi

echo ""
echo "🔗 Monitoring URLs:"
echo "==================="
echo "Flink Dashboard:   http://localhost:8081"
echo "Kafka UI:          http://localhost:8082"
echo "MinIO Console:     http://localhost:9001"
echo "Dremio UI:         http://localhost:9047"
echo "Nessie API:        http://localhost:19120/api/v1"

echo ""
success "Validation completed!"

# Cleanup temp files
rm -f /tmp/kafka_count.txt 