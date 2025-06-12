-- Start Streaming Job with Checkpointing
-- This will create data files in MinIO

-- Configure checkpointing
SET 'execution.checkpointing.interval' = '30sec';
SET 'execution.checkpointing.mode' = 'EXACTLY_ONCE';
SET 'state.backend' = 'rocksdb';
SET 'state.checkpoints.dir' = 's3a://warehouse/checkpoints';

-- Create Kafka source
CREATE TABLE kafka_source (
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
    count BIGINT,
    `op` STRING,
    `ts_ms` BIGINT,
    proc_time AS PROCTIME()
) WITH (
    'connector' = 'kafka',
    'topic' = 'demographics_server.public.demographics',
    'properties.bootstrap.servers' = 'kafka:9092',
    'properties.group.id' = 'flink-checkpointing-test',
    'scan.startup.mode' = 'earliest-offset',
    'format' = 'debezium-json'
);

-- Create Iceberg sink
CREATE TABLE demographics_lakehouse (
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
    count BIGINT,
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

-- Start streaming
INSERT INTO demographics_lakehouse
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
    COALESCE(`op`, 'c') as operation_type,
    `ts_ms` as change_timestamp,
    CURRENT_TIMESTAMP as processing_time
FROM kafka_source
WHERE `op` IN ('c', 'u', 'd') OR `op` IS NULL; 