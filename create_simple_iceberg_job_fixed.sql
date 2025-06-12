-- =============================================================================
-- SIMPLE FLINK CDC TO ICEBERG JOB (FIXED S3A CREDENTIALS)
-- =============================================================================
-- This job uses proper S3A credential configuration
-- =============================================================================

-- Set execution mode and checkpointing
SET 'execution.runtime-mode' = 'streaming';
SET 'execution.checkpointing.interval' = '60s';
SET 'execution.checkpointing.mode' = 'EXACTLY_ONCE';

-- Configure S3A properties for MinIO with proper credentials
SET 'fs.s3a.endpoint' = 'http://minioserver:9000';
SET 'fs.s3a.access.key' = 'DKZjmhls7nwxBN4GJfXC';
SET 'fs.s3a.secret.key' = 'kNuAZodphLEGKHv5EmbyiDt1v5eT0yVErjVFyg0t';
SET 'fs.s3a.path.style.access' = 'true';
SET 'fs.s3a.impl' = 'org.apache.hadoop.fs.s3a.S3AFileSystem';
SET 'fs.s3a.connection.ssl.enabled' = 'false';

-- Create Iceberg catalog using Hadoop catalog with explicit S3A config
CREATE CATALOG iceberg_catalog WITH (
    'type' = 'iceberg',
    'catalog-type' = 'hadoop',
    'warehouse' = 's3a://warehouse/iceberg/',
    'property-version' = '1',
    's3.endpoint' = 'http://minioserver:9000',
    's3.access-key-id' = 'DKZjmhls7nwxBN4GJfXC',
    's3.secret-access-key' = 'kNuAZodphLEGKHv5EmbyiDt1v5eT0yVErjVFyg0t',
    's3.path-style-access' = 'true'
);

-- Use the Iceberg catalog
USE CATALOG iceberg_catalog;

-- Create database
CREATE DATABASE IF NOT EXISTS lakehouse;
USE lakehouse;

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
    'properties.group.id' = 'flink-iceberg-consumer',
    'scan.startup.mode' = 'earliest-offset',
    'format' = 'json',
    'json.fail-on-missing-field' = 'false',
    'json.ignore-parse-errors' = 'true'
);

-- Create simple Iceberg sink table
CREATE TABLE IF NOT EXISTS demographics_lakehouse (
    operation STRING,
    city STRING,
    state STRING,
    population_count INT,
    event_time TIMESTAMP(3),
    processing_time TIMESTAMP(3)
) WITH (
    'format-version' = '2'
);

-- Show tables to verify creation
SHOW TABLES;

-- Insert simplified CDC data into Iceberg table
INSERT INTO demographics_lakehouse
SELECT 
    CASE 
        WHEN op = 'c' THEN 'CREATE'
        WHEN op = 'u' THEN 'UPDATE' 
        WHEN op = 'd' THEN 'DELETE'
        WHEN op = 'r' THEN 'READ'
        ELSE 'UNKNOWN'
    END as operation,
    COALESCE(`after`.city, `before`.city) as city,
    COALESCE(`after`.state, `before`.state) as state,
    COALESCE(`after`.count, `before`.count) as population_count,
    TO_TIMESTAMP_LTZ(ts_ms, 3) as event_time,
    CURRENT_TIMESTAMP as processing_time
FROM kafka_cdc_source
WHERE op IN ('c', 'u', 'd', 'r'); 