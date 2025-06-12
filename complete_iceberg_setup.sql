-- Complete Iceberg Setup - Simplified for Hadoop Catalog
-- Step 1: Set MinIO credentials (Updated)
SET 'fs.s3a.access.key' = 'DKZjmhls7nwxBN4GJfXC';
SET 'fs.s3a.secret.key' = 'kNuAZodphLEGKHv5EmbyiDt1v5eT0yVErjVFyg0t';
SET 'fs.s3a.endpoint' = 'http://minioserver:9000';
SET 'fs.s3a.path.style.access' = 'true';
SET 'fs.s3a.impl' = 'org.apache.hadoop.fs.s3a.S3AFileSystem';

-- Step 2: Create Iceberg Catalog
CREATE CATALOG iceberg_catalog WITH (
    'type' = 'iceberg',
    'catalog-type' = 'hadoop',
    'warehouse' = 's3a://lakehouse/warehouse',
    'property-version' = '1'
);

-- Step 3: Use the catalog
USE CATALOG iceberg_catalog;

-- Step 4: Create Iceberg table directly (no connector property needed in Iceberg catalog)
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

-- 7. Test insert
INSERT INTO demographics VALUES 
(999, 'Iceberg Test City', 123456, CURRENT_TIMESTAMP, 'INSERT', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP); 