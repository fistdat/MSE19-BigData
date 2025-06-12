#!/bin/bash

echo "🔍 COMPREHENSIVE CDC LAKEHOUSE PIPELINE VALIDATION"
echo "=================================================="

# Check PostgreSQL
echo "📊 1. PostgreSQL Status:"
docker exec postgres psql -U admin -d demographics -c "SELECT COUNT(*) as total_records FROM demographics;" 2>/dev/null || echo "❌ PostgreSQL connection failed"

# Check Debezium
echo ""
echo "🔄 2. Debezium CDC Status:"
curl -s http://localhost:8083/connectors/demographics-connector/status | jq '.connector.state' 2>/dev/null || echo "❌ Debezium not accessible"

# Check Kafka Topic
echo ""
echo "📨 3. Kafka Topic Status:"
docker exec kafka /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --list | grep demographics 2>/dev/null || echo "❌ Kafka topic check failed"

# Check Flink Jobs
echo ""
echo "⚡ 4. Flink Jobs Status:"
docker exec jobmanager bash -c "echo 'SHOW JOBS;' | /opt/flink/bin/sql-client.sh" 2>/dev/null | grep -E "job id|job name|status" || echo "❌ No Flink jobs found"

# Check MinIO Structure
echo ""
echo "🗄️ 5. MinIO Warehouse Structure:"
docker exec minioserver mc ls -r minio/warehouse/ 2>/dev/null | head -10 || echo "❌ MinIO warehouse empty"

# Check for Data Files
echo ""
echo "📁 6. Data Files Check:"
DATA_FILES=$(docker exec minioserver mc ls -r minio/warehouse/ 2>/dev/null | grep -E "\\.parquet|\\.avro|\\.orc" | wc -l)
echo "Found $DATA_FILES data files"

# Check for Metadata Files
echo ""
echo "📋 7. Metadata Files Check:"
METADATA_FILES=$(docker exec minioserver mc ls -r minio/warehouse/ 2>/dev/null | grep -E "metadata\\.json|manifest" | wc -l)
echo "Found $METADATA_FILES metadata files"

# Check Nessie Catalog
echo ""
echo "🌊 8. Nessie Catalog Status:"
curl -s http://localhost:19120/api/v1/trees/tree/main 2>/dev/null | jq '.name' || echo "❌ Nessie not accessible"

# Summary
echo ""
echo "📈 PIPELINE SUMMARY:"
echo "==================="

if [ "$DATA_FILES" -gt 0 ]; then
    echo "✅ SUCCESS: Data files found in MinIO!"
    echo "   - $DATA_FILES data files"
    echo "   - $METADATA_FILES metadata files"
    echo "   - Checkpointing is working correctly"
else
    echo "⚠️  ISSUE: No data files found in MinIO"
    echo "   - Possible causes:"
    echo "     1. Checkpointing interval not reached (wait 30+ seconds)"
    echo "     2. Flink job not running properly"
    echo "     3. Schema mismatch between Kafka and Flink"
    echo "     4. Iceberg table configuration issue"
fi

echo ""
echo "🔧 TROUBLESHOOTING COMMANDS:"
echo "- Check Flink logs: docker logs jobmanager --tail 50"
echo "- Check TaskManager: docker logs taskmanager --tail 50"
echo "- Add test data: docker exec postgres psql -U admin -d demographics -c \"INSERT INTO demographics (city, state, median_age, male_population, female_population, total_population, number_of_veterans, foreign_born, average_household_size, state_code, race, count) VALUES ('Debug', 'Test', 50.0, 1000, 1000, 2000, 100, 200, 2.5, 'DT', 'Debug', 500);\""
echo "- Force checkpoint: Wait 30+ seconds after data insertion" 