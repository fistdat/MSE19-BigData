-- =============================================================================
-- NESSIE CATALOG TEST WITH CATALOG-IMPL
-- =============================================================================
-- Based on Dremio blog: https://www.dremio.com/blog/using-flink-with-apache-iceberg-and-nessie/
-- Using catalog-impl instead of catalog-type for Nessie support
-- =============================================================================

-- Set execution mode
SET 'execution.runtime-mode' = 'streaming';

-- Configure S3A properties for MinIO
SET 'fs.s3a.endpoint' = 'http://minioserver:9000';
SET 'fs.s3a.access.key' = 'DKZjmhls7nwxBN4GJfXC';
SET 'fs.s3a.secret.key' = 'kNuAZodphLEGKHv5EmbyiDt1v5eT0yVErjVFyg0t';
SET 'fs.s3a.path.style.access' = 'true';
SET 'fs.s3a.impl' = 'org.apache.hadoop.fs.s3a.S3AFileSystem';
SET 'fs.s3a.connection.ssl.enabled' = 'false';

-- Configure Nessie Iceberg catalog using catalog-impl (NOT catalog-type)
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

-- Show databases
SHOW DATABASES;

-- Create database if not exists
CREATE DATABASE IF NOT EXISTS lakehouse;

-- Use the database
USE lakehouse;

-- Show tables
SHOW TABLES; 