-- PostgreSQL Initialization Script for Data Lakehouse
-- Cấu hình WAL (Write-Ahead Logging) cho CDC

-- Database demographics đã được tạo tự động bởi POSTGRES_DB
-- CREATE DATABASE demographics;

-- Tạo user chuyên dụng cho CDC với quyền replication
CREATE USER cdc_user WITH ENCRYPTED PASSWORD 'cdc_password';
ALTER ROLE cdc_user WITH REPLICATION;

-- Connect vào database demographics
\c demographics;

-- Cấu hình PostgreSQL parameters cho CDC
-- Lưu ý: Trong production, các parameters này nên được cấu hình trong postgresql.conf
-- Đây là cách cấu hình tạm thời trong session
ALTER SYSTEM SET wal_level = 'logical';
ALTER SYSTEM SET max_replication_slots = 10;
ALTER SYSTEM SET max_wal_senders = 10;

-- Tạo bảng demographics
CREATE TABLE IF NOT EXISTS public.demographics (
    city VARCHAR(255),
    state VARCHAR(255),
    median_age DECIMAL(5,2),
    male_population INTEGER,
    female_population INTEGER,
    total_population INTEGER,
    number_of_veterans INTEGER,
    foreign_born INTEGER,
    average_household_size DECIMAL(3,2),
    state_code VARCHAR(10),
    race VARCHAR(255),
    count INTEGER
);

-- Grant quyền cho CDC user
GRANT SELECT ON ALL TABLES IN SCHEMA public TO cdc_user;
GRANT USAGE ON SCHEMA public TO cdc_user;

-- Tạo replication slot cho CDC
SELECT pg_create_logical_replication_slot('flink_slot', 'pgoutput');

-- Tạo publication cho bảng demographics
CREATE PUBLICATION demographics_publication FOR TABLE public.demographics;

-- Load dữ liệu từ CSV
COPY public.demographics FROM '/docker-entrypoint-initdb.d/us-cities-demographics.csv' 
WITH (FORMAT csv, HEADER true, DELIMITER ',');

-- Thêm một số dữ liệu mẫu để test CDC
INSERT INTO public.demographics VALUES 
('Test City 1', 'Test State', 35.5, 4000000, 4200000, 8200000, 250000, 1800000, 2.3, 'TS', 'White', 3500000),
('Test City 2', 'Test State', 34.2, 1900000, 2000000, 3900000, 120000, 1500000, 2.8, 'TS', 'Hispanic', 1800000);

-- Thông báo completion
\echo 'PostgreSQL initialization completed with WAL logging and CDC configuration' 