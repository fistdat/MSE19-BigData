#!/bin/bash

echo "=== SUBMITTING PERSISTENT CDC STREAMING JOB ==="
echo "This will submit a long-running streaming job to Flink cluster"

# Set environment variables for AWS region
export AWS_REGION=us-east-1

echo "Starting streaming job submission..."

# Submit the streaming job via REST API approach
echo "Method 1: Using SQL Client with streaming job"

# Copy SQL file to container if not already there
docker cp nessie_cdc_to_iceberg_job_final.sql jobmanager:/opt/flink/scripts/

# Submit job via Flink SQL CLI with streaming execution
docker exec -e AWS_REGION=us-east-1 -d jobmanager bash -c "
cd /opt/flink && 
nohup bin/sql-client.sh embedded -f /opt/flink/scripts/nessie_cdc_to_iceberg_job_final.sql > /tmp/streaming_job.log 2>&1 &
echo 'Streaming job submitted in background'
"

echo "Waiting 10 seconds for job to start..."
sleep 10

echo "Checking job status..."
curl -s http://localhost:8081/jobs | jq '.' || curl -s http://localhost:8081/jobs

echo "Job submission completed!" 