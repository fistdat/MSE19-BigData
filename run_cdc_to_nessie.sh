#!/bin/bash

# Run CDC to Nessie Iceberg Streaming
echo "Starting CDC to Nessie Iceberg streaming..."

# Set AWS environment variables for MinIO
export AWS_REGION="us-east-1"
export AWS_ACCESS_KEY_ID="minioadmin"
export AWS_SECRET_ACCESS_KEY="minioadmin123"

# Copy SQL file to container
echo "Copying CDC script to container..."
docker cp flink_cdc_to_nessie_iceberg.sql jobmanager:/opt/flink/sql/flink_cdc_to_nessie_iceberg.sql

# Run CDC streaming with environment variables
echo "Executing CDC to Nessie Iceberg streaming..."
docker exec -e AWS_REGION="$AWS_REGION" -e AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" -e AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY" -it jobmanager /opt/flink/bin/sql-client.sh -f /opt/flink/sql/flink_cdc_to_nessie_iceberg.sql

echo "CDC to Nessie Iceberg streaming completed!" 