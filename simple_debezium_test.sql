-- Simple Debezium to Iceberg Test with Checkpointing
-- Using correct Debezium JSON schema

-- Configure checkpointing
SET 'execution.checkpointing.interval' = '30sec';
SET 'execution.checkpointing.mode' = 'EXACTLY_ONCE';
SET 'state.backend' = 'rocksdb';
SET 'state.checkpoints.dir' = 's3a://warehouse/checkpoints';

-- Create Kafka source with Debezium format
CREATE TABLE debezium_source (
    `before` ROW<
        city STRING,
        state STRING,
        median_age DOUBLE,
        male_population BIGINT,
        female_population BIGINT,
        total_population BIGINT,
        number_of_veterans BIGINT,
        foreign_born BIGINT,
        average_household_size DOUBLE,
        state_code STRING,
        race STRING,
        `count` BIGINT
    >,
    `after` ROW<
        city STRING,
        state STRING,
        median_age DOUBLE,
        male_population BIGINT,
        female_population BIGINT,
        total_population BIGINT,
        number_of_veterans BIGINT,
        foreign_born BIGINT,
        average_household_size DOUBLE,
        state_code STRING,
        race STRING,
        `count` BIGINT
    >,
    `op` STRING,
    `ts_ms` BIGINT,
    proc_time AS PROCTIME()
) WITH (
    'connector' = 'kafka',
    'topic' = 'demographics_server.public.demographics',
    'properties.bootstrap.servers' = 'kafka:9092',
    'properties.group.id' = 'flink-debezium-test',
    'scan.startup.mode' = 'earliest-offset',
    'format' = 'debezium-json'
);

-- Create simple Iceberg sink
CREATE TABLE demographics_simple (
    city STRING,
    state STRING,
    median_age DOUBLE,
    total_population BIGINT,
    race STRING,
    operation_type STRING,
    change_timestamp BIGINT,
    processing_time TIMESTAMP(3)
) WITH (
    'connector' = 'iceberg',
    'catalog-impl' = 'org.apache.iceberg.nessie.NessieCatalog',
    'uri' = 'http://nessie:19120/api/v1',
    'ref' = 'main',
    'warehouse' = 's3a://warehouse/',
    'io-impl' = 'org.apache.iceberg.aws.s3.S3FileIO',
    's3.endpoint' = 'http://minioserver:9000',
    's3.path-style-access' = 'true',
    'write.format.default' = 'parquet',
    'write.target-file-size-bytes' = '67108864'
);

-- Start streaming with proper Debezium handling
INSERT INTO demographics_simple
SELECT 
    COALESCE(`after`.city, `before`.city) as city,
    COALESCE(`after`.state, `before`.state) as state,
    COALESCE(`after`.median_age, `before`.median_age) as median_age,
    COALESCE(`after`.total_population, `before`.total_population) as total_population,
    COALESCE(`after`.race, `before`.race) as race,
    `op` as operation_type,
    `ts_ms` as change_timestamp,
    CURRENT_TIMESTAMP as processing_time
FROM debezium_source
WHERE `op` IN ('c', 'u', 'd', 'r'); 