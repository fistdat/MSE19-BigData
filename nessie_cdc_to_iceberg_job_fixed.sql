-- =============================================================================
-- NESSIE CDC TO ICEBERG LAKEHOUSE JOB (FIXED)
-- =============================================================================
-- Complete CDC pipeline: PostgreSQL → Kafka → Flink → Iceberg (Nessie catalog)
-- Using working catalog-impl syntax for Nessie integration
-- Fixed: 'count' reserved keyword renamed to 'population_count'
-- =============================================================================

-- Set execution mode and checkpointing
SET 'execution.runtime-mode' = 'streaming';
SET 'execution.checkpointing.interval' = '60s';
SET 'execution.checkpointing.mode' = 'EXACTLY_ONCE';
SET 'execution.checkpointing.timeout' = '10min';

-- Configure S3A properties for MinIO
SET 'fs.s3a.endpoint' = 'http://minioserver:9000';
SET 'fs.s3a.access.key' = 'DKZjmhls7nwxBN4GJfXC';
SET 'fs.s3a.secret.key' = 'kNuAZodphLEGKHv5EmbyiDt1v5eT0yVErjVFyg0t';
SET 'fs.s3a.path.style.access' = 'true';
SET 'fs.s3a.impl' = 'org.apache.hadoop.fs.s3a.S3AFileSystem';
SET 'fs.s3a.connection.ssl.enabled' = 'false';

-- Configure Nessie Iceberg catalog (WORKING!)
CREATE CATALOG iceberg_catalog WITH (
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
    's3.path-style-access' = 'true'
);

-- Use the Nessie catalog
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
        population_count INT
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
        population_count INT
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
    'properties.group.id' = 'flink-nessie-iceberg-consumer',
    'scan.startup.mode' = 'earliest-offset',
    'format' = 'json',
    'json.fail-on-missing-field' = 'false',
    'json.ignore-parse-errors' = 'true'
);

-- Create Nessie-backed Iceberg sink table
CREATE TABLE IF NOT EXISTS demographics_nessie_lakehouse (
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
) PARTITIONED BY (DATE_FORMAT(event_time, 'yyyy-MM-dd'))
WITH (
    'format-version' = '2',
    'write.upsert.enabled' = 'true'
);

-- Show tables to verify creation
SHOW TABLES;

-- Insert CDC data into Nessie-backed Iceberg table
INSERT INTO demographics_nessie_lakehouse
SELECT 
    CASE 
        WHEN op = 'c' THEN 'CREATE'
        WHEN op = 'u' THEN 'UPDATE' 
        WHEN op = 'd' THEN 'DELETE'
        WHEN op = 'r' THEN 'READ'
        ELSE 'UNKNOWN'
    END as operation,
    CAST(COALESCE(`after`.city, `before`.city) AS STRING) || '_' || 
    CAST(COALESCE(`after`.state, `before`.state) AS STRING) as record_id,
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
    COALESCE(`after`.population_count, `before`.population_count) as population_count,
    TO_TIMESTAMP_LTZ(ts_ms, 3) as event_time,
    CURRENT_TIMESTAMP as processing_time
FROM kafka_cdc_source
WHERE op IN ('c', 'u', 'd', 'r'); 