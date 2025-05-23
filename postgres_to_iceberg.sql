i-- Định nghĩa source table từ PostgreSQL
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
    'hostname' = 'postgres', -- tên container PostgreSQL
    'port' = '5432',
    'username' = 'cdc_user', -- user replication
    'password' = 'cdc_password',
    'database-name' = 'postgres',
    'schema-name' = 'public',
    'table-name' = 'demographics'
);

-- Định nghĩa sink table trên Iceberg
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
    count INT
) WITH (
    'connector' = 'iceberg',
    'catalog-name' = 'nessie',
    'catalog-type' = 'hadoop',
    'warehouse' = 's3a://lakehouse/warehouse',
    'format' = 'parquet'
);

-- Pipeline để ingest dữ liệu
INSERT INTO iceberg_demographics
SELECT * FROM postgres_demographics;
