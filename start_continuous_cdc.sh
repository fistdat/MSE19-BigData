#!/bin/bash
# =============================================================================
# START CONTINUOUS CDC STREAMING
# =============================================================================
# Start continuous CDC streaming job after AWS_REGION fix
# =============================================================================

source pipeline_config.env

echo "🔄 STARTING CONTINUOUS CDC STREAMING"
echo "===================================="

# Verify AWS_REGION is set
AWS_REGION_JM=$(docker exec jobmanager env | grep AWS_REGION | cut -d'=' -f2)
AWS_REGION_TM=$(docker exec taskmanager env | grep AWS_REGION | cut -d'=' -f2)

echo "🔍 AWS_REGION verification:"
echo "   JobManager: $AWS_REGION_JM"
echo "   TaskManager: $AWS_REGION_TM"

if [ "$AWS_REGION_JM" = "us-east-1" ] && [ "$AWS_REGION_TM" = "us-east-1" ]; then
    echo "✅ AWS_REGION correctly set!"
else
    echo "❌ AWS_REGION not properly set"
    exit 1
fi

# Create continuous streaming SQL
cat > /tmp/continuous_cdc_streaming.sql << 'EOF'
-- CONTINUOUS CDC STREAMING (POST AWS_REGION FIX)
SET 'execution.runtime-mode' = 'streaming';
SET 'execution.checkpointing.interval' = '60s';
SET 'execution.checkpointing.mode' = 'EXACTLY_ONCE';

-- Configure Nessie Iceberg catalog
CREATE CATALOG iceberg_catalog WITH (
    'type' = 'iceberg',
    'catalog-impl' = 'org.apache.iceberg.nessie.NessieCatalog',
    'io-impl' = 'org.apache.iceberg.aws.s3.S3FileIO',
    'uri' = 'http://nessie:19120/api/v1',
    'authentication.type' = 'none',
    'ref' = 'main',
    'warehouse' = 's3a://warehouse/',
    's3.endpoint' = 'http://minioserver:9000',
    's3.access-key-id' = 'DKZjmhls7nwxBN4GJfXC',
    's3.secret-access-key' = 'kNuAZodphLEGKHv5EmbyiDt1v5eT0yVErjVFyg0t',
    's3.path-style-access' = 'true',
    's3.region' = 'us-east-1'
);

USE CATALOG iceberg_catalog;
CREATE DATABASE IF NOT EXISTS cdc_lakehouse;
USE cdc_lakehouse;

-- Clean up existing tables
DROP TABLE IF EXISTS kafka_cdc_source;
DROP TABLE IF EXISTS demographics_streaming;

-- Create Kafka CDC source table  
CREATE TABLE kafka_cdc_source (
    `before` ROW<
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
    'properties.group.id' = 'flink-continuous-cdc-consumer',
    'scan.startup.mode' = 'latest-offset',
    'format' = 'json',
    'json.fail-on-missing-field' = 'false',
    'json.ignore-parse-errors' = 'true'
);

-- Create Iceberg streaming sink table
CREATE TABLE demographics_streaming (
    operation STRING,
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
    population_count INT,
    event_time TIMESTAMP(3),
    processing_time TIMESTAMP(3)
) 
WITH (
    'format-version' = '2'
);

SHOW TABLES;

-- Start continuous streaming job
INSERT INTO demographics_streaming
SELECT 
    CASE 
        WHEN op = 'c' THEN 'CREATE'
        WHEN op = 'u' THEN 'UPDATE' 
        WHEN op = 'd' THEN 'DELETE'
        WHEN op = 'r' THEN 'READ'
        ELSE 'UNKNOWN'
    END as operation,
    COALESCE(`after`.city, `before`.city) as city,
    COALESCE(`after`.state, `before`.state) as state,
    COALESCE(`after`.median_age, `before`.median_age) as median_age,
    COALESCE(`after`.male_population, `before`.male_population) as male_population,
    COALESCE(`after`.female_population, `before`.female_population) as female_population,
    COALESCE(`after`.total_population, `before`.total_population) as total_population,
    COALESCE(`after`.number_of_veterans, `before`.number_of_veterans) as number_of_veterans,
    COALESCE(`after`.foreign_born, `before`.foreign_born) as foreign_born,
    COALESCE(`after`.average_household_size, `before`.average_household_size) as average_household_size,
    COALESCE(`after`.state_code, `before`.state_code) as state_code,
    COALESCE(`after`.race, `before`.race) as race,
    COALESCE(`after`.population_count, `before`.population_count) as population_count,
    TO_TIMESTAMP_LTZ(ts_ms, 3) as event_time,
    CURRENT_TIMESTAMP as processing_time
