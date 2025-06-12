-- Flink SQL CDC Job Configuration
SET 'execution.checkpointing.interval' = '10s';
SET 'execution.checkpointing.mode' = 'EXACTLY_ONCE';
SET 'table.exec.source.idle-timeout' = '30s';

-- S3/MinIO Configuration
SET 's3.endpoint' = 'http://minioserver:9000';
SET 's3.access-key' = 'minioadmin';
SET 's3.secret-key' = 'minioadmin';
SET 's3.path.style.access' = 'true';

-- Create CDC Source Table
CREATE TABLE postgres_demographics (
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
    count INT
) WITH (
    'connector' = 'postgres-cdc',
    'hostname' = 'postgres',
    'port' = '5432',
    'username' = 'cdc_user',
    'password' = 'cdc_password',
    'database-name' = 'demographics',
    'schema-name' = 'public',
    'table-name' = 'demographics',
    'slot.name' = 'flink_slot',
    'publication.name' = 'demographics_publication',
    'decoding.plugin.name' = 'pgoutput'
);

-- Create Iceberg Sink Table
CREATE TABLE iceberg_demographics (
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
    ingestion_time TIMESTAMP(3),
    PRIMARY KEY (city, state, race) NOT ENFORCED
) WITH (
    'connector' = 'iceberg',
    'catalog-name' = 'lakehouse_catalog',
    'catalog-type' = 'nessie',
    'catalog-impl' = 'org.apache.iceberg.nessie.NessieCatalog',
    'nessie.uri' = 'http://nessie:19120/api/v1',
    'nessie.ref' = 'main',
    'warehouse' = 's3a://lakehouse/warehouse',
    'format-version' = '2',
    'write.format.default' = 'parquet',
    'write.upsert.enabled' = 'true',
    's3.endpoint' = 'http://minioserver:9000',
    's3.access-key-id' = 'minioadmin',
    's3.secret-access-key' = 'minioadmin',
    's3.path-style-access' = 'true'
);

-- Start CDC Pipeline
INSERT INTO iceberg_demographics
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
    CURRENT_TIMESTAMP as ingestion_time
FROM postgres_demographics;
