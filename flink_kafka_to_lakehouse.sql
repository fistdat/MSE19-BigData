-- ===== FLINK SQL: KAFKA CDC TO LAKEHOUSE =====
-- Stream demographics data from Kafka CDC topic to MinIO lakehouse

-- 1. Create Kafka source table for CDC data
CREATE TABLE demographics_kafka_source (
    id INT,
    city STRING,
    population BIGINT,
    created_at TIMESTAMP(3),
    WATERMARK FOR created_at AS created_at - INTERVAL '5' SECOND
) WITH (
    'connector' = 'kafka',
    'topic' = 'demographics_server.public.demographics',
    'properties.bootstrap.servers' = 'kafka:9092',
    'properties.group.id' = 'flink-demographics-consumer',
    'scan.startup.mode' = 'earliest-offset',
    'format' = 'debezium-json'
);

-- 2. Create MinIO S3 sink table for lakehouse
CREATE TABLE demographics_lakehouse_sink (
    id INT,
    city STRING,
    population BIGINT,
    created_at TIMESTAMP(3),
    processing_time TIMESTAMP(3)
) PARTITIONED BY (city) WITH (
    'connector' = 'filesystem',
    'path' = 's3a://lakehouse/demographics',
    'format' = 'parquet',
    'sink.partition-commit.trigger' = 'partition-time',
    'sink.partition-commit.delay' = '1 min',
    'sink.partition-commit.policy.kind' = 'metastore,success-file'
);

-- 3. Stream data from Kafka to lakehouse
INSERT INTO demographics_lakehouse_sink
SELECT 
    id,
    city,
    population,
    created_at,
    CURRENT_TIMESTAMP as processing_time
FROM demographics_kafka_source
WHERE id IS NOT NULL; 