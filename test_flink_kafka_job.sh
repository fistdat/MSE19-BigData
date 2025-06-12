#!/bin/bash
# =============================================================================
# TEST FLINK KAFKA JOB SUBMISSION
# =============================================================================
# This script tests Flink job submission with Kafka source after fixing dependencies
# =============================================================================

source pipeline_config.env

echo "🧪 TESTING FLINK KAFKA JOB SUBMISSION"
echo "====================================="

# Test configuration
TEST_JOB_NAME="kafka-cdc-test-job"
TEST_SQL_FILE="test_kafka_streaming.sql"

echo "📋 Pre-flight checks..."
echo "======================"

# Check if all services are running
echo "🔍 Checking service status..."

# Test connections
test_flink || { echo "❌ Flink not accessible"; exit 1; }
test_kafka || { echo "❌ Kafka not accessible"; exit 1; }
test_postgresql || { echo "❌ PostgreSQL not accessible"; exit 1; }

echo "✅ All required services are running"

# Check if CDC topic exists and has data
echo ""
echo "🔍 Checking CDC topic status..."
TOPIC_EXISTS=$(docker exec ${CONTAINER_KAFKA} kafka-topics --bootstrap-server ${KAFKA_BOOTSTRAP_SERVERS} --list | grep "${KAFKA_CDC_TOPIC}" || echo "")

if [ -z "$TOPIC_EXISTS" ]; then
    echo "❌ CDC topic ${KAFKA_CDC_TOPIC} does not exist"
    echo "   Run CDC setup first: ./setup_debezium_cdc.sh"
    exit 1
else
    echo "✅ CDC topic ${KAFKA_CDC_TOPIC} exists"
fi

# Check topic has messages
echo "🔍 Checking for CDC messages..."
MESSAGE_COUNT=$(docker exec ${CONTAINER_KAFKA} kafka-console-consumer --bootstrap-server ${KAFKA_BOOTSTRAP_SERVERS} --topic ${KAFKA_CDC_TOPIC} --from-beginning --timeout-ms 5000 2>/dev/null | wc -l || echo "0")

if [ "$MESSAGE_COUNT" -gt 0 ]; then
    echo "✅ Found $MESSAGE_COUNT CDC messages in topic"
else
    echo "⚠️  No messages found in CDC topic (this is OK for testing)"
fi

echo ""
echo "🚀 Creating test Flink SQL job..."
echo "================================="

# Create test SQL file
cat > ${TEST_SQL_FILE} << 'EOF'
-- =============================================================================
-- FLINK KAFKA CDC TEST JOB
-- =============================================================================

-- Set execution mode
SET 'execution.runtime-mode' = 'streaming';
SET 'execution.checkpointing.interval' = '60s';
SET 'execution.checkpointing.mode' = 'EXACTLY_ONCE';

-- Create Kafka source table
CREATE TABLE kafka_cdc_source (
    `before` ROW<
        id INT,
        city STRING,
        state STRING,
        median_age DOUBLE,
        male_population INT,
        female_population INT,
        total_population INT,
        number_of_veterans INT,
        foreign_born INT,
        average_household_size DOUBLE,
        state_code STRING,
        race STRING,
        population_count INT
    >,
    `after` ROW<
        id INT,
        city STRING,
        state STRING,
        median_age DOUBLE,
        male_population INT,
        female_population INT,
        total_population INT,
        number_of_veterans INT,
        foreign_born INT,
        average_household_size DOUBLE,
        state_code STRING,
        race STRING,
        population_count INT
    >,
    `op` STRING,
    `ts_ms` BIGINT,
    `source` ROW<
        version STRING,
        connector STRING,
        name STRING,
        ts_ms BIGINT,
        snapshot STRING,
        db STRING,
        sequence STRING,
        schema STRING,
        `table` STRING,
        txId BIGINT,
        lsn BIGINT,
        xmin BIGINT
    >
) WITH (
    'connector' = 'kafka',
    'topic' = 'demographics_server.public.demographics',
    'properties.bootstrap.servers' = 'kafka:9092',
    'properties.group.id' = 'flink-test-consumer',
    'scan.startup.mode' = 'earliest-offset',
    'format' = 'json',
    'json.fail-on-missing-field' = 'false',
    'json.ignore-parse-errors' = 'true'
);

-- Create print sink for testing
CREATE TABLE print_sink (
    operation STRING,
    record_id INT,
    city STRING,
    state STRING,
    population_count INT,
    event_time TIMESTAMP(3)
) WITH (
    'connector' = 'print'
);

