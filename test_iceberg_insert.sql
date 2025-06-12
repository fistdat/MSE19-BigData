-- Simple Lakehouse Streaming Test
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

-- Step 2: Use Nessie catalog and database
USE CATALOG nessie_catalog;
USE cdc_db;

-- Step 3: Insert test data into Iceberg table
INSERT INTO citizen_cdc VALUES
(1, 'Alice Johnson', 28, 'New York', 'alice@email.com', '555-0101', TIMESTAMP '2024-01-15 10:30:00', TIMESTAMP '2024-01-15 10:30:00', 'INSERT', TIMESTAMP '2024-01-15 10:30:00'),
(2, 'Bob Smith', 35, 'Los Angeles', 'bob@email.com', '555-0102', TIMESTAMP '2024-01-15 11:00:00', TIMESTAMP '2024-01-15 11:00:00', 'INSERT', TIMESTAMP '2024-01-15 11:00:00'),
(3, 'Carol Davis', 42, 'Chicago', 'carol@email.com', '555-0103', TIMESTAMP '2024-01-15 11:30:00', TIMESTAMP '2024-01-15 11:30:00', 'INSERT', TIMESTAMP '2024-01-15 11:30:00');

-- Step 4: Verify data
SELECT COUNT(*) as total_records FROM citizen_cdc;
SELECT * FROM citizen_cdc ORDER BY id; 