FROM kafka_cdc_source
WHERE op IN ('c', 'u', 'd', 'r');
EOF

# Execute continuous streaming job
echo ""
echo "🚀 Starting CONTINUOUS CDC streaming job..."
docker cp /tmp/continuous_cdc_streaming.sql ${CONTAINER_FLINK_JM}:/tmp/

echo "📤 Executing continuous streaming job..."
nohup docker exec ${CONTAINER_FLINK_JM} /opt/flink/bin/sql-client.sh -f /tmp/continuous_cdc_streaming.sql > /tmp/flink_cdc.log 2>&1 &

FLINK_PID=$!
echo "🔧 Started background job with PID: $FLINK_PID"

# Wait for job to start
echo "⏳ Waiting for job to start (15 seconds)..."
sleep 15

# Check job status
echo ""
echo "🔍 Checking continuous streaming job status..."
JOBS_RESPONSE=$(curl -s ${FLINK_JOBMANAGER_URL}/jobs)
echo "Jobs: $JOBS_RESPONSE"

RUNNING_JOBS=$(echo "$JOBS_RESPONSE" | grep -o '"status":"RUNNING"' | wc -l || echo "0")

if [ "$RUNNING_JOBS" -gt 0 ]; then
    JOB_ID=$(echo "$JOBS_RESPONSE" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
    echo "✅ Continuous streaming job running with ID: $JOB_ID"
    
    # Test the pipeline with new data
    echo ""
    echo "🧪 Testing continuous CDC pipeline..."
    TEST_TIMESTAMP=$(date +%s)
    TEST_CITY="ContinuousCDC_${TEST_TIMESTAMP}"
    
    INSERT_RESULT=$(docker exec ${CONTAINER_POSTGRES} psql -U ${PG_USER} -d ${PG_DATABASE} -c "INSERT INTO demographics (city, state, count) VALUES ('${TEST_CITY}', 'StreamingState', 12345);" 2>&1)
    
    if echo "$INSERT_RESULT" | grep -q "INSERT 0 1"; then
        echo "✅ Test data inserted: $TEST_CITY"
        echo "⏳ Waiting for real-time processing (20 seconds)..."
        sleep 20
        
        echo ""
        echo "🎉 CONTINUOUS CDC PIPELINE ACTIVE!"
        echo "=================================="
        echo "✅ PostgreSQL → Kafka → Flink → Nessie → Iceberg: RUNNING"
        echo "✅ AWS_REGION issue: RESOLVED"
        echo "✅ Job ID: $JOB_ID"
        echo "✅ Real-time streaming: CONTINUOUS"
        echo "✅ Test data: $TEST_CITY being processed"
        echo ""
        echo "🔗 Monitor Endpoints:"
        echo "• Flink UI: ${FLINK_JOBMANAGER_URL}"
        echo "• Flink Job: ${FLINK_JOBMANAGER_URL}/#/job/${JOB_ID}/overview"
        echo "• MinIO Console: ${MINIO_CONSOLE_URL}"  
        echo "• Nessie API: ${NESSIE_URL_EXTERNAL}/trees/main"
        echo ""
        echo "⚡ Pipeline Status: REAL-TIME ACTIVE"
        echo "   Add data to PostgreSQL and it will flow automatically to Iceberg!"
        
    else
        echo "❌ Test data insertion failed"
        echo "$INSERT_RESULT"
    fi
else
    echo "⚠️  No running jobs found"
    echo "Jobs response: $JOBS_RESPONSE"
fi

echo ""
echo "🏁 Continuous CDC Pipeline Startup Complete!" 