#!/bin/bash

echo "Testing MinIO access..."

# Test with default credentials
echo "Testing with default credentials (minioadmin)..."
docker exec minioserver mc alias set local http://localhost:9000 minioadmin minioadmin123

# List buckets
echo "Listing buckets..."
docker exec minioserver mc ls local

# Test with new credentials
echo "Testing with new credentials..."
docker exec minioserver mc alias set local http://localhost:9000 DKZjmhls7nwxBN4GJfXC kNuAZodphLEGKHv5EmbyiDt1v5eT0yVErjVFyg0t

# List buckets with new credentials
echo "Listing buckets with new credentials..."
docker exec minioserver mc ls local 