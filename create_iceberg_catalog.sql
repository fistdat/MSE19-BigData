-- Create Iceberg Catalog with Nessie Integration
-- Following Dremio CDC best practices
-- =============================================

-- 1. Create Iceberg Catalog với Nessie
CREATE CATALOG iceberg_catalog WITH (
    'type' = 'iceberg',
    'catalog-type' = 'nessie',
    'uri' = 'http://nessie:19120/api/v1',
    'ref' = 'main',
    'warehouse' = 's3://lakehouse',
    's3.endpoint' = 'http://minioserver:9000',
    's3.access-key-id' = 'minioadmin',
    's3.secret-access-key' = 'minioadmin123',
    's3.path-style-access' = 'true'
);

-- 2. Switch to Iceberg catalog
USE CATALOG iceberg_catalog;

-- 3. Create database trong Iceberg catalog
CREATE DATABASE IF NOT EXISTS demographics_db
COMMENT 'Demographics database for CDC streaming'
WITH ('location' = 's3://lakehouse/demographics_db/');

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