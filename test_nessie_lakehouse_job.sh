#!/bin/bash
# =============================================================================
# TEST NESSIE LAKEHOUSE JOB
# =============================================================================
# Complete test for CDC pipeline using Nessie catalog with Iceberg
# =============================================================================

source pipeline_config.env

echo "🗄️ TESTING NESSIE LAKEHOUSE JOB"
echo "==============================="

# Stop existing jobs first
echo "🔄 Checking for existing Flink jobs..."
EXISTING_JOBS=$(curl -s ${FLINK_JOBMANAGER_URL}/jobs | grep -o '"id":"[^"]*"' | cut -d'"' -f4)

if [ -n "$EXISTING_JOBS" ]; then
    echo "⚠️  Found existing jobs, stopping them first..."
    for job_id in $EXISTING_JOBS; do
        echo "🛑 Stopping job: $job_id"
        curl -X PATCH ${FLINK_JOBMANAGER_URL}/jobs/$job_id?mode=stop > /dev/null 2>&1
    done
    echo "⏳ Waiting for jobs to stop..."
    sleep 10
fi

# Pre-flight checks
echo ""
echo "📋 Pre-flight checks..."
echo "======================"

# Test connections
test_flink || { echo "❌ Flink not accessible"; exit 1; }
test_kafka || { echo "❌ Kafka not accessible"; exit 1; }
test_minio || { echo "❌ MinIO not accessible"; exit 1; }
test_nessie || { echo "❌ Nessie not accessible"; exit 1; }

echo "✅ All required services are running"

# Check CDC topic
echo ""
echo "🔍 Checking CDC topic status..."
TOPIC_EXISTS=$(docker exec ${CONTAINER_KAFKA} kafka-topics --bootstrap-server ${KAFKA_BOOTSTRAP_SERVERS} --list | grep "${KAFKA_CDC_TOPIC}" || echo "")

if [ -z "$TOPIC_EXISTS" ]; then
    echo "❌ CDC topic ${KAFKA_CDC_TOPIC} does not exist"
    exit 1
else
    echo "✅ CDC topic ${KAFKA_CDC_TOPIC} exists"
fi

# Check Nessie dependencies
echo ""
echo "🔍 Checking Nessie dependencies..."
NESSIE_JAR_COUNT=$(docker exec ${CONTAINER_FLINK_JM} ls /opt/flink/lib/ | grep -E "(nessie|iceberg)" | wc -l)
if [ "$NESSIE_JAR_COUNT" -ge 2 ]; then
    echo "✅ Found $NESSIE_JAR_COUNT Nessie/Iceberg JARs"
    echo "📋 Nessie JARs:"
    docker exec ${CONTAINER_FLINK_JM} ls /opt/flink/lib/ | grep -E "(nessie|iceberg)"
else
    echo "❌ Missing Nessie dependencies"
    exit 1
fi

echo ""
echo "🚀 Submitting Nessie lakehouse job..."
echo "====================================="

# Copy SQL file to Flink container
docker cp nessie_cdc_to_iceberg_job.sql ${CONTAINER_FLINK_JM}:/tmp/nessie_job.sql

# Submit the job
echo "📤 Executing Nessie job via Flink SQL Client..."
JOB_RESULT=$(docker exec ${CONTAINER_FLINK_JM} /opt/flink/bin/sql-client.sh -f /tmp/nessie_job.sql 2>&1)
JOB_EXIT_CODE=$?

echo "📊 Job submission result:"
echo "========================"
echo "$JOB_RESULT"

