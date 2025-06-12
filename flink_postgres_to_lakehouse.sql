-- ===== FLINK SQL: POSTGRES CDC TO LAKEHOUSE =====
-- Direct stream from PostgreSQL to MinIO lakehouse using postgres-cdc

-- 1. Create PostgreSQL CDC source table
CREATE TABLE demographics_postgres_source (
    id INT,
    city STRING,
    population BIGINT,
    created_at TIMESTAMP(3),
    PRIMARY KEY (id) NOT ENFORCED
) WITH (
    'connector' = 'postgres-cdc',
    'hostname' = 'postgres',
    'port' = '5432',
    'username' = 'admin',
    'password' = 'admin123',
    'database-name' = 'bigdata_db',
    'schema-name' = 'public',
    'table-name' = 'demographics'
);

-- 2. Create MinIO S3 sink table for lakehouse
CREATE TABLE demographics_lakehouse_sink (
    id INT,
    city STRING,
    population BIGINT,
    created_at TIMESTAMP(3),
    processing_time TIMESTAMP(3)
) WITH (
    'connector' = 'filesystem',
    'path' = 's3a://lakehouse/demographics',
    'format' = 'parquet'
);

-- 3. Stream data from PostgreSQL CDC to lakehouse
INSERT INTO demographics_lakehouse_sink
SELECT 
    id,
    city,
    population,
    created_at,
    CURRENT_TIMESTAMP as processing_time
FROM demographics_postgres_source; 