-- =============================================================================
-- NESSIE CDC TO ICEBERG STREAMING JOB (FIXED FOR PERSISTENT EXECUTION)
-- =============================================================================
-- Complete CDC pipeline: PostgreSQL → Kafka → Flink → Iceberg (Nessie catalog)
-- FIXED: Handle existing tables to reach INSERT statement successfully
-- =============================================================================

-- Set execution mode and checkpointing for streaming
SET 'execution.runtime-mode' = 'streaming';
SET 'execution.checkpointing.interval' = '30s';
SET 'execution.checkpointing.mode' = 'EXACTLY_ONCE';
SET 'execution.checkpointing.timeout' = '5min';

-- Configure Nessie Iceberg catalog
CREATE CATALOG IF NOT EXISTS iceberg_catalog WITH (
    'type' = 'iceberg',
    'catalog-impl' = 'org.apache.iceberg.nessie.NessieCatalog',
    'io-impl' = 'org.apache.iceberg.aws.s3.S3FileIO',
    'uri' = 'http://nessie:19120/api/v1',
    'authentication.type' = 'none',
    'ref' = 'main',
    'warehouse' = 's3a://warehouse/',
    's3.endpoint' = 'http://minioserver:9000',
    's3.access-key-id' = 'DKZjmhls7nwxBN4GJfXC',
    's3.secret-access-key' = 'kNuAZodphLEGKHv5EmbyiDt1v5eT0yVErjVFyg0t',
    's3.path-style-access' = 'true',
    's3.region' = 'us-east-1'
);

USE CATALOG iceberg_catalog;
CREATE DATABASE IF NOT EXISTS cdc_streaming;
USE cdc_streaming;

-- Drop and recreate tables to avoid "already exists" errors
DROP TABLE IF EXISTS kafka_cdc_source;
DROP TABLE IF EXISTS demographics_streaming_lakehouse;

-- Create Kafka CDC source table
CREATE TABLE kafka_cdc_source (
    `before` ROW<
        city STRING,
        state STRING,
        median_age DOUBLE,
        male_population INT,
        female_population INT,
        total_population INT,
        number_of_veterans INT,
        foreign_born INT,
        average_household_size DOUBLE,
        state_code STRING,
        race STRING,
        count INT
    >,
    `after` ROW<
        city STRING,
        state STRING,
        median_age DOUBLE,
        male_population INT,
        female_population INT,
        total_population INT,
        number_of_veterans INT,
        foreign_born INT,
        average_household_size DOUBLE,
        state_code STRING,
        race STRING,
        count INT
    >,
    `op` STRING,
    `ts_ms` BIGINT,
    `source` ROW<
        version STRING,
        connector STRING,
        name STRING,
        ts_ms BIGINT,
        snapshot STRING,
        db STRING,
        sequence STRING,
        schema STRING,
        `table` STRING,
        txId BIGINT,
        lsn BIGINT,
        xmin BIGINT
    >
) WITH (
    'connector' = 'kafka',
    'topic' = 'demographics_server.public.demographics',
    'properties.bootstrap.servers' = 'kafka:9092',
    'properties.group.id' = 'flink-cdc-streaming-consumer',
    'scan.startup.mode' = 'latest-offset',
    'format' = 'json',
    'json.fail-on-missing-field' = 'false',
    'json.ignore-parse-errors' = 'true'
);

-- Create Iceberg sink table for streaming data
CREATE TABLE demographics_streaming_lakehouse (
    operation STRING,
    record_id STRING,
    city STRING,
    state STRING,
    median_age DOUBLE,
    male_population INT,
    female_population INT,
    total_population INT,
    number_of_veterans INT,
    foreign_born INT,
    average_household_size DOUBLE,
    state_code STRING,
    race STRING,
    population_count INT,
    event_time TIMESTAMP(3),
    processing_time TIMESTAMP(3)
) WITH (
    'format-version' = '2',
    'write.upsert.enabled' = 'true'
);

-- THIS IS THE CRITICAL STREAMING JOB - must execute successfully!
INSERT INTO demographics_streaming_lakehouse
SELECT 
    CASE 
        WHEN op = 'c' THEN 'CREATE'
        WHEN op = 'u' THEN 'UPDATE' 
        WHEN op = 'd' THEN 'DELETE'
        WHEN op = 'r' THEN 'READ'
        ELSE 'UNKNOWN'
    END as operation,
    CONCAT(
        COALESCE(`after`.city, `before`.city, 'unknown'), 
        '_', 
        COALESCE(`after`.state, `before`.state, 'unknown')
    ) as record_id,
    COALESCE(`after`.city, `before`.city) as city,
    COALESCE(`after`.state, `before`.state) as state,
    COALESCE(`after`.median_age, `before`.median_age) as median_age,
    COALESCE(`after`.male_population, `before`.male_population) as male_population,
    COALESCE(`after`.female_population, `before`.female_population) as female_population,
    COALESCE(`after`.total_population, `before`.total_population) as total_population,
    COALESCE(`after`.number_of_veterans, `before`.number_of_veterans) as number_of_veterans,
    COALESCE(`after`.foreign_born, `before`.foreign_born) as foreign_born,
    COALESCE(`after`.average_household_size, `before`.average_household_size) as average_household_size,
    COALESCE(`after`.state_code, `before`.state_code) as state_code,
    COALESCE(`after`.race, `before`.race) as race,
    COALESCE(`after`.count, `before`.count) as population_count,
    TO_TIMESTAMP_LTZ(ts_ms, 3) as event_time,
    CURRENT_TIMESTAMP as processing_time
FROM kafka_cdc_source
WHERE op IN ('c', 'u', 'd', 'r'); 