-- Insert test query - process CDC events
INSERT INTO print_sink
SELECT 
    CASE 
        WHEN op = 'c' THEN 'CREATE'
        WHEN op = 'u' THEN 'UPDATE' 
        WHEN op = 'd' THEN 'DELETE'
        ELSE 'UNKNOWN'
    END as operation,
    COALESCE(`after`.id, `before`.id) as record_id,
    COALESCE(`after`.city, `before`.city) as city,
    COALESCE(`after`.state, `before`.state) as state,
    COALESCE(`after`.population_count, `before`.population_count) as population_count,
    TO_TIMESTAMP_LTZ(ts_ms, 3) as event_time
FROM kafka_cdc_source
WHERE op IN ('c', 'u', 'd');
EOF

echo "✅ Created test SQL file: ${TEST_SQL_FILE}"

echo ""
echo "📋 Test SQL content:"
echo "==================="
head -20 ${TEST_SQL_FILE}
echo "... (truncated)"

echo ""
echo "🚀 Submitting Flink job..."
echo "=========================="

# Submit job using Flink SQL Client
echo "📤 Executing SQL job via Flink SQL Client..."

# Copy SQL file to Flink container
TEMP_SQL_SCRIPT="/tmp/flink_test_job.sql"
docker cp ${TEST_SQL_FILE} ${CONTAINER_FLINK_JM}:${TEMP_SQL_SCRIPT}

# Execute the job
JOB_RESULT=$(docker exec ${CONTAINER_FLINK_JM} /opt/flink/bin/sql-client.sh -f ${TEMP_SQL_SCRIPT} 2>&1)
JOB_EXIT_CODE=$?

echo "📊 Job submission result:"
echo "========================"
echo "$JOB_RESULT"

if [ $JOB_EXIT_CODE -eq 0 ]; then
    echo ""
    echo "✅ Job submitted successfully!"
    
    echo ""
    echo "🔍 Checking running jobs..."
    RUNNING_JOBS=$(curl -s ${FLINK_JOBMANAGER_URL}/jobs | jq -r '.jobs[] | select(.status == "RUNNING") | .id' 2>/dev/null || echo "")
    
    if [ -n "$RUNNING_JOBS" ]; then
        echo "✅ Found running jobs:"
        echo "$RUNNING_JOBS"
        
        echo ""
        echo "🎯 MONITORING INSTRUCTIONS:"
        echo "=========================="
        echo "1. 🌐 Open Flink Web UI: ${FLINK_JOBMANAGER_URL}"
        echo "2. 📊 Check job metrics and logs"
        echo "3. 🔍 Monitor TaskManager logs for print output"
        echo "4. 🧪 Test CDC by inserting data into PostgreSQL:"
        echo "   docker exec ${CONTAINER_POSTGRES} psql -U ${PG_USER} -d ${PG_DATABASE} -c \"INSERT INTO demographics (city, state, population_count) VALUES ('TestCity', 'TestState', 12345);\""
        
        echo ""
        echo "📝 To view TaskManager logs (where print output appears):"
        echo "docker logs ${CONTAINER_FLINK_TM} -f"
        
    else
        echo "⚠️  No running jobs found - job may have failed to start"
        echo "   Check Flink Web UI for details: ${FLINK_JOBMANAGER_URL}"
    fi
    
else
    echo ""
    echo "❌ Job submission failed!"
    echo "========================"
    
    # Check for specific error patterns
    if echo "$JOB_RESULT" | grep -q "ClassNotFoundException"; then
        echo "🔍 Detected ClassNotFoundException - dependency issue"
        echo "   Try running: ./fix_flink_kafka_dependencies.sh"
    elif echo "$JOB_RESULT" | grep -q "kafka"; then
        echo "🔍 Detected Kafka-related error"
        echo "   Check Kafka connectivity and topic existence"
    elif echo "$JOB_RESULT" | grep -q "JSON"; then
        echo "🔍 Detected JSON parsing error"
        echo "   Check CDC message format and schema"
    fi
    
    echo ""
    echo "🔧 TROUBLESHOOTING STEPS:"
    echo "========================"
    echo "1. Check Flink logs: docker logs ${CONTAINER_FLINK_JM}"
    echo "2. Check TaskManager logs: docker logs ${CONTAINER_FLINK_TM}"
    echo "3. Verify dependencies: docker exec ${CONTAINER_FLINK_JM} ls /opt/flink/lib/ | grep kafka"
    echo "4. Test Kafka connectivity: docker exec ${CONTAINER_KAFKA} kafka-topics --bootstrap-server ${KAFKA_BOOTSTRAP_SERVERS} --list"
fi

# Cleanup
echo ""
echo "🧹 Cleaning up temporary files..."
rm -f ${TEST_SQL_FILE} ${TEMP_SQL_SCRIPT}

echo ""
echo "🏁 Flink Kafka Job Test Complete!"

# Final status
if [ $JOB_EXIT_CODE -eq 0 ]; then
    echo "✅ SUCCESS: Job submitted and running"
    exit 0
else
    echo "❌ FAILED: Job submission failed"
    exit 1
fi 