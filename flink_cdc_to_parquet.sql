-- Flink CDC to Parquet Streaming (Dremio Compatible)
-- ==================================================

-- 1. Create Kafka CDC Source Table
CREATE TABLE kafka_demographics_cdc (
    -- Parse Debezium CDC message structure  
    payload ROW<
        before ROW<
            id INT,
            city STRING,
            population INT,
            created_at BIGINT
        >,
        after ROW<
            id INT,
            city STRING,
            population INT,
            created_at BIGINT
        >,
        source ROW<
            version STRING,
            connector STRING,
            name STRING,
            ts_ms BIGINT,
            snapshot STRING,
            db STRING,
            schema STRING,
            table STRING,
            txId BIGINT,
            lsn BIGINT
        >,
        op STRING,
        ts_ms BIGINT
    >
) WITH (
    'connector' = 'kafka',
    'topic' = 'demographics_server.public.demographics',
    'properties.bootstrap.servers' = 'kafka:9092',
    'properties.group.id' = 'flink-parquet-cdc-consumer',
    'scan.startup.mode' = 'earliest-offset',
    'format' = 'json'
);

-- 2. Create Parquet Sink Table in MinIO Lakehouse
CREATE TABLE lakehouse_demographics_parquet (
    id INT,
    city STRING,
    population INT,
    created_at TIMESTAMP(3),
    -- CDC metadata for tracking
    cdc_op STRING,              -- CDC operation: INSERT, UPDATE, DELETE
    cdc_ts_ms BIGINT,           -- CDC timestamp
    processing_time TIMESTAMP(3) -- Flink processing timestamp
) WITH (
    'connector' = 'filesystem',
    'path' = 's3://lakehouse/demographics_parquet/',
    'format' = 'parquet',
    
    -- S3/MinIO Configuration
    's3.endpoint' = 'http://minioserver:9000',
    's3.access-key-id' = 'minioadmin',
    's3.secret-access-key' = 'minioadmin123',
    's3.path-style-access' = 'true'
);

-- 3. Stream CDC data to Parquet (INSERT job)
INSERT INTO lakehouse_demographics_parquet
SELECT 
    -- Extract data from CDC payload
    COALESCE(payload.after.id, payload.before.id) as id,
    COALESCE(payload.after.city, payload.before.city) as city,
    COALESCE(payload.after.population, payload.before.population) as population,
    
    -- Convert timestamp
    CASE 
        WHEN payload.after.created_at IS NOT NULL THEN 
            TO_TIMESTAMP_LTZ(payload.after.created_at / 1000, 3)
        WHEN payload.before.created_at IS NOT NULL THEN 
            TO_TIMESTAMP_LTZ(payload.before.created_at / 1000, 3)
        ELSE CURRENT_TIMESTAMP
    END as created_at,
    
    -- CDC metadata
    CASE payload.op
        WHEN 'c' THEN 'INSERT'
        WHEN 'u' THEN 'UPDATE' 
        WHEN 'd' THEN 'DELETE'
        WHEN 'r' THEN 'SNAPSHOT'
        ELSE 'UNKNOWN'
    END as cdc_op,
    
    payload.ts_ms as cdc_ts_ms,
    CURRENT_TIMESTAMP as processing_time
    
FROM kafka_demographics_cdc
WHERE payload.op IN ('c', 'u', 'd', 'r')
  AND (
    payload.after.id IS NOT NULL OR 
    (payload.before.id IS NOT NULL AND payload.op = 'd')
  ); 