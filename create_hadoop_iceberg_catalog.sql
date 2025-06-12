-- Create Iceberg Catalog with Hadoop Filesystem (Fixed S3A scheme)
-- Following Dremio CDC best practices + Internet research
-- ========================================================

-- 1. Create Iceberg Catalog với Hadoop filesystem using S3A
CREATE CATALOG iceberg_catalog WITH (
    'type' = 'iceberg',
    'catalog-type' = 'hadoop',
    'warehouse' = 's3a://lakehouse',
    'hadoop.fs.s3a.impl' = 'org.apache.hadoop.fs.s3a.S3AFileSystem',
    'hadoop.fs.s3a.endpoint' = 'http://minioserver:9000',
    'hadoop.fs.s3a.access.key' = 'minioadmin',
    'hadoop.fs.s3a.secret.key' = 'minioadmin123',
    'hadoop.fs.s3a.path.style.access' = 'true',
    'hadoop.fs.AbstractFileSystem.s3a.impl' = 'org.apache.hadoop.fs.s3a.S3A'
);

-- 2. Switch to Iceberg catalog
USE CATALOG iceberg_catalog;

-- 3. Create database trong Iceberg catalog
CREATE DATABASE IF NOT EXISTS demographics_db
COMMENT 'Demographics database for CDC streaming'
WITH ('location' = 's3a://lakehouse/demographics_db/');

-- 4. Switch to the database
USE demographics_db;

-- 5. Create Iceberg table cho CDC data
CREATE TABLE demographics (
    id INT,
    city STRING,
    population INT,
    created_at TIMESTAMP(3),
    -- Iceberg metadata columns
    _cdc_operation STRING COMMENT 'CDC operation: INSERT, UPDATE, DELETE',
    _processing_time TIMESTAMP(3) COMMENT 'Processing timestamp',
    _event_time TIMESTAMP(3) COMMENT 'Event timestamp from source'
) COMMENT 'Demographics table for CDC streaming to Iceberg'
WITH (
    'format-version' = '2',
    'write.metadata.delete-after-commit.enabled' = 'true',
    'write.metadata.previous-versions-max' = '10'
);

-- 6. Show catalog information
SHOW CATALOGS;
SHOW DATABASES;
SHOW TABLES; 