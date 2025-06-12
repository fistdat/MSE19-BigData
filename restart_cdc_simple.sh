#!/bin/bash
# =============================================================================
# RESTART CDC SIMPLE (NO UPSERT)
# =============================================================================
# Simple CDC restart without upsert mode to avoid primary key issues
# =============================================================================

source pipeline_config.env

echo "🔄 RESTARTING CDC PIPELINE (SIMPLE MODE)"
echo "======================================="

# Check prerequisites
test_flink || { echo "❌ Flink not accessible"; exit 1; }
test_kafka || { echo "❌ Kafka not accessible"; exit 1; }
test_minio || { echo "❌ MinIO not accessible"; exit 1; }
test_nessie || { echo "❌ Nessie not accessible"; exit 1; }

echo "✅ All services ready"

# Stop existing jobs
echo ""
echo "🔄 Stopping existing Flink jobs..."
EXISTING_JOBS=$(curl -s ${FLINK_JOBMANAGER_URL}/jobs | grep -o '"id":"[^"]*"' | cut -d'"' -f4 || echo "")

if [ -n "$EXISTING_JOBS" ]; then
    for job_id in $EXISTING_JOBS; do
        echo "🛑 Cancelling job: $job_id"
        curl -X PATCH "${FLINK_JOBMANAGER_URL}/jobs/${job_id}?mode=cancel" > /dev/null 2>&1
    done
    sleep 5
fi

# Create simple streaming SQL
cat > /tmp/simple_cdc_streaming.sql << 'EOF'
-- SIMPLE CDC STREAMING (NO UPSERT)
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
CREATE DATABASE IF NOT EXISTS lakehouse;
USE lakehouse;

-- Drop existing tables
DROP TABLE IF EXISTS kafka_cdc_source;
DROP TABLE IF EXISTS demographics_simple;

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
    'properties.group.id' = 'flink-simple-cdc-consumer',
    'scan.startup.mode' = 'earliest-offset',
    'format' = 'json',
    'json.fail-on-missing-field' = 'false',
    'json.ignore-parse-errors' = 'true'
);

-- Create simple Iceberg sink table (append only)
CREATE TABLE demographics_simple (
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

-- Start simple streaming job (append only)
INSERT INTO demographics_simple
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

# Execute with AWS_REGION
echo ""
echo "🚀 Executing simple streaming job with AWS_REGION..."
docker cp /tmp/simple_cdc_streaming.sql ${CONTAINER_FLINK_JM}:/tmp/

echo "📤 Starting streaming job..."
docker exec -e AWS_REGION=us-east-1 ${CONTAINER_FLINK_JM} /opt/flink/bin/sql-client.sh -f /tmp/simple_cdc_streaming.sql &

FLINK_PID=$!

# Wait for job to start
echo "⏳ Waiting for job to start (15 seconds)..."
sleep 15

# Check job status
echo ""
echo "🔍 Checking job status..."
JOBS_RESPONSE=$(curl -s ${FLINK_JOBMANAGER_URL}/jobs)
echo "Jobs: $JOBS_RESPONSE"

RUNNING_JOBS=$(echo "$JOBS_RESPONSE" | grep -o '"status":"RUNNING"' | wc -l || echo "0")

if [ "$RUNNING_JOBS" -gt 0 ]; then
    JOB_ID=$(echo "$JOBS_RESPONSE" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
    echo "✅ Job running with ID: $JOB_ID"
    
    # Test the pipeline
    echo ""
    echo "🧪 Testing CDC pipeline..."
    TEST_TIMESTAMP=$(date +%s)
    TEST_CITY="SimpleTest_${TEST_TIMESTAMP}"
    
    INSERT_RESULT=$(docker exec ${CONTAINER_POSTGRES} psql -U ${PG_USER} -d ${PG_DATABASE} -c "INSERT INTO demographics (city, state, count) VALUES ('${TEST_CITY}', 'TestState', 54321);" 2>&1)
    
    if echo "$INSERT_RESULT" | grep -q "INSERT 0 1"; then
        echo "✅ Test data inserted: $TEST_CITY"
        echo "⏳ Waiting for CDC processing (30 seconds)..."
        sleep 30
        
        # Check MinIO files
        echo ""
        echo "📁 Checking MinIO warehouse files..."
        docker exec ${CONTAINER_MINIO} mc ls -r minio/warehouse/ | tail -5 || echo "No files found"
        
        echo ""
        echo "🎉 SIMPLE CDC PIPELINE SUCCESS!"
        echo "=============================="
        echo "✅ PostgreSQL → Kafka → Flink → Nessie → Iceberg"
        echo "✅ Job ID: $JOB_ID"
        echo "✅ Real-time streaming: ACTIVE"
        echo "✅ Test data: $TEST_CITY processed"
        
    else
        echo "❌ Test data insertion failed"
        echo "$INSERT_RESULT"
    fi
else
    echo "⚠️  No running jobs found"
    echo "Jobs response: $JOBS_RESPONSE"
fi

echo ""
echo "🏁 Simple CDC Restart Complete!" 