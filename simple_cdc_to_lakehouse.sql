-- Simple CDC to Lakehouse Streaming
-- =================================

-- Step 1: Create a simple JSON source table for CDC messages
CREATE TABLE cdc_source (
    message STRING
) WITH (
    'connector' = 'kafka',
    'topic' = 'demographics_server.public.demographics',
    'properties.bootstrap.servers' = 'kafka:9092',
    'properties.group.id' = 'flink-simple-cdc-consumer',
    'scan.startup.mode' = 'earliest-offset',
    'format' = 'raw'
);

-- Step 2: Create filesystem sink for lakehouse
CREATE TABLE lakehouse_sink (
    id INT,
    city STRING,
    population INT,
    created_at TIMESTAMP(3),
    cdc_operation STRING,
    processing_time TIMESTAMP(3)
) WITH (
    'connector' = 'filesystem',
    'path' = 's3://lakehouse/demographics/',
    'format' = 'json',
    's3.endpoint' = 'http://minioserver:9000',
    's3.access-key-id' = 'minioadmin',
    's3.secret-access-key' = 'minioadmin123',
    's3.path-style-access' = 'true'
);

-- Step 3: Test data insert
INSERT INTO lakehouse_sink VALUES 
(1, 'Test City', 100000, CURRENT_TIMESTAMP, 'INSERT', CURRENT_TIMESTAMP); 