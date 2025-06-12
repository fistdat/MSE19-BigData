-- Working CDC Streaming Job with Checkpointing
-- This should create data files in MinIO

-- Configure checkpointing (CRITICAL for data files!)
SET 'execution.checkpointing.interval' = '30sec';
SET 'execution.checkpointing.mode' = 'EXACTLY_ONCE';
SET 'state.backend' = 'rocksdb';
SET 'state.checkpoints.dir' = 's3a://warehouse/checkpoints';

-- Create Kafka source with Debezium format
CREATE TABLE kafka_demographics (
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
    'properties.group.id' = 'flink-cdc-group',
    'scan.startup.mode' = 'earliest-offset',
    'format' = 'debezium-json'
);

-- Create Iceberg sink table
CREATE TABLE iceberg_demographics (
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
    population_count BIGINT,
    operation STRING,
    event_time TIMESTAMP(3)
) WITH (
    'connector' = 'iceberg',
    'catalog-name' = 'nessie_catalog',
    'catalog-type' = 'rest',
    'uri' = 'http://nessie:19120/api/v1',
    'warehouse' = 's3a://warehouse',
    'io-impl' = 'org.apache.iceberg.aws.s3.S3FileIO',
    's3.endpoint' = 'http://minioserver:9000',
    's3.access-key-id' = 'DKZjmhls7nwxBN4GJfXC',
    's3.secret-access-key' = 'kNuAZodphLEGKHv5EmbyiDt1v5eT0yVErjVFyg0t',
    's3.path-style-access' = 'true'
);

-- Start streaming job with INSERT
INSERT INTO iceberg_demographics
SELECT 
    COALESCE(`after`.city, `before`.city) as city,
    COALESCE(`after`.state, `before`.state) as state,
    COALESCE(`after`.median_age, `before`.median_age) as median_age,
    COALESCE(`after`.male_population, `before`.male_population) as male_population,
    COALESCE(`after`.female_population, `before`.female_population) as female_population,
    COALESCE(`after`.total_population, `before`.total_population) as total_population,
    COALESCE(`after`.number_of_veterans, `before`.number_of_veterans) as number_of_veterans,
    COALESCE(`after`.foreign_born, `before`.foreign_born) as foreign_born,
    COALESCE(`after`.average_household_size, `before`.average_household_size) as average_household_size,
    COALESCE(`after`.state_code, `before`.state_code) as state_code,
    COALESCE(`after`.race, `before`.race) as race,
    COALESCE(`after`.`count`, `before`.`count`) as population_count,
    `op` as operation,
    TO_TIMESTAMP_LTZ(`ts_ms`, 3) as event_time
FROM kafka_demographics
WHERE `op` IN ('c', 'u', 'd', 'r'); 