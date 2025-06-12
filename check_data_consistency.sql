-- ================================================================
-- DATA CONSISTENCY CHECK SCRIPT
-- Kiểm tra tính nhất quán dữ liệu giữa PostgreSQL và Data Lakehouse
-- ================================================================

-- 1. Tạo CDC Source Table từ PostgreSQL
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
    'publication.name' = 'demographics_publication'
);

-- 2. Tạo Iceberg Sink Table trong Data Lakehouse
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
    count INT
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
    'catalog-table' = 'demographics_table'
);

-- 3. Print Sink để Debug
CREATE TABLE print_sink (
    city STRING,
    state STRING,
    total_population INT,
    data_source STRING
) WITH (
    'connector' = 'print'
);

-- 4. Streaming Job: PostgreSQL CDC -> Iceberg
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
    count
FROM postgres_demographics;

-- 5. Debug Stream: PostgreSQL CDC -> Print
INSERT INTO print_sink 
SELECT 
    city,
    state,
    total_population,
    'PostgreSQL_CDC' as data_source
FROM postgres_demographics; 