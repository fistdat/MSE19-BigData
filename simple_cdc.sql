-- Simple CDC Test
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

-- Test query
SELECT * FROM postgres_demographics LIMIT 3;
