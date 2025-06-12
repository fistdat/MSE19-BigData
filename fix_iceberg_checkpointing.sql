-- Fix Iceberg Data Files Issue - Enable Checkpointing
-- This script addresses the missing data files in MinIO by configuring proper Flink checkpointing

-- =====================================================
-- STEP 1: Configure Flink Checkpointing (CRITICAL!)
-- =====================================================
-- Enable checkpointing with 30-second interval for faster data flushing
SET 'execution.checkpointing.interval' = '30sec';

-- Configure checkpoint mode for exactly-once processing
SET 'execution.checkpointing.mode' = 'EXACTLY_ONCE';

-- Set checkpoint timeout
SET 'execution.checkpointing.timeout' = '10min';

-- Configure checkpoint storage (use MinIO for checkpoint storage)
SET 'state.backend' = 'rocksdb';
SET 'state.checkpoints.dir' = 's3a://warehouse/checkpoints';

-- =====================================================
-- STEP 2: Configure Iceberg Table Properties
-- =====================================================
-- Set table commit properties for better data flushing
SET 'table.exec.sink.not-null-enforcer' = 'drop';

-- Configure write properties for Iceberg
SET 'table.exec.sink.upsert-materialize' = 'none';

-- =====================================================
-- STEP 3: Drop and Recreate Tables with Proper Config
-- =====================================================

-- Drop existing problematic tables
DROP TABLE IF EXISTS nessie_catalog.final_test.demographics_test;
DROP TABLE IF EXISTS nessie_catalog.cdc_db.citizen_cdc;
DROP TABLE IF EXISTS nessie_catalog.cdc_db.citizen_lakehouse;

-- =====================================================
-- STEP 4: Create Kafka Source Table
-- =====================================================
CREATE TABLE kafka_demographics_source (
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
    'properties.group.id' = 'flink-iceberg-consumer',
    'scan.startup.mode' = 'earliest-offset',
    'format' = 'debezium-json'
);

-- =====================================================
-- STEP 5: Create Iceberg Sink Table with Optimized Properties
-- =====================================================
CREATE TABLE nessie_catalog.cdc_db.demographics_iceberg (
    id INT,
    name STRING,
    age INT,
    city STRING,
    operation_type STRING,
    change_timestamp BIGINT,
    processing_time TIMESTAMP(3),
    PRIMARY KEY (id) NOT ENFORCED
) WITH (
    'catalog-impl' = 'org.apache.iceberg.nessie.NessieCatalog',
    'uri' = 'http://nessie:19120/api/v1',
    'ref' = 'main',
    'warehouse' = 's3a://warehouse/',
    'io-impl' = 'org.apache.iceberg.aws.s3.S3FileIO',
    's3.endpoint' = 'http://minioserver:9000',
    's3.path-style-access' = 'true',
    'write.format.default' = 'parquet',
    'write.target-file-size-bytes' = '134217728',
    'write.upsert.enabled' = 'true'
);

-- =====================================================
-- STEP 6: Create Streaming INSERT with Checkpointing
-- =====================================================
INSERT INTO nessie_catalog.cdc_db.demographics_iceberg
SELECT 
    id,
    name,
    age,
    city,
    COALESCE(`op`, 'c') as operation_type,
    `ts_ms` as change_timestamp,
    CURRENT_TIMESTAMP as processing_time
FROM kafka_demographics_source
WHERE `op` IN ('c', 'u', 'd') OR `op` IS NULL;

-- =====================================================
-- VERIFICATION QUERIES
-- =====================================================
-- Check job status
-- SHOW JOBS;

-- Check table data (run after a few minutes)
-- SELECT COUNT(*) FROM nessie_catalog.cdc_db.demographics_iceberg;

-- Check Iceberg metadata
-- SELECT * FROM nessie_catalog.cdc_db.demographics_iceberg.snapshots; 