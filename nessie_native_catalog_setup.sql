-- Native Nessie Catalog Setup - Following Official Documentation
-- Step 1: Create Native Nessie Catalog
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

-- Step 2: Use the catalog
USE CATALOG nessie_catalog;

-- Step 3: Create database
CREATE DATABASE IF NOT EXISTS cdc_db;
USE cdc_db;

-- Step 4: Create Iceberg table
CREATE TABLE citizen_cdc (
    id BIGINT,
    name STRING,
    age INT,
    city STRING,
    email STRING,
    phone STRING,
    created_at TIMESTAMP(3),
    updated_at TIMESTAMP(3),
    op_type STRING,
    op_ts TIMESTAMP(3)
);

-- Step 5: Verify table creation
SHOW TABLES;
DESCRIBE citizen_cdc; 