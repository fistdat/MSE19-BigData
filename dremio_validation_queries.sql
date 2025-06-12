-- ================================================================
-- DREMIO DATA CONSISTENCY VALIDATION QUERIES
-- Kiểm tra tính nhất quán dữ liệu trong Dremio
-- ================================================================

-- Prerequisites:
-- 1. MinIO source configured as "minio-s3" or "datalake"
-- 2. Nessie catalog configured as "nessie-catalog" or "Nessie"
-- 3. Data streaming pipeline active

-- ================================================================
-- 1. BASIC CONNECTIVITY TESTS
-- ================================================================

-- Check available data sources
SHOW SCHEMAS;

-- List available tables in each source
SHOW TABLES IN INFORMATION_SCHEMA;

-- ================================================================
-- 2. NESSIE CATALOG VALIDATION
-- ================================================================

-- Check if Nessie catalog is accessible
SELECT * FROM INFORMATION_SCHEMA.SCHEMATA 
WHERE SCHEMA_NAME LIKE '%nessie%' OR SCHEMA_NAME LIKE '%Nessie%';

-- List tables in Nessie catalog (adjust schema name as needed)
SHOW TABLES IN "Nessie";

-- Count records in demographics table from Nessie
-- Note: Adjust the path based on your Nessie configuration
SELECT COUNT(*) as nessie_record_count
FROM "Nessie".demographics;

-- Sample data from Nessie catalog
SELECT 
    id,
    city,
    population,
    created_at
FROM "Nessie".demographics
ORDER BY created_at DESC
LIMIT 10;

-- Data distribution by city from Nessie
SELECT 
    city,
    population,
    created_at
FROM "Nessie".demographics
ORDER BY population DESC
LIMIT 10;

-- ================================================================
-- 3. MINIO S3 DIRECT ACCESS VALIDATION
-- ================================================================

-- Check MinIO/S3 source schemas
SELECT * FROM INFORMATION_SCHEMA.SCHEMATA 
WHERE SCHEMA_NAME LIKE '%minio%' OR SCHEMA_NAME LIKE '%s3%' OR SCHEMA_NAME LIKE '%datalake%';

-- List tables/files in MinIO source
SHOW TABLES IN "datalake";

-- Count records from MinIO direct access (if available)
-- Note: This might not work if data is in Iceberg format
SELECT COUNT(*) as minio_record_count
FROM "datalake".lakehouse.demographics;

-- ================================================================
-- 4. DATA QUALITY VALIDATION
-- ================================================================

-- Check for null values in critical fields
SELECT 
    COUNT(*) as total_records,
    COUNT(city) as non_null_city,
    COUNT(state) as non_null_state,
    COUNT(total_population) as non_null_population,
    COUNT(CASE WHEN total_population <= 0 THEN 1 END) as invalid_population
FROM "Nessie".demographics;

-- Check data type consistency
SELECT 
    city,
    state,
    total_population,
    median_age,
    CASE 
        WHEN total_population IS NULL THEN 'NULL_POPULATION'
        WHEN total_population <= 0 THEN 'INVALID_POPULATION'
        WHEN median_age < 0 OR median_age > 120 THEN 'INVALID_AGE'
        ELSE 'VALID'
    END as data_quality_status
FROM "Nessie".demographics
WHERE total_population IS NULL 
   OR total_population <= 0 
   OR median_age < 0 
   OR median_age > 120
LIMIT 20;

-- ================================================================
-- 5. TEMPORAL CONSISTENCY VALIDATION
-- ================================================================

-- Check data freshness - most recent records
SELECT 
    MIN(created_at) as earliest_record,
    MAX(created_at) as latest_record,
    COUNT(*) as total_records,
    COUNT(DISTINCT DATE(created_at)) as unique_dates
FROM "Nessie".demographics;

-- Records created in last 24 hours
SELECT 
    DATE(created_at) as record_date,
    COUNT(*) as records_per_day
FROM "Nessie".demographics
WHERE created_at >= CURRENT_DATE - INTERVAL '7' DAY
GROUP BY DATE(created_at)
ORDER BY record_date DESC;

-- ================================================================
-- 6. BUSINESS LOGIC VALIDATION
-- ================================================================

