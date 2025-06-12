-- Create Iceberg Table directly (Hadoop catalog limitation workaround)
-- Following Dremio CDC best practices
-- =====================================================

-- 1. Switch to Iceberg catalog (already created)
USE CATALOG iceberg_catalog;

-- 2. Create Iceberg table directly (skip database creation)
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

-- 3. Show catalog information
SHOW CATALOGS;
SHOW TABLES; 