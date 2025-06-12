#!/bin/bash

# ===== SUBMIT POSTGRES CDC TO LAKEHOUSE JOB =====
# Direct stream from PostgreSQL to MinIO lakehouse

echo "🚀 SUBMITTING POSTGRES CDC TO LAKEHOUSE JOB..."

# Check if Flink is running
if ! curl -s http://localhost:8081 > /dev/null; then
    echo "❌ Flink JobManager not accessible at http://localhost:8081"
    exit 1
fi

echo "✅ Flink JobManager is accessible"

# Submit the SQL job using postgres-cdc
echo "📤 Submitting Postgres CDC job..."

docker exec -i jobmanager /opt/flink/bin/sql-client.sh embedded << 'EOF'
-- Set S3 configuration for MinIO
SET 'fs.s3a.endpoint' = 'http://minioserver:9000';
SET 'fs.s3a.access-key' = 'minioadmin';
SET 'fs.s3a.secret-key' = 'minioadmin';
SET 'fs.s3a.path.style.access' = 'true';
SET 'fs.s3a.impl' = 'org.apache.hadoop.fs.s3a.S3AFileSystem';

-- Create PostgreSQL CDC source table
CREATE TABLE demographics_postgres_source (
    id INT,
    city STRING,
    population BIGINT,
    created_at TIMESTAMP(3),
    PRIMARY KEY (id) NOT ENFORCED
) WITH (
    'connector' = 'postgres-cdc',
    'hostname' = 'postgres',
    'port' = '5432',
    'username' = 'admin',
    'password' = 'admin123',
    'database-name' = 'bigdata_db',
    'schema-name' = 'public',
    'table-name' = 'demographics'
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
FROM demographics_postgres_source;

EXIT;
EOF

echo ""
echo "✅ Postgres CDC job submitted!"

# Check job status
echo "🔍 Checking submitted jobs..."
sleep 5
curl -s http://localhost:8081/jobs | python3 -m json.tool 2>/dev/null || echo "Could not parse jobs response"

echo ""
echo "💡 NEXT STEPS:"
echo "1. Check Flink Web UI: http://localhost:8081"
echo "2. Monitor job execution and logs"
echo "3. Wait 2-3 minutes for data to be written to lakehouse"
echo "4. Check MinIO Console: http://localhost:9001"
echo "5. Refresh Dremio sources to see new data"
echo "6. Run validation: ./validate_data_consistency.sh" 