-- Flink SQL: Kafka CDC to Iceberg Streaming Job
-- ================================================

-- 1. Create Kafka Source Table (CDC from Debezium)
CREATE TABLE kafka_demographics_source (
    `before` ROW<
        id INT,
        city STRING,
        population INT,
        created_at BIGINT
    >,
    `after` ROW<
        id INT,
        city STRING,
        population INT,
        created_at BIGINT
    >,
    `source` ROW<
        version STRING,
        connector STRING,
        name STRING,
        ts_ms BIGINT,
        snapshot STRING,
        db STRING,
        sequence ARRAY<STRING>,
        schema STRING,
        table STRING,
        txId INT,
        lsn BIGINT,
        xmin STRING
    >,
    op STRING,
    ts_ms BIGINT,
    transaction STRING
) WITH (
    'connector' = 'kafka',
    'topic' = 'demographics_server.public.demographics',
    'properties.bootstrap.servers' = 'kafka:9092',
    'properties.group.id' = 'flink-cdc-consumer',
    'scan.startup.mode' = 'earliest-offset',
    'format' = 'json'
);

-- 2. Create Iceberg Sink Table
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
    COALESCE(`after`.id, `before`.id) as id,
    COALESCE(`after`.city, `before`.city) as city,
    COALESCE(`after`.population, `before`.population) as population,
    CASE 
        WHEN `after`.created_at IS NOT NULL THEN TO_TIMESTAMP_LTZ(`after`.created_at / 1000, 3)
        ELSE TO_TIMESTAMP_LTZ(`before`.created_at / 1000, 3)
    END as created_at,
    op as operation,
    TO_TIMESTAMP_LTZ(ts_ms, 3) as cdc_timestamp
FROM kafka_demographics_source
WHERE op IN ('c', 'u', 'd', 'r'); -- Create, Update, Delete, Read operations 