-- Simple Flink Streaming Job for Testing
-- This job reads from Kafka CDC topic and prints to console

-- Set execution environment
SET 'execution.checkpointing.interval' = '30sec';

-- Create Kafka source table for CDC data
CREATE TABLE demographics_source (
    city STRING,
    state STRING,
    median_age DECIMAL(5,2),
    male_population INT,
    female_population INT,
    total_population INT,
    number_of_veterans INT,
    foreign_born INT,
    average_household_size DECIMAL(3,2),
    state_code STRING,
    race STRING,
    population_count INT
) WITH (
    'connector' = 'kafka',
    'topic' = 'demographics_server.public.demographics',
    'properties.bootstrap.servers' = 'kafka:9092',
    'properties.group.id' = 'flink-test-consumer',
    'scan.startup.mode' = 'earliest-offset',
    'format' = 'debezium-json'
);

-- Create print sink for testing
CREATE TABLE print_sink (
    city STRING,
    state STRING,
    total_population INT,
    processing_time TIMESTAMP(3)
) WITH (
    'connector' = 'print'
);

-- Insert streaming data to print sink
INSERT INTO print_sink
SELECT 
    city,
    state,
    total_population,
    PROCTIME() as processing_time
FROM demographics_source
WHERE total_population > 0; 