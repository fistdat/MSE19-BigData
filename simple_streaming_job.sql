SET 'execution.runtime-mode' = 'streaming';
SET 'execution.checkpointing.interval' = '30s';

-- Use existing catalog
USE CATALOG iceberg_catalog;
USE lakehouse;

-- Create simple source table from Kafka
CREATE TABLE IF NOT EXISTS kafka_simple_source (
    after_city STRING,
    after_state STRING,
    after_total_population INT,
    operation STRING,
    ts_ms BIGINT
) WITH (
    'connector' = 'kafka',
    'topic' = 'demographics_server.public.demographics',
    'properties.bootstrap.servers' = 'kafka:9092',
    'properties.group.id' = 'flink-simple-test',
    'scan.startup.mode' = 'latest-offset',
    'format' = 'json',
    'json.fail-on-missing-field' = 'false',
    'json.ignore-parse-errors' = 'true',
    'json.map-null-key-mode' = 'LITERAL',
    'json.map-null-key.literal' = 'null'
);

-- Create simple sink table  
CREATE TABLE IF NOT EXISTS demographics_simple_sink (
    city STRING,
    state STRING,
    population INT,
    operation STRING,
    event_time TIMESTAMP(3)
) WITH (
    'format-version' = '2'
);

SHOW TABLES;

-- Start simple streaming
INSERT INTO demographics_simple_sink
SELECT 
    COALESCE(after_city, 'unknown') as city,
    COALESCE(after_state, 'unknown') as state, 
    COALESCE(after_total_population, 0) as population,
    COALESCE(operation, 'unknown') as operation,
    TO_TIMESTAMP_LTZ(COALESCE(ts_ms, 0), 3) as event_time
FROM kafka_simple_source; 