-- Validate population calculations
SELECT 
    city,
    state,
    male_population,
    female_population,
    total_population,
    (male_population + female_population) as calculated_total,
    ABS(total_population - (male_population + female_population)) as population_diff,
    CASE 
        WHEN ABS(total_population - (male_population + female_population)) > 100 
        THEN 'INCONSISTENT' 
        ELSE 'CONSISTENT' 
    END as population_consistency
FROM "Nessie".demographics
WHERE male_population IS NOT NULL 
  AND female_population IS NOT NULL 
  AND total_population IS NOT NULL
ORDER BY population_diff DESC
LIMIT 20;

-- Check for duplicate records
SELECT 
    city,
    state,
    COUNT(*) as duplicate_count
FROM "Nessie".demographics
GROUP BY city, state
HAVING COUNT(*) > 1
ORDER BY duplicate_count DESC
LIMIT 10;

-- ================================================================
-- 7. COMPARISON WITH EXPECTED VALUES
-- ================================================================

-- Compare with known state totals (example validation)
SELECT 
    state,
    COUNT(*) as city_count,
    SUM(total_population) as state_population,
    AVG(median_age) as avg_state_age
FROM "Nessie".demographics
GROUP BY state
ORDER BY state_population DESC
LIMIT 15;

-- ================================================================
-- 8. COMPREHENSIVE VALIDATION SUMMARY
-- ================================================================

-- Create a validation summary report
SELECT 
    'Total Records' as metric,
    CAST(COUNT(*) as VARCHAR) as value
FROM "Nessie".demographics

UNION ALL

SELECT 
    'Unique Cities' as metric,
    CAST(COUNT(DISTINCT city) as VARCHAR) as value
FROM "Nessie".demographics

UNION ALL

SELECT 
    'Unique States' as metric,
    CAST(COUNT(DISTINCT state) as VARCHAR) as value
FROM "Nessie".demographics

UNION ALL

SELECT 
    'Records with Valid Population' as metric,
    CAST(COUNT(CASE WHEN total_population > 0 THEN 1 END) as VARCHAR) as value
FROM "Nessie".demographics

UNION ALL

SELECT 
    'Latest Record Date' as metric,
    CAST(MAX(created_at) as VARCHAR) as value
FROM "Nessie".demographics

UNION ALL

SELECT 
    'Data Quality Score' as metric,
    CAST(
        ROUND(
            (COUNT(CASE WHEN total_population > 0 AND median_age BETWEEN 0 AND 120 THEN 1 END) * 100.0) / COUNT(*), 
            2
        ) as VARCHAR
    ) || '%' as value
FROM "Nessie".demographics;

-- ================================================================
-- 9. TROUBLESHOOTING QUERIES
-- ================================================================

-- If no data is found, check these:

-- 1. Check if any tables exist
SELECT 
    TABLE_SCHEMA,
    TABLE_NAME,
    TABLE_TYPE
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA NOT IN ('INFORMATION_SCHEMA', 'sys')
LIMIT 20;

-- 2. Check source configurations
SELECT * FROM sys.sources;

-- 3. If using different source names, replace "Nessie" with your actual source name:
-- Examples:
-- "nessie-catalog".demographics
-- "minio-s3".lakehouse.demographics
-- "iceberg".demographics_db.demographics_table

-- ================================================================
-- NOTES:
-- ================================================================
-- 1. Adjust source names ("Nessie", "datalake") based on your configuration
-- 2. Some queries may fail if tables don't exist yet - this is normal
-- 3. Iceberg tables may have different path structures
-- 4. Run these queries after ensuring Flink streaming jobs are active
-- ================================================================

-- Dremio Validation Queries for MinIO Data Sources
-- Execute these queries in Dremio UI after configuring sources

-- =====================================================
-- STEP 1: Basic Source Validation
-- =====================================================

-- Check available sources and schemas
SHOW SCHEMAS;

-- List all available sources
SELECT * FROM INFORMATION_SCHEMA.SCHEMATA;

-- =====================================================
-- STEP 2: MinIO S3 Source Validation
-- =====================================================

-- Browse MinIO warehouse structure (after configuring minio-s3 source)
-- This should show the test_data folder
SELECT * FROM "minio-s3"."warehouse";

