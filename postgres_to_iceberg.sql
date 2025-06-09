-- Định nghĩa source table từ PostgreSQL với CDC
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
    'database-name' = 'demographics', -- database chính
    'schema-name' = 'public',
    'table-name' = 'demographics',
    'slot.name' = 'flink_slot',
    'publication.name' = 'demographics_publication'
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
    count INT,
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
    'write.format.default' = 'parquet'
);

-- Pipeline để ingest dữ liệu
INSERT INTO iceberg_demographics
SELECT * FROM postgres_demographics;
