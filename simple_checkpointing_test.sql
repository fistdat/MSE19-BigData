-- Simple Checkpointing Test for Iceberg Data Files
-- Test with existing catalog setup

-- =====================================================
-- STEP 1: Configure Checkpointing (CRITICAL!)
-- =====================================================
SET 'execution.checkpointing.interval' = '30sec';
SET 'execution.checkpointing.mode' = 'EXACTLY_ONCE';
SET 'execution.checkpointing.timeout' = '10min';
SET 'state.backend' = 'rocksdb';
SET 'state.checkpoints.dir' = 's3a://warehouse/checkpoints';

-- =====================================================
-- STEP 2: Create Simple Test Tables
-- =====================================================

-- Create Kafka source for demographics
CREATE TABLE kafka_demographics_simple (
    id INT,
    name STRING,
    age INT,
    city STRING,
    `op` STRING,
    `ts_ms` BIGINT,
    proc_time AS PROCTIME()
) WITH (
    'connector' = 'kafka',
    'topic' = 'demographics_server.public.demographics',
    'properties.bootstrap.servers' = 'kafka:9092',
    'properties.group.id' = 'flink-test-consumer',
    'scan.startup.mode' = 'earliest-offset',
    'format' = 'debezium-json'
);

-- Create simple Iceberg table using default catalog
CREATE TABLE demographics_with_checkpointing (
    id INT,
    name STRING,
    age INT,
    city STRING,
    operation_type STRING,
    change_timestamp BIGINT,
    processing_time TIMESTAMP(3),
    PRIMARY KEY (id) NOT ENFORCED
) WITH (
    'connector' = 'iceberg',
    'catalog-impl' = 'org.apache.iceberg.nessie.NessieCatalog',
    'uri' = 'http://nessie:19120/api/v1',
    'ref' = 'main',
    'warehouse' = 's3a://warehouse/',
    'io-impl' = 'org.apache.iceberg.aws.s3.S3FileIO',
    's3.endpoint' = 'http://minioserver:9000',
    's3.path-style-access' = 'true',
    'write.format.default' = 'parquet',
    'write.target-file-size-bytes' = '67108864'
);

-- =====================================================
-- STEP 3: Start Streaming with Checkpointing
-- =====================================================
INSERT INTO demographics_with_checkpointing
SELECT 
    id,
    name,
    age,
    city,
    COALESCE(`op`, 'c') as operation_type,
    `ts_ms` as change_timestamp,
    CURRENT_TIMESTAMP as processing_time
FROM kafka_demographics_simple
WHERE `op` IN ('c', 'u', 'd') OR `op` IS NULL; 