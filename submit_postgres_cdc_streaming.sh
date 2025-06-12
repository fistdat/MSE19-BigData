#!/bin/bash

echo "🚀 SUBMITTING POSTGRESQL CDC STREAMING JOB TO FLINK..."

# Wait for Flink to be ready
echo "🔍 Checking Flink cluster health..."
for i in {1..30}; do
    if curl -s http://localhost:8081/overview > /dev/null; then
        echo "✅ Flink cluster is ready!"
        break
    fi
    echo "   Waiting for Flink... ($i/30)"
    sleep 2
done

# Submit PostgreSQL CDC streaming job via SQL Client
echo "📝 Submitting CDC streaming job..."
docker exec -i jobmanager-cdc ./bin/sql-client.sh -f /dev/stdin << 'EOF'
-- Flink SQL: PostgreSQL CDC to Kafka Streaming
-- Creates real-time streaming from PostgreSQL -> Kafka

-- Create source table connected to PostgreSQL (CDC)
CREATE TABLE postgres_demographics (
  id INT,
  name STRING,
  age INT,
  city STRING,
  salary DECIMAL(10,2),
  PRIMARY KEY (id) NOT ENFORCED
) WITH (
  'connector' = 'postgres-cdc',
  'hostname' = 'postgres',
  'port' = '5432',
  'username' = 'admin',
  'password' = 'admin123',
  'database-name' = 'bigdata_db',
  'schema-name' = 'public',
  'table-name' = 'demographics',
  'decoding.plugin.name' = 'pgoutput',
  'slot.name' = 'flink_slot'
);

-- Create target table for Kafka output using UPSERT connector for CDC
CREATE TABLE kafka_demographics (
  id INT,
  name STRING,
  age INT,
  city STRING,
  salary DECIMAL(10,2),
  PRIMARY KEY (id) NOT ENFORCED
) WITH (
  'connector' = 'upsert-kafka',
  'topic' = 'demographics-cdc',
  'properties.bootstrap.servers' = 'kafka:9092',
  'key.format' = 'json',
  'value.format' = 'json'
);

-- Start CDC streaming: PostgreSQL -> Kafka
INSERT INTO kafka_demographics
SELECT id, name, age, city, salary
FROM postgres_demographics;
EOF

echo ""
echo "📊 Checking job status..."
curl -s http://localhost:8081/jobs | python3 -m json.tool

echo ""
echo "✅ PostgreSQL CDC streaming job submitted!"
echo ""
echo "🌐 Monitor:"
echo "• Flink Web UI: http://localhost:8081"
echo "• Kafka UI: http://localhost:8082"
echo "• Check topic 'demographics-cdc' for CDC messages" 