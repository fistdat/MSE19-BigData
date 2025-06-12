-- Simple Iceberg Setup - Using Hadoop Configuration
-- Step 1: Create Iceberg Catalog (credentials from core-site.xml)
CREATE CATALOG iceberg_catalog WITH (
    'type' = 'iceberg',
    'catalog-type' = 'hadoop',
    'warehouse' = 's3a://lakehouse/warehouse',
    'property-version' = '1'
);

-- Step 2: Use the catalog
USE CATALOG iceberg_catalog;

-- Step 3: Create Iceberg table
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

-- Step 4: Verify table creation
SHOW TABLES;
DESCRIBE citizen_cdc; 