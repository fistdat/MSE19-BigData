-- ================================================================
-- FLINK SQL: KAFKA (DEBEZIUM) TO ICEBERG PIPELINE
-- Consume CDC events from Kafka and sink to Data Lakehouse
-- ================================================================

-- 1. Create Kafka Source Table (consuming Debezium CDC events)
CREATE TABLE kafka_demographics_source (
    city STRING,
    state STRING,
    median_age DOUBLE,
    male_population INT,
    female_population INT,
    total_population INT,
    number_of_veterans INT,
    foreign_born INT,
    average_household_size DOUBLE,
    state_code STRING,
    race STRING,
    count INT,
    __op STRING,
    __source_ts_ms BIGINT,
    __source_db STRING
) WITH (
    'connector' = 'kafka',
    'topic' = 'demographics_server.public.demographics',
    'properties.bootstrap.servers' = 'kafka:9092',
    'properties.group.id' = 'flink-demographics-consumer',
    'scan.startup.mode' = 'earliest-offset',
    'format' = 'json',
    'json.fail-on-missing-field' = 'false',
    'json.ignore-parse-errors' = 'true'
);

-- 2. Create Iceberg Sink Table in Data Lakehouse
CREATE TABLE iceberg_demographics_sink (
    city STRING,
    state STRING,
    median_age DOUBLE,
    male_population INT,
    female_population INT,
    total_population INT,
    number_of_veterans INT,
    foreign_born INT,
    average_household_size DOUBLE,
    state_code STRING,
    race STRING,
    count INT,
    cdc_operation STRING,
    cdc_timestamp TIMESTAMP(3),
    processing_time TIMESTAMP(3)
) WITH (
    'connector' = 'iceberg',
    'catalog-name' = 'nessie',
    'catalog-type' = 'nessie',
    'uri' = 'http://nessie:19120/api/v1',
    'warehouse' = 's3a://lakehouse/',
    's3.endpoint' = 'http://minioserver:9000',
    's3.access-key-id' = 'minioadmin',
    's3.secret-access-key' = 'minioadmin123',
    's3.path-style-access' = 'true',
    'catalog-database' = 'demographics_db',
    'catalog-table' = 'demographics_cdc_table',
    'write.upsert.enabled' = 'true',
    'write.merge.mode' = 'merge-on-read'
);

-- 3. Create Print Sink for Debug (Optional)
CREATE TABLE print_sink_debug (
    city STRING,
    state STRING,
    total_population INT,
    cdc_operation STRING,
    cdc_timestamp TIMESTAMP(3)
) WITH (
    'connector' = 'print'
);

-- 4. Streaming Job: Kafka CDC -> Iceberg with transformations
INSERT INTO iceberg_demographics_sink
SELECT 
    city,
    state,
    median_age,
    male_population,
    female_population,
    total_population,
    number_of_veterans,
    foreign_born,
    average_household_size,
    state_code,
    race,
    count,
    COALESCE(__op, 'u') as cdc_operation,
    TO_TIMESTAMP_LTZ(__source_ts_ms, 3) as cdc_timestamp,
    CURRENT_TIMESTAMP as processing_time
FROM kafka_demographics_source
WHERE __op IS NULL OR __op IN ('c', 'u', 'd'); -- Create, Update, Delete operations

-- 5. Debug Stream: Kafka CDC -> Print (for monitoring)
INSERT INTO print_sink_debug
SELECT 
    city,
    state,
    total_population,
    COALESCE(__op, 'unknown') as cdc_operation,
    TO_TIMESTAMP_LTZ(__source_ts_ms, 3) as cdc_timestamp
FROM kafka_demographics_source; 