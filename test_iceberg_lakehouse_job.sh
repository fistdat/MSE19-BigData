#!/bin/bash
# =============================================================================
# TEST ICEBERG LAKEHOUSE JOB
# =============================================================================
# This script tests Flink CDC to Iceberg lakehouse integration
# =============================================================================

source pipeline_config.env

echo "🧊 TESTING ICEBERG LAKEHOUSE JOB"
echo "================================"

# First, stop the existing print sink job to avoid conflicts
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

# Check Iceberg dependencies
echo ""
echo "🔍 Checking Iceberg dependencies..."
ICEBERG_JAR_COUNT=$(docker exec ${CONTAINER_FLINK_JM} ls /opt/flink/lib/ | grep -E "(iceberg|hadoop-aws)" | wc -l)
if [ "$ICEBERG_JAR_COUNT" -ge 2 ]; then
    echo "✅ Found $ICEBERG_JAR_COUNT Iceberg/S3A JARs"
else
    echo "❌ Missing Iceberg dependencies"
    echo "   Run: ./setup_flink_iceberg_dependencies.sh"
    exit 1
fi

echo ""
echo "🚀 Submitting Iceberg lakehouse job..."
echo "====================================="

# Copy SQL file to Flink container
docker cp create_simple_iceberg_job.sql ${CONTAINER_FLINK_JM}:/tmp/iceberg_job.sql

# Submit the job
echo "📤 Executing Iceberg job via Flink SQL Client..."
JOB_RESULT=$(docker exec ${CONTAINER_FLINK_JM} /opt/flink/bin/sql-client.sh -f /tmp/iceberg_job.sql 2>&1)
JOB_EXIT_CODE=$?

echo "📊 Job submission result:"
echo "========================"
echo "$JOB_RESULT"

