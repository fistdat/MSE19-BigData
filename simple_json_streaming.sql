-- SIMPLE JSON STREAMING (Bypass debezium format dependency)
-- Using JSON format to parse Debezium messages manually

SET 'execution.runtime-mode' = 'streaming';
SET 'execution.checkpointing.interval' = '30sec';
SET 'execution.checkpointing.mode' = 'EXACTLY_ONCE';

-- Create Nessie catalog 
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

-- Simple Kafka source with raw JSON
CREATE TABLE kafka_raw_cdc (
    message STRING
) WITH (
    'connector' = 'kafka',
    'topic' = 'demographics_server.public.demographics',
    'properties.bootstrap.servers' = 'kafka:9092',
    'properties.group.id' = 'flink-simple-json-cdc',
    'scan.startup.mode' = 'latest-offset',
    'format' = 'raw'
);

-- Create Iceberg sink table
CREATE TABLE demographics_simple_lakehouse (
    raw_message STRING,
    processing_time TIMESTAMP(3)
) WITH (
    'write.format.default' = 'parquet'
);

SHOW TABLES;

-- Start simple streaming job to verify connectivity
INSERT INTO demographics_simple_lakehouse
SELECT 
    message as raw_message,
    CURRENT_TIMESTAMP as processing_time
FROM kafka_raw_cdc; 