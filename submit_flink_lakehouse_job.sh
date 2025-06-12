#!/bin/bash

# ===== SUBMIT FLINK LAKEHOUSE STREAMING JOB =====
# Stream data from Kafka CDC to MinIO lakehouse

echo "🚀 SUBMITTING FLINK LAKEHOUSE STREAMING JOB..."

# Check if Flink is running
if ! curl -s http://localhost:8081 > /dev/null; then
    echo "❌ Flink JobManager not accessible at http://localhost:8081"
    exit 1
fi

echo "✅ Flink JobManager is accessible"

# Submit the SQL job
echo "📤 Submitting Flink SQL job..."

# Method 1: Submit via SQL Client (if available)
echo "🔄 Attempting to submit via Flink SQL Client..."

docker exec -i jobmanager /opt/flink/bin/sql-client.sh embedded << 'EOF'
-- Set S3 configuration for MinIO
SET 'fs.s3a.endpoint' = 'http://minioserver:9000';
SET 'fs.s3a.access-key' = 'minioadmin';
SET 'fs.s3a.secret-key' = 'minioadmin';
SET 'fs.s3a.path.style.access' = 'true';
SET 'fs.s3a.impl' = 'org.apache.hadoop.fs.s3a.S3AFileSystem';

-- Create Kafka source table for CDC data
CREATE TABLE demographics_kafka_source (
    id INT,
    city STRING,
    population BIGINT,
    created_at TIMESTAMP(3),
    WATERMARK FOR created_at AS created_at - INTERVAL '5' SECOND
) WITH (
    'connector' = 'kafka',
    'topic' = 'demographics_server.public.demographics',
    'properties.bootstrap.servers' = 'kafka:9092',
    'properties.group.id' = 'flink-demographics-consumer',
    'scan.startup.mode' = 'earliest-offset',
    'format' = 'debezium-json'
);

-- Create MinIO S3 sink table for lakehouse
CREATE TABLE demographics_lakehouse_sink (
    id INT,
    city STRING,
    population BIGINT,
    created_at TIMESTAMP(3),
    processing_time TIMESTAMP(3)
) WITH (
    'connector' = 'filesystem',
    'path' = 's3a://lakehouse/demographics',
    'format' = 'parquet'
);

-- Submit streaming job
INSERT INTO demographics_lakehouse_sink
SELECT 
    id,
    city,
    population,
    created_at,
    CURRENT_TIMESTAMP as processing_time
FROM demographics_kafka_source
WHERE id IS NOT NULL;

EXIT;
EOF

echo ""
echo "✅ Flink job submitted!"

# Check job status
echo "🔍 Checking submitted jobs..."
sleep 5
curl -s http://localhost:8081/jobs | python3 -m json.tool 2>/dev/null || echo "Could not parse jobs response"

echo ""
echo "💡 NEXT STEPS:"
echo "1. Check Flink Web UI: http://localhost:8081"
echo "2. Monitor job execution and logs"
echo "3. Wait 2-3 minutes for data to be written to lakehouse"
echo "4. Refresh Dremio sources to see new data"
echo "5. Run validation script: ./validate_data_consistency.sh" 