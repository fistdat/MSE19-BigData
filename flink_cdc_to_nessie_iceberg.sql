-- Flink CDC to Nessie Iceberg Streaming
-- Step 1: Create Nessie Catalog (if not exists)
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

-- Step 2: Create PostgreSQL CDC source table
CREATE TABLE postgres_citizen_source (
    id BIGINT,
    name STRING,
    age INT,
    city STRING,
    email STRING,
    phone STRING,
    created_at TIMESTAMP(3),
    updated_at TIMESTAMP(3),
    PRIMARY KEY (id) NOT ENFORCED
) WITH (
    'connector' = 'postgres-cdc',
    'hostname' = 'postgres',
    'port' = '5432',
    'username' = 'postgres',
    'password' = 'postgres',
    'database-name' = 'testdb',
    'schema-name' = 'public',
    'table-name' = 'citizen'
);

-- Step 3: Use Nessie catalog and database
USE CATALOG nessie_catalog;
USE cdc_db;

-- Step 4: Insert CDC data into Iceberg table with CDC metadata
INSERT INTO citizen_cdc
SELECT 
    id,
    name,
    age,
    city,
    email,
    phone,
    created_at,
    updated_at,
    'INSERT' as op_type,
    CURRENT_TIMESTAMP as op_ts
FROM default_catalog.default_database.postgres_citizen_source;

-- Step 5: Verify data
SELECT COUNT(*) as total_records FROM citizen_cdc;
SELECT * FROM citizen_cdc LIMIT 5; 