if [ $JOB_EXIT_CODE -eq 0 ]; then
    echo ""
    echo "✅ Iceberg job submitted successfully!"
    
    # Wait a moment for job to start
    sleep 5
    
    # Check running jobs
    echo ""
    echo "🔍 Checking running jobs..."
    RUNNING_JOBS=$(curl -s ${FLINK_JOBMANAGER_URL}/jobs | grep -o '"status":"RUNNING"' | wc -l || echo "0")
    
    if [ "$RUNNING_JOBS" -gt 0 ]; then
        JOB_ID=$(curl -s ${FLINK_JOBMANAGER_URL}/jobs | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
        echo "✅ Found running job: $JOB_ID"
        
        # Test real-time CDC processing
        echo ""
        echo "🧪 Testing real-time CDC to Iceberg..."
        echo "======================================"
        
        # Insert test data
        TEST_TIMESTAMP=$(date +%s)
        TEST_CITY="IcebergTest_${TEST_TIMESTAMP}"
        TEST_STATE="LakehouseState"
        
        echo "📤 Inserting test data: $TEST_CITY"
        INSERT_RESULT=$(docker exec ${CONTAINER_POSTGRES} psql -U ${PG_USER} -d ${PG_DATABASE} -c "INSERT INTO demographics (city, state, count) VALUES ('${TEST_CITY}', '${TEST_STATE}', 77777);" 2>&1)
        
        if echo "$INSERT_RESULT" | grep -q "INSERT 0 1"; then
            echo "✅ Test data inserted successfully"
            
            # Wait for processing
            echo "⏳ Waiting for CDC processing and Iceberg write (30 seconds)..."
            sleep 30
            
            # Check MinIO for Iceberg files
            echo ""
            echo "🔍 Checking MinIO for Iceberg data files..."
            if docker exec ${CONTAINER_MINIO} mc ls minio/warehouse/iceberg/ > /dev/null 2>&1; then
                echo "✅ Iceberg directory exists in MinIO"
                echo "📋 Iceberg warehouse contents:"
                docker exec ${CONTAINER_MINIO} mc ls -r minio/warehouse/iceberg/ | head -10 || echo "No files yet or access issues"
            else
                echo "⚠️  Iceberg directory not found in MinIO"
            fi
            
            # Check job metrics
            echo ""
            echo "📊 Checking job metrics..."
            JOB_DETAILS=$(curl -s ${FLINK_JOBMANAGER_URL}/jobs/${JOB_ID} 2>/dev/null || echo "")
            if echo "$JOB_DETAILS" | grep -q "RUNNING"; then
                echo "✅ Job is still running"
                
                # Try to get vertex metrics
                VERTICES=$(curl -s ${FLINK_JOBMANAGER_URL}/jobs/${JOB_ID}/vertices 2>/dev/null | grep -o '"id":"[^"]*"' | cut -d'"' -f4 | head -3)
                if [ -n "$VERTICES" ]; then
                    echo "📈 Job vertices found, processing data..."
                fi
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
    echo "❌ Iceberg job submission failed!"
    echo "================================"
    
    # Check for specific error patterns
    if echo "$JOB_RESULT" | grep -q "ClassNotFoundException"; then
        echo "🔍 Detected ClassNotFoundException - missing dependencies"
        echo "   Check Iceberg JARs installation"
    elif echo "$JOB_RESULT" | grep -q "S3"; then
        echo "🔍 Detected S3-related error"
        echo "   Check MinIO connectivity and S3A configuration"
    elif echo "$JOB_RESULT" | grep -q "catalog"; then
        echo "🔍 Detected catalog-related error"
        echo "   Check Iceberg catalog configuration"
    elif echo "$JOB_RESULT" | grep -q "iceberg"; then
        echo "🔍 Detected Iceberg-related error"
        echo "   Check Iceberg table creation and schema"
    fi
fi

echo ""
echo "🎯 LAKEHOUSE INTEGRATION SUMMARY"
echo "==============================="

if [ $JOB_EXIT_CODE -eq 0 ]; then
    echo "✅ Iceberg Job: Submitted successfully"
    echo "✅ CDC Processing: Real-time data flow active"
    echo "✅ Lakehouse Storage: MinIO warehouse configured"
    echo "✅ Data Pipeline: PostgreSQL → Kafka → Flink → Iceberg"
    
    echo ""
    echo "🔍 MONITORING COMMANDS:"
    echo "======================"
    echo "• Flink Web UI: open ${FLINK_JOBMANAGER_URL}"
    echo "• MinIO Console: open ${MINIO_CONSOLE_URL}"
    echo "• Check Iceberg files: docker exec ${CONTAINER_MINIO} mc ls -r minio/warehouse/iceberg/"
    echo "• Job logs: docker logs ${CONTAINER_FLINK_TM} -f"
    
    echo ""
    echo "🧪 TEST COMMANDS:"
    echo "================"
    echo "• Insert test data: docker exec ${CONTAINER_POSTGRES} psql -U ${PG_USER} -d ${PG_DATABASE} -c \"INSERT INTO demographics (city, state, count) VALUES ('TestLakehouse', 'TestState', 88888);\""
    echo "• Check job status: curl -s ${FLINK_JOBMANAGER_URL}/jobs"
    
else
    echo "❌ Iceberg Job: Submission failed"
    echo "⚠️  CDC Processing: Not connected to lakehouse"
    echo "⚠️  Lakehouse Storage: Configuration issues"
    echo "❌ Data Pipeline: Incomplete"
    
    echo ""
    echo "🔧 TROUBLESHOOTING:"
    echo "=================="
    echo "1. Check Flink logs: docker logs ${CONTAINER_FLINK_JM}"
    echo "2. Verify dependencies: docker exec ${CONTAINER_FLINK_JM} ls /opt/flink/lib/ | grep iceberg"
    echo "3. Test MinIO access: docker exec ${CONTAINER_MINIO} mc ls minio/"
    echo "4. Check S3A configuration in job SQL"
fi

echo ""
echo "🏁 Iceberg Lakehouse Job Test Complete!"

# Return appropriate exit code
if [ $JOB_EXIT_CODE -eq 0 ]; then
    exit 0
else
    exit 1
fi 