-- Direct Iceberg Test - Insert data directly to verify lakehouse
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
CREATE DATABASE IF NOT EXISTS final_test;
USE final_test;

-- Step 3: Create Iceberg table
CREATE TABLE demographics_test (
    city STRING,
    state STRING,
    population BIGINT,
    test_timestamp TIMESTAMP(3)
);

-- Step 4: Insert test data
INSERT INTO demographics_test VALUES
('Test City 1', 'Test State 1', 100000, CURRENT_TIMESTAMP),
('Test City 2', 'Test State 2', 200000, CURRENT_TIMESTAMP),
('Test City 3', 'Test State 3', 300000, CURRENT_TIMESTAMP);

-- Step 5: Query results
SELECT COUNT(*) as total_records FROM demographics_test;
SELECT * FROM demographics_test; 