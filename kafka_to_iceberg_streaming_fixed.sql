-- Flink SQL: Kafka CDC to Iceberg Streaming Job (Fixed for Flink 2.0.0)
-- ================================================================

-- 1. Create Kafka Source Table (CDC from Debezium)
CREATE TABLE kafka_demographics_source (
    before_id INT,
    before_city STRING,
    before_population INT,
    before_created_at BIGINT,
    after_id INT,
    after_city STRING,
    after_population INT,
    after_created_at BIGINT,
    op STRING,
    ts_ms BIGINT
) WITH (
    'connector' = 'kafka',
    'topic' = 'demographics_server.public.demographics',
    'properties.bootstrap.servers' = 'kafka:9092',
    'properties.group.id' = 'flink-cdc-consumer',
    'scan.startup.mode' = 'earliest-offset',
    'format' = 'json',
    'json.fail-on-missing-field' = 'false',
    'json.ignore-parse-errors' = 'true'
);

-- 2. Create Iceberg Catalog
CREATE CATALOG iceberg_catalog WITH (
    'type' = 'iceberg',
    'catalog-type' = 'nessie',
    'uri' = 'http://nessie:19120/api/v1',
    'ref' = 'main',
    'warehouse' = 's3://lakehouse',
    's3.endpoint' = 'http://minioserver:9000',
    's3.access-key-id' = 'minioadmin',
    's3.secret-access-key' = 'minioadmin123',
    's3.path-style-access' = 'true'
);

-- 3. Create Iceberg Table
CREATE TABLE iceberg_catalog.default.demographics_sink (
    id INT,
    city STRING,
    population INT,
    created_at TIMESTAMP(3),
    operation STRING,
    cdc_timestamp TIMESTAMP(3),
    PRIMARY KEY (id) NOT ENFORCED
) WITH (
    'format-version' = '2',
    'write.upsert.enabled' = 'true'
);

-- 4. Start Streaming Job: Kafka CDC → Iceberg
INSERT INTO iceberg_catalog.default.demographics_sink
SELECT 
    COALESCE(after_id, before_id) as id,
    COALESCE(after_city, before_city) as city,
    COALESCE(after_population, before_population) as population,
    CASE 
        WHEN after_created_at IS NOT NULL THEN TO_TIMESTAMP_LTZ(after_created_at / 1000, 3)
        ELSE TO_TIMESTAMP_LTZ(before_created_at / 1000, 3)
    END as created_at,
    op as operation,
    TO_TIMESTAMP_LTZ(ts_ms, 3) as cdc_timestamp
FROM kafka_demographics_source
WHERE op IN ('c', 'u', 'd', 'r'); 