-- Dremio-Compatible CDC Streaming
-- Following Dremio CDC best practices for non-Iceberg setup
-- =========================================================

-- 1. Test simple Kafka reading first
CREATE TABLE test_kafka_raw (
    raw_message STRING
) WITH (
    'connector' = 'kafka',
    'topic' = 'demographics_server.public.demographics',
    'properties.bootstrap.servers' = 'kafka:9092',
    'properties.group.id' = 'test-consumer',
    'scan.startup.mode' = 'latest-offset',
    'format' = 'raw'
);

-- 2. Create print sink to debug
CREATE TABLE print_sink (
    message STRING
) WITH (
    'connector' = 'print'
);

-- 3. Debug what we're getting from Kafka
INSERT INTO print_sink
SELECT raw_message
FROM test_kafka_raw
LIMIT 10; 