-- Query the test JSON file directly
SELECT * FROM "minio-s3"."warehouse"."test_data"."test_data.json";

-- Validate JSON structure and data types
SELECT 
    city,
    state,
    median_age,
    male_population,
    female_population,
    total_population,
    TYPEOF(median_age) as median_age_type,
    TYPEOF(male_population) as population_type
FROM "minio-s3"."warehouse"."test_data"."test_data.json";

-- =====================================================
-- STEP 3: Nessie Catalog Validation (if Iceberg tables exist)
-- =====================================================

-- Check Nessie catalog content
SHOW TABLES IN "nessie-catalog";

-- If lakehouse database exists, query it
SELECT * FROM "nessie-catalog"."lakehouse";

-- If demographics table exists in Nessie
SELECT COUNT(*) as total_records 
FROM "nessie-catalog"."lakehouse"."demographics_final";

SELECT * FROM "nessie-catalog"."lakehouse"."demographics_final" 
LIMIT 10;

-- =====================================================
-- STEP 4: Data Quality Validation
-- =====================================================

-- Test aggregations on MinIO data
SELECT 
    COUNT(*) as record_count,
    AVG(median_age) as avg_median_age,
    SUM(total_population) as total_pop,
    MIN(male_population) as min_male_pop,
    MAX(female_population) as max_female_pop
FROM "minio-s3"."warehouse"."test_data"."test_data.json";

-- Test data filtering and transformations
SELECT 
    city,
    state,
    CASE 
        WHEN median_age > 40 THEN 'High'
        WHEN median_age > 30 THEN 'Medium' 
        ELSE 'Low'
    END as age_category,
    ROUND(male_population * 100.0 / total_population, 2) as male_percentage
FROM "minio-s3"."warehouse"."test_data"."test_data.json"
WHERE total_population > 0;

-- =====================================================
-- STEP 5: Performance and Metadata Tests
-- =====================================================

-- Check table metadata
DESCRIBE "minio-s3"."warehouse"."test_data"."test_data.json";

-- Test query performance with EXPLAIN
EXPLAIN PLAN FOR 
SELECT city, state, total_population 
FROM "minio-s3"."warehouse"."test_data"."test_data.json"
WHERE total_population > 1000;

-- =====================================================
-- STEP 6: Advanced Analytics Tests
-- =====================================================

-- Create a virtual dataset for reuse
-- (This would be done via Dremio UI: Save View As...)
-- Virtual Dataset Name: demographics_analysis

-- Window functions test
SELECT 
    city,
    state,
    total_population,
    ROW_NUMBER() OVER (ORDER BY total_population DESC) as population_rank,
    PERCENT_RANK() OVER (ORDER BY median_age) as age_percentile
FROM "minio-s3"."warehouse"."test_data"."test_data.json";

-- =====================================================
-- STEP 7: Error Handling and Edge Cases
-- =====================================================

-- Test with non-existent paths (should return error)
-- SELECT * FROM "minio-s3"."warehouse"."non_existent_folder";

-- Test with malformed data handling
SELECT 
    city,
    COALESCE(median_age, 0) as safe_median_age,
    CASE WHEN total_population IS NULL THEN 0 ELSE total_population END as safe_total_pop
FROM "minio-s3"."warehouse"."test_data"."test_data.json";

-- =====================================================
-- EXPECTED RESULTS SUMMARY
-- =====================================================

/*
Expected Results for Successful Validation:

1. SHOW SCHEMAS should include:
   - minio-s3 (if MinIO source configured)
   - nessie-catalog (if Nessie source configured)
   - INFORMATION_SCHEMA
   - sys

2. MinIO test data query should return:
   - city: "Test City"
   - state: "Test State" 
   - median_age: 35.5
   - total_population: 2100
   - etc.

3. Data types should be correctly inferred:
   - median_age: DOUBLE
   - populations: BIGINT
   - city/state: VARCHAR

4. Aggregations should work without errors

5. Performance should be reasonable for small test data

If any queries fail:
- Check source configuration
- Verify MinIO connectivity
- Ensure test data file exists
- Check Dremio logs for detailed errors
*/ 