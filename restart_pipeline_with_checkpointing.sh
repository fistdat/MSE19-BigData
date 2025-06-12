#!/bin/bash

echo "🔄 Restarting Flink Pipeline with Checkpointing Fix..."

# Cancel all running/failed jobs
echo "📋 Canceling existing Flink jobs..."
docker exec jobmanager bash -c "
echo 'CANCEL JOB \"c72dadb7902509da97e35148b80d460f\";' | /opt/flink/bin/sql-client.sh
echo 'CANCEL JOB \"f870207a669b48222fcce6e5765dbaf4\";' | /opt/flink/bin/sql-client.sh  
echo 'CANCEL JOB \"f6f7799c279a1b19d1cd502195703d45\";' | /opt/flink/bin/sql-client.sh
echo 'CANCEL JOB \"bd68db2594005bc46f0635fb55bfb008\";' | /opt/flink/bin/sql-client.sh
echo 'CANCEL JOB \"fd4faf507fa470c6ace380d8c97a3e38\";' | /opt/flink/bin/sql-client.sh
echo 'CANCEL JOB \"e09ab4d55965c9556495f0939c9df211\";' | /opt/flink/bin/sql-client.sh
"

echo "⏳ Waiting for jobs to cancel..."
sleep 10

# Create checkpoints directory in MinIO
echo "📁 Creating checkpoints directory in MinIO..."
docker exec minioserver mc mb minio/warehouse/checkpoints 2>/dev/null || true

# Run the fix script
echo "🚀 Running Iceberg checkpointing fix..."
docker exec jobmanager bash -c "cat /opt/flink/fix_iceberg_checkpointing.sql | /opt/flink/bin/sql-client.sh"

echo "✅ Pipeline restart completed!"
echo ""
echo "📊 Monitoring instructions:"
echo "1. Check job status: docker exec jobmanager bash -c \"echo 'SHOW JOBS;' | /opt/flink/bin/sql-client.sh\""
echo "2. Check MinIO data files: docker exec minioserver mc ls -r minio/warehouse/"
echo "3. Wait 2-3 minutes for checkpointing to create data files"
echo "4. Verify data: docker exec jobmanager bash -c \"echo 'SELECT COUNT(*) FROM nessie_catalog.cdc_db.demographics_iceberg;' | /opt/flink/bin/sql-client.sh\"" 