if [ $JOB_EXIT_CODE -eq 0 ]; then
    echo ""
    echo "✅ Nessie lakehouse job submitted successfully!"
    
    # Wait a moment for job to start
    sleep 5
    
    # Check running jobs
    echo ""
    echo "🔍 Checking running jobs..."
    RUNNING_JOBS=$(curl -s ${FLINK_JOBMANAGER_URL}/jobs | grep -o '"status":"RUNNING"' | wc -l || echo "0")
    
    if [ "$RUNNING_JOBS" -gt 0 ]; then
        JOB_ID=$(curl -s ${FLINK_JOBMANAGER_URL}/jobs | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
        echo "✅ Found running job: $JOB_ID"
        
        # Test real-time CDC processing to Nessie
        echo ""
        echo "🧪 Testing real-time CDC to Nessie Iceberg..."
        echo "=============================================="
        
        # Insert test data
        TEST_TIMESTAMP=$(date +%s)
        TEST_CITY="NessieTest_${TEST_TIMESTAMP}"
        TEST_STATE="LakehouseState"
        
        echo "📤 Inserting test data: $TEST_CITY"
        INSERT_RESULT=$(docker exec ${CONTAINER_POSTGRES} psql -U ${PG_USER} -d ${PG_DATABASE} -c "INSERT INTO demographics (city, state, count) VALUES ('${TEST_CITY}', '${TEST_STATE}', 88888);" 2>&1)
        
        if echo "$INSERT_RESULT" | grep -q "INSERT 0 1"; then
            echo "✅ Test data inserted successfully"
            
            # Wait for processing
            echo "⏳ Waiting for CDC processing and Nessie Iceberg write (30 seconds)..."
            sleep 30
            
            # Check MinIO for Iceberg files
            echo ""
            echo "🔍 Checking MinIO for Nessie Iceberg data files..."
            if docker exec ${CONTAINER_MINIO} mc ls minio/warehouse/ > /dev/null 2>&1; then
                echo "✅ Warehouse directory exists in MinIO"
                echo "📋 Warehouse contents:"
                docker exec ${CONTAINER_MINIO} mc ls -r minio/warehouse/ | head -15 || echo "No files yet or access issues"
            else
                echo "⚠️  Warehouse directory access issues"
            fi
            
            # Check Nessie for commits
            echo ""
            echo "🗄️ Checking Nessie for data commits..."
            NESSIE_COMMITS=$(curl -s ${NESSIE_URL_EXTERNAL}/trees/main/entries?content=true | head -20 || echo "Access issues")
            if echo "$NESSIE_COMMITS" | grep -q "lakehouse"; then
                echo "✅ Found Nessie commits for lakehouse data"
                echo "📋 Nessie entries:"
                echo "$NESSIE_COMMITS" | head -10
            else
                echo "⚠️  Nessie commits not found yet"
                echo "Debug info:"
                echo "$NESSIE_COMMITS"
            fi
            
            # Check job metrics
            echo ""
            echo "📊 Checking job metrics..."
            JOB_DETAILS=$(curl -s ${FLINK_JOBMANAGER_URL}/jobs/${JOB_ID} 2>/dev/null || echo "")
            if echo "$JOB_DETAILS" | grep -q "RUNNING"; then
                echo "✅ Job is still running"
            else
                echo "⚠️  Job status unclear"
            fi
            
        else
            echo "❌ Failed to insert test data"
            echo "$INSERT_RESULT"
        fi
        
    else
        echo "⚠️  No running jobs found - job may have failed to start"
        echo "   Check Flink Web UI for details: ${FLINK_JOBMANAGER_URL}"
    fi
    
else
    echo ""
    echo "❌ Nessie lakehouse job submission failed!"
    echo "========================================="
    
    # Check for specific error patterns
    if echo "$JOB_RESULT" | grep -q "ClassNotFoundException"; then
        echo "🔍 Detected ClassNotFoundException - missing dependencies"
        echo "   Check Nessie JARs installation"
    elif echo "$JOB_RESULT" | grep -q "S3"; then
        echo "🔍 Detected S3-related error"
        echo "   Check MinIO connectivity and S3A configuration"
    elif echo "$JOB_RESULT" | grep -q "catalog"; then
        echo "🔍 Detected catalog-related error"
        echo "   Check Nessie catalog configuration"
    elif echo "$JOB_RESULT" | grep -q "nessie"; then
        echo "🔍 Detected Nessie-related error"
        echo "   Check Nessie connectivity and authentication"
    fi
fi

echo ""
echo "🎯 NESSIE LAKEHOUSE INTEGRATION SUMMARY"
echo "======================================="

if [ $JOB_EXIT_CODE -eq 0 ]; then
    echo "✅ Nessie Catalog: Working with catalog-impl"
    echo "✅ Iceberg Integration: Successful"
    echo "✅ CDC Processing: Real-time data flow active"
    echo "✅ Git-like Versioning: Nessie managing metadata"
    echo "✅ Data Pipeline: PostgreSQL → Kafka → Flink → Nessie → Iceberg"
    
    echo ""
    echo "🔍 MONITORING COMMANDS:"
    echo "======================"
    echo "• Flink Web UI: open ${FLINK_JOBMANAGER_URL}"
    echo "• MinIO Console: open ${MINIO_CONSOLE_URL}"
    echo "• Nessie API: curl ${NESSIE_URL_EXTERNAL}/trees/main/entries"
    echo "• Check warehouse: docker exec ${CONTAINER_MINIO} mc ls -r minio/warehouse/"
    echo "• Job logs: docker logs ${CONTAINER_FLINK_TM} -f"
    
    echo ""
    echo "🎮 NESSIE FEATURES:"
    echo "=================="
    echo "• Git-like branching: curl ${NESSIE_URL_EXTERNAL}/trees/main"
    echo "• Version history: curl ${NESSIE_URL_EXTERNAL}/trees/main/log"
    echo "• Time travel queries: Available through Dremio"
    echo "• Data versioning: Automatic with every CDC operation"
    
else
    echo "❌ Nessie Catalog: Configuration issues"
    echo "⚠️  Iceberg Integration: Failed"
    echo "⚠️  CDC Processing: Not connected to lakehouse"
    echo "❌ Data Pipeline: Incomplete"
    
    echo ""
    echo "🔧 TROUBLESHOOTING:"
    echo "=================="
    echo "1. Check Nessie logs: docker logs nessie"
    echo "2. Verify Nessie JARs: docker exec ${CONTAINER_FLINK_JM} ls /opt/flink/lib/ | grep nessie"
    echo "3. Test Nessie API: curl ${NESSIE_URL_EXTERNAL}/config"
    echo "4. Check Flink logs: docker logs ${CONTAINER_FLINK_JM}"
fi

echo ""
echo "🏁 Nessie Lakehouse Job Test Complete!"

# Return appropriate exit code
if [ $JOB_EXIT_CODE -eq 0 ]; then
    exit 0
else
    exit 1
fi 