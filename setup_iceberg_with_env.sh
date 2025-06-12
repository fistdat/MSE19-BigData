#!/bin/bash

# Setup Iceberg with Environment Variables
echo "Setting up Iceberg lakehouse with MinIO default credentials..."

# Set AWS environment variables for MinIO (using default credentials)
export AWS_ACCESS_KEY_ID="minioadmin"
export AWS_SECRET_ACCESS_KEY="minioadmin123"

# Copy updated SQL file to container
echo "Copying SQL file to container..."
docker cp simple_iceberg_setup.sql jobmanager:/opt/flink/sql/simple_iceberg_setup.sql

# Run SQL setup with environment variables
echo "Executing Iceberg setup..."
docker exec -e AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" -e AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY" -it jobmanager /opt/flink/bin/sql-client.sh -f /opt/flink/sql/simple_iceberg_setup.sql

echo "Iceberg setup completed!" 