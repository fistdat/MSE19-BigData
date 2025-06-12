#!/bin/bash

echo "🚀 SIMPLE FLINK JOB SUBMISSION"
echo "=============================="

# Check if Flink is accessible
if ! curl -s http://localhost:8081/overview > /dev/null; then
    echo "❌ Flink JobManager not accessible"
    exit 1
fi

echo "✅ Flink JobManager is accessible"

# Create SQL file
cat > /tmp/simple_cdc_job.sql << 'EOF'
-- Set checkpointing
SET 'execution.checkpointing.interval' = '60sec';

-- Create Kafka source table
CREATE TABLE demographics_source (
    city STRING,
    state STRING,
    median_age DOUBLE,
    male_population BIGINT,
    female_population BIGINT,
    total_population BIGINT,
    number_of_veterans BIGINT,
    foreign_born BIGINT,
    average_household_size DOUBLE,
    state_code STRING,
    race STRING,
    population_count BIGINT
) WITH (
    'connector' = 'kafka',
    'topic' = 'demographics_server.public.demographics',
    'properties.bootstrap.servers' = 'kafka:9092',
    'properties.group.id' = 'flink-cdc-consumer',
    'scan.startup.mode' = 'earliest-offset',
    'format' = 'debezium-json'
);

-- Simple insert to print sink for testing
CREATE TABLE print_sink (
    city STRING,
    state STRING,
    total_population BIGINT
) WITH (
    'connector' = 'print'
);

-- Insert data to print sink
INSERT INTO print_sink
SELECT city, state, total_population
FROM demographics_source;
EOF

echo "📄 Created SQL job file"

# Try to submit via Flink SQL Gateway (if available)
echo "🔄 Attempting to submit job..."

# Method 1: Try with taskmanager container
if docker exec taskmanager /opt/flink/bin/sql-client.sh embedded -f /tmp/simple_cdc_job.sql 2>/dev/null; then
    echo "✅ Job submitted via taskmanager"
elif docker exec jobmanager /opt/flink/bin/sql-client.sh embedded -f /tmp/simple_cdc_job.sql 2>/dev/null; then
    echo "✅ Job submitted via jobmanager"
else
    echo "⚠️  SQL client not available, trying alternative method..."
    
    # Method 2: Create a simple JAR submission (if we had a JAR)
    echo "📋 Available Flink containers:"
    docker ps | grep flink
    
    echo ""
    echo "🔧 Manual submission required:"
    echo "1. Access Flink UI: http://localhost:8081"
    echo "2. Go to 'Submit New Job'"
    echo "3. Upload a Flink SQL job JAR or use SQL Gateway"
    echo ""
    echo "📄 SQL to execute:"
    cat /tmp/simple_cdc_job.sql
fi

# Check job status
sleep 5
echo ""
echo "📊 Current Flink jobs:"
curl -s http://localhost:8081/jobs | jq '.' 2>/dev/null || echo "No jobs or jq not available"

# Clean up
rm -f /tmp/simple_cdc_job.sql

echo ""
echo "✅ Job submission attempt completed" 