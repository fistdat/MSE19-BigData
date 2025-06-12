#!/bin/bash

# ===== COMPREHENSIVE PIPELINE MONITORING =====
# Monitor all components of the data lakehouse pipeline

echo "🔍 COMPREHENSIVE PIPELINE MONITORING & DEBUG"
echo "============================================="

echo ""
echo "📊 1. PostgreSQL Status:"
docker exec postgres psql -U admin -d demographics -c "SELECT COUNT(*) as total_records FROM demographics;" 2>/dev/null || echo "❌ PostgreSQL connection failed"

echo ""
echo "🔄 2. Debezium CDC Status:"
curl -s http://localhost:8083/connectors/demographics-connector/status | jq '.connector.state' 2>/dev/null || echo "❌ Debezium not accessible"

echo ""
echo "📨 3. Kafka Topic Messages:"
docker exec kafka /opt/kafka/bin/kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic demographics_server.public.demographics --from-beginning --max-messages 3 --timeout-ms 5000 2>/dev/null || echo "❌ Kafka topic check failed"

echo ""
echo "⚡ 4. Flink Jobs Status:"
curl -s http://localhost:8081/jobs | jq '.jobs[] | {id: .id, name: .name, status: .status}' 2>/dev/null || echo "❌ No Flink jobs found"

echo ""
echo "🗄️ 5. Nessie Catalog Status:"
curl -s http://localhost:19120/api/v1/trees/tree/main | jq '.name' 2>/dev/null || echo "❌ Nessie not accessible"

echo ""
echo "📦 6. MinIO Warehouse Structure:"
docker exec minioserver mc ls -r minio/warehouse/ | head -20

echo ""
echo "🔍 7. MinIO Data Files Search:"
echo "Searching for data files (.parquet, .avro, .orc):"
docker exec minioserver mc ls -r minio/warehouse/ | grep -E "\\.parquet|\\.avro|\\.orc" | head -10

echo ""
echo "📋 8. Flink TaskManager Logs (last 10 lines):"
docker logs taskmanager --tail 10

echo ""
echo "📋 9. Flink JobManager Logs (last 10 lines):"
docker logs jobmanager --tail 10

echo ""
echo "🔧 10. Test Simple Flink Job:"
echo "Testing if Flink can execute simple jobs..."
docker exec jobmanager bash -c "echo \"SET 'execution.checkpointing.interval' = '30sec'; CREATE TABLE test_simple (id INT, name STRING) WITH ('connector' = 'datagen', 'rows-per-second' = '1'); SELECT COUNT(*) FROM test_simple;\" | timeout 30s /opt/flink/bin/sql-client.sh" 2>/dev/null || echo "❌ Simple Flink job test failed"

echo ""
echo "✅ Monitoring Complete!"
echo "======================"

echo "📊 BIGDATA PIPELINE MONITORING DASHBOARD"
echo "========================================"
echo "Monitoring time: $(date)"
echo ""

# Function to check service health
check_service() {
    local service_name=$1
    local url=$2
    local timeout=${3:-5}
    
    if timeout $timeout curl -s "$url" > /dev/null 2>&1; then
        echo "✅ $service_name - HEALTHY"
        return 0
    else
        echo "❌ $service_name - DOWN"
        return 1
    fi
}

# Function to get container status
get_container_status() {
    local container=$1
    local status=$(docker ps --filter "name=$container" --format "{{.Status}}" 2>/dev/null)
    if [ -n "$status" ]; then
        echo "✅ $container: $status"
    else
        echo "❌ $container: NOT RUNNING"
    fi
}

echo "🐳 CONTAINER STATUS:"
echo "===================="
get_container_status "postgres"
get_container_status "kafka" 
get_container_status "zookeeper"
get_container_status "debezium"
get_container_status "jobmanager"
get_container_status "taskmanager"
get_container_status "minioserver"
get_container_status "nessie"
get_container_status "dremio"

echo ""
echo "🌐 SERVICE HEALTH CHECKS:"
echo "========================="
check_service "PostgreSQL" "localhost:5432" 3 &
check_service "Kafka" "localhost:9092" 3 &
check_service "Debezium" "http://localhost:8083" 5 &
check_service "Flink JobManager" "http://localhost:8081" 5 &
check_service "MinIO" "http://localhost:9000" 3 &
check_service "Nessie" "http://localhost:19120" 5 &
check_service "Dremio" "http://localhost:9047" 5 &

# Wait for all background checks
wait

echo ""
echo "📊 DATA CONSISTENCY STATUS:"
echo "==========================="

# PostgreSQL data count
PG_COUNT=$(docker exec postgres psql -U admin -d bigdata_db -t -c "SELECT COUNT(*) FROM demographics;" 2>/dev/null | tr -d ' \n' || echo "ERROR")
echo "📊 PostgreSQL records: $PG_COUNT"

