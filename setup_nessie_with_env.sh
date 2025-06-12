#!/bin/bash

# Setup Nessie Catalog with Environment Variables
echo "Setting up Nessie catalog with environment variables..."

# Set AWS environment variables for MinIO
export AWS_REGION="us-east-1"
export AWS_ACCESS_KEY_ID="minioadmin"
export AWS_SECRET_ACCESS_KEY="minioadmin123"

# Copy updated SQL file to container
echo "Copying SQL file to container..."
docker cp nessie_native_catalog_setup.sql jobmanager:/opt/flink/sql/nessie_native_catalog_setup.sql

# Run SQL setup with environment variables
echo "Executing Nessie catalog setup..."
docker exec -e AWS_REGION="$AWS_REGION" -e AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" -e AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY" -it jobmanager /opt/flink/bin/sql-client.sh -f /opt/flink/sql/nessie_native_catalog_setup.sql

echo "Nessie catalog setup completed!" 