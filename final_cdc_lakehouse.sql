-- Final CDC Lakehouse Solution - Data Files Creation
-- This will create actual Parquet data files in MinIO

-- =====================================================
-- STEP 1: Configure Checkpointing (CRITICAL!)
-- =====================================================
SET 'execution.checkpointing.interval' = '60sec';
SET 'execution.checkpointing.mode' = 'EXACTLY_ONCE';
SET 'state.backend' = 'rocksdb';
SET 'state.checkpoints.dir' = 's3a://warehouse/checkpoints';

-- =====================================================
-- STEP 2: Set AWS Environment for S3A
-- =====================================================
SET 'env.java.opts' = '-Daws.region=us-east-1';

-- =====================================================
-- STEP 3: Create Nessie Catalog with Full Configuration
-- =====================================================
CREATE CATALOG nessie_catalog WITH (
    'type' = 'iceberg',
    'catalog-impl' = 'org.apache.iceberg.nessie.NessieCatalog',
    'io-impl' = 'org.apache.iceberg.aws.s3.S3FileIO',
    'uri' = 'http://nessie:19120/api/v1',
    'authentication.type' = 'none',
    'ref' = 'main',
    'warehouse' = 's3://warehouse',
    's3.endpoint' = 'http://minioserver:9000',
    's3.access-key-id' = 'DKZjmhls7nwxBN4GJfXC',
    's3.secret-access-key' = 'kNuAZodphLEGKHv5EmbyiDt1v5eT0yVErjVFyg0t',
    's3.path-style-access' = 'true',
    's3.region' = 'us-east-1'
);

USE CATALOG nessie_catalog;
CREATE DATABASE IF NOT EXISTS lakehouse;
USE lakehouse;

-- =====================================================
-- STEP 4: Create Simple Kafka Source Table
-- =====================================================
CREATE TABLE kafka_demographics_simple (
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
) WITH (
    'connector' = 'kafka',
    'topic' = 'demographics_server.public.demographics',
    'properties.bootstrap.servers' = 'kafka:9092',
    'scan.startup.mode' = 'earliest-offset',
    'format' = 'json',
    'json.fail-on-missing-field' = 'false',
    'json.ignore-parse-errors' = 'true'
);

-- =====================================================
-- STEP 5: Create Iceberg Table with CREATE TABLE AS SELECT
-- This is the pattern that creates data files!
-- =====================================================
CREATE TABLE demographics_final WITH (
    'write.format.default' = 'parquet',
    'write.parquet.compression-codec' = 'snappy'
)
AS SELECT 
    city,
    state,
    median_age,
    male_population,
    female_population,
    total_population,
    number_of_veterans,
    foreign_born,
    average_household_size,
    state_code,
    race,
    population_count
FROM kafka_demographics_simple
WHERE city IS NOT NULL; 