# Debezium connector status
DEBEZIUM_STATUS=$(curl -s http://localhost:8083/connectors/postgres-demographics-connector/status 2>/dev/null | python3 -c "import sys, json; data=json.load(sys.stdin); print(data['connector']['state'])" 2>/dev/null || echo "ERROR")
echo "🔄 Debezium CDC: $DEBEZIUM_STATUS"

# Kafka topics
KAFKA_TOPIC_COUNT=$(timeout 3s docker exec kafka /kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --list 2>/dev/null | grep demographics | wc -l || echo "0")
echo "📮 Kafka CDC topics: $KAFKA_TOPIC_COUNT"

# Flink jobs
FLINK_JOBS=$(curl -s http://localhost:8081/jobs 2>/dev/null | python3 -c "import sys, json; data=json.load(sys.stdin); print(len(data['jobs']))" 2>/dev/null || echo "ERROR")
echo "⚡ Flink active jobs: $FLINK_JOBS"

# MinIO lakehouse data
MINIO_FILES=$(docker exec minioserver mc ls minio/lakehouse/demographics/ 2>/dev/null | wc -l || echo "0")
echo "🗂️ Lakehouse files: $MINIO_FILES"

echo ""
echo "🎯 DATA FLOW PIPELINE:"
echo "======================"
echo "PostgreSQL ($PG_COUNT records) → Debezium ($DEBEZIUM_STATUS) → Kafka ($KAFKA_TOPIC_COUNT topics) → Flink ($FLINK_JOBS jobs) → MinIO ($MINIO_FILES files)"

echo ""
echo "⚠️ ISSUES DETECTED:"
echo "=================="

# Check for issues
ISSUES=0

if [ "$PG_COUNT" = "ERROR" ] || [ "$PG_COUNT" = "0" ]; then
    echo "❌ No data in PostgreSQL source"
    ((ISSUES++))
fi

if [ "$DEBEZIUM_STATUS" != "RUNNING" ]; then
    echo "❌ Debezium CDC not running properly"
    ((ISSUES++))
fi

if [ "$FLINK_JOBS" = "ERROR" ] || [ "$FLINK_JOBS" = "0" ]; then
    echo "❌ No Flink streaming jobs active"
    ((ISSUES++))
fi

if [ "$MINIO_FILES" = "0" ]; then
    echo "❌ No data files in lakehouse"
    ((ISSUES++))
fi

if [ $ISSUES -eq 0 ]; then
    echo "✅ No critical issues detected!"
else
    echo "🚨 $ISSUES issue(s) found above"
fi

echo ""
echo "📊 PERFORMANCE METRICS:"
echo "======================="
echo "🐘 PostgreSQL:"
echo "   • Connection test: $(timeout 3s docker exec postgres psql -U admin -d bigdata_db -c 'SELECT 1;' 2>/dev/null && echo 'OK' || echo 'FAIL')"
echo "   • Latest record: $(docker exec postgres psql -U admin -d bigdata_db -t -c "SELECT MAX(created_at) FROM demographics;" 2>/dev/null | tr -d ' \n' || echo 'ERROR')"

echo ""
echo "📮 Kafka:"
echo "   • Topics available: $(timeout 3s docker exec kafka /kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --list 2>/dev/null | wc -l || echo 'ERROR')"

echo ""
echo "⚡ Flink:"
echo "   • JobManager uptime: $(curl -s http://localhost:8081/overview 2>/dev/null | python3 -c "import sys, json; print(json.load(sys.stdin).get('flink-commit', 'Unknown'))" 2>/dev/null || echo 'ERROR')"

echo ""
echo "🗂️ MinIO:"
echo "   • Bucket status: $(docker exec minioserver mc ls minio/lakehouse 2>/dev/null && echo 'OK' || echo 'ERROR')"

echo ""
echo "🌐 WEB INTERFACES:"
echo "=================="
echo "• Dremio UI: http://localhost:9047"
echo "• Flink UI: http://localhost:8081"
echo "• MinIO Console: http://localhost:9001"
echo "• Kafka UI: http://localhost:8082"
echo "• pgAdmin: http://localhost:5050"

echo ""
echo "🔄 NEXT ACTIONS:"
echo "================"
if [ "$FLINK_JOBS" = "0" ]; then
    echo "1. ⚡ Start Flink CDC streaming: ./submit_postgres_cdc_job.sh"
fi
if [ "$MINIO_FILES" = "0" ]; then
    echo "2. 📂 Check data in lakehouse: Access MinIO Console"
fi
echo "3. 🎯 Test queries in Dremio UI"
echo "4. 📊 Re-run monitoring: ./monitor_pipeline.sh"

echo ""
echo "📋 MONITORING COMPLETE - $(date)" 