-- Test Full CDC Pipeline: PostgreSQL → Kafka → Flink → Nessie/Iceberg → MinIO
-- Step 1: Create Nessie Catalog
CREATE CATALOG nessie_catalog WITH (
    'type' = 'iceberg',
    'catalog-impl' = 'org.apache.iceberg.nessie.NessieCatalog',
    'uri' = 'http://nessie:19120/api/v1',
    'ref' = 'main',
    'warehouse' = 's3a://lakehouse/warehouse',
    'io-impl' = 'org.apache.iceberg.aws.s3.S3FileIO',
    's3.endpoint' = 'http://minioserver:9000',
    's3.access-key-id' = 'minioadmin',
    's3.secret-access-key' = 'minioadmin123',
    's3.path-style-access' = 'true',
    's3.region' = 'us-east-1',
    'authentication.type' = 'NONE'
);

-- Step 2: Use catalog and create database
USE CATALOG nessie_catalog;
CREATE DATABASE IF NOT EXISTS test_db;
USE test_db;

-- Step 3: Create Iceberg sink table
CREATE TABLE demographics_final (
    city STRING,
    state STRING,
    median_age DECIMAL(5,2),
    male_population BIGINT,
    female_population BIGINT,
    total_population BIGINT,
    number_of_veterans BIGINT,
    foreign_born BIGINT,
    average_household_size DECIMAL(3,2),
    state_code STRING,
    race STRING,
    count BIGINT,
    op_type STRING,
    op_ts TIMESTAMP(3),
    ingestion_time TIMESTAMP(3)
);

-- Step 4: Create Kafka CDC source table
CREATE TABLE kafka_demographics_source (
    city STRING,
    state STRING,
    median_age DECIMAL(5,2),
    male_population BIGINT,
    female_population BIGINT,
    total_population BIGINT,
    number_of_veterans BIGINT,
    foreign_born BIGINT,
    average_household_size DECIMAL(3,2),
    state_code STRING,
    race STRING,
    count BIGINT,
    op STRING,
    ts_ms BIGINT
) WITH (
    'connector' = 'kafka',
    'topic' = 'demographics_server.public.demographics',
    'properties.bootstrap.servers' = 'kafka:9092',
    'properties.group.id' = 'flink-test-pipeline',
    'scan.startup.mode' = 'latest-offset',
    'format' = 'debezium-json'
);

-- Step 5: Stream CDC data to Iceberg lakehouse
INSERT INTO demographics_final
SELECT 
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
    count,
    CASE op
        WHEN 'c' THEN 'INSERT'
        WHEN 'u' THEN 'UPDATE'
        WHEN 'd' THEN 'DELETE'
        WHEN 'r' THEN 'SNAPSHOT'
        ELSE 'UNKNOWN'
    END as op_type,
    TO_TIMESTAMP_LTZ(ts_ms, 3) as op_ts,
    CURRENT_TIMESTAMP as ingestion_time
FROM kafka_demographics_source
WHERE city IS NOT NULL; 