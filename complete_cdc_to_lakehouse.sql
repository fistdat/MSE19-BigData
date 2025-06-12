-- Complete CDC to Lakehouse - Working Version
-- Based on successful examples and fixing computed columns issue

-- =====================================================
-- STEP 1: Configure Checkpointing (CRITICAL!)
-- =====================================================
SET 'execution.checkpointing.interval' = '60sec';
SET 'execution.checkpointing.mode' = 'EXACTLY_ONCE';
SET 'state.backend' = 'rocksdb';
SET 'state.checkpoints.dir' = 's3a://warehouse/checkpoints';

-- =====================================================
-- STEP 2: Create Nessie Catalog
-- =====================================================
CREATE CATALOG nessie_catalog WITH (
    'type' = 'iceberg',
    'catalog-impl' = 'org.apache.iceberg.nessie.NessieCatalog',
    'io-impl' = 'org.apache.iceberg.aws.s3.S3FileIO',
    'uri' = 'http://nessie:19120/api/v1',
    'authentication.type' = 'none',
    'ref' = 'main',
    'client.assume-role.region' = 'us-east-1',
    'warehouse' = 's3://warehouse',
    's3.endpoint' = 'http://minioserver:9000',
    's3.access-key-id' = 'DKZjmhls7nwxBN4GJfXC',
    's3.secret-access-key' = 'kNuAZodphLEGKHv5EmbyiDt1v5eT0yVErjVFyg0t',
    's3.path-style-access' = 'true'
);

USE CATALOG nessie_catalog;
CREATE DATABASE IF NOT EXISTS lakehouse;
USE lakehouse;

-- =====================================================
-- STEP 3: Create Kafka Source Table (No computed columns)
-- =====================================================
CREATE TABLE kafka_demographics_source (
    `before` ROW<
        city STRING,
        state STRING,
        median_age DOUBLE,
        male_population BIGINT,
        female_population BIGINT,
        total_population BIGINT,
        number_of_veterans BIGINT,
        foreign_born BIGINT,
        average_household_size DOUBLE,
        state_code STRING,
        race STRING,
        population_count BIGINT
    >,
    `after` ROW<
        city STRING,
        state STRING,
        median_age DOUBLE,
        male_population BIGINT,
        female_population BIGINT,
        total_population BIGINT,
        number_of_veterans BIGINT,
        foreign_born BIGINT,
        average_household_size DOUBLE,
        state_code STRING,
        race STRING,
        population_count BIGINT
    >,
    `op` STRING,
    `ts_ms` BIGINT
) WITH (
    'connector' = 'kafka',
    'topic' = 'demographics_server.public.demographics',
    'properties.bootstrap.servers' = 'kafka:9092',
    'scan.startup.mode' = 'earliest-offset',
    'format' = 'debezium-json'
);

-- =====================================================
-- STEP 4: Create Iceberg Table with CREATE TABLE AS SELECT
-- This pattern creates actual data files in MinIO!
-- =====================================================
CREATE TABLE demographics_lakehouse WITH (
    'write.format.default' = 'parquet',
    'write.parquet.compression-codec' = 'snappy'
)
AS SELECT 
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
    `op` as operation_type,
    `ts_ms` as event_timestamp_ms
FROM kafka_demographics_source
WHERE `op` IN ('c', 'u', 'r'); 