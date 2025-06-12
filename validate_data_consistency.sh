#!/bin/bash

echo "=== LAKEHOUSE PIPELINE VALIDATION ==="
echo "Validating data consistency across PostgreSQL → Kafka → Flink → Nessie/Iceberg → MinIO"
echo

# 1. Check PostgreSQL data
echo "1. PostgreSQL Source Data:"
docker exec postgres psql -U postgres -d testdb -c "SELECT COUNT(*) as postgres_count FROM citizen;"
echo

# 2. Check Kafka CDC messages
echo "2. Kafka CDC Messages:"
docker exec kafka kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic postgres_server.public.citizen --from-beginning --timeout-ms 5000 2>/dev/null | wc -l | awk '{print "Kafka messages: " $1}'
echo

# 3. Check Flink jobs
echo "3. Flink Jobs Status:"
curl -s http://localhost:8081/jobs | grep -o '"status":"[^"]*"' | head -3
echo

# 4. Check MinIO lakehouse files
echo "4. MinIO Lakehouse Files:"
docker exec minioserver mc ls local/lakehouse --recursive | grep -v "test.txt" | wc -l | awk '{print "MinIO files: " $1}'
echo

# 5. Check Nessie catalog
echo "5. Nessie Catalog Status:"
curl -s http://localhost:19120/api/v1/config | grep -o '"defaultBranch":"[^"]*"'
echo

# 6. Test Iceberg table query
echo "6. Iceberg Table Query Test:"
echo "CREATE CATALOG nessie_catalog WITH ('type' = 'iceberg', 'catalog-impl' = 'org.apache.iceberg.nessie.NessieCatalog', 'uri' = 'http://nessie:19120/api/v1', 'ref' = 'main', 'warehouse' = 's3a://lakehouse/warehouse', 'io-impl' = 'org.apache.iceberg.aws.s3.S3FileIO', 's3.endpoint' = 'http://minioserver:9000', 's3.access-key-id' = 'minioadmin', 's3.secret-access-key' = 'minioadmin123', 's3.path-style-access' = 'true', 's3.region' = 'us-east-1', 'authentication.type' = 'NONE'); USE CATALOG nessie_catalog; USE cdc_db; SELECT COUNT(*) FROM citizen_cdc;" > /tmp/validate_query.sql

docker cp /tmp/validate_query.sql jobmanager:/opt/flink/sql/validate_query.sql
docker exec -e AWS_REGION="us-east-1" -e AWS_ACCESS_KEY_ID="minioadmin" -e AWS_SECRET_ACCESS_KEY="minioadmin123" jobmanager /opt/flink/bin/sql-client.sh -f /opt/flink/sql/validate_query.sql 2>/dev/null | grep -A 5 "Flink SQL>" | tail -3

echo
echo "=== VALIDATION COMPLETE ===" 