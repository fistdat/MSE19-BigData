-- Nessie Iceberg Setup - Using Nessie Catalog
CREATE CATALOG nessie_catalog WITH ('type' = 'iceberg', 'catalog-type' = 'rest', 'uri' = 'http://nessie:19120/api/v1', 'warehouse' = 's3a://lakehouse/warehouse', 'io-impl' = 'org.apache.iceberg.aws.s3.S3FileIO', 's3.endpoint' = 'http://minioserver:9000', 's3.access-key-id' = 'minioadmin', 's3.secret-access-key' = 'minioadmin123', 's3.path-style-access' = 'true');
USE CATALOG nessie_catalog;
CREATE NAMESPACE cdc_db;
USE cdc_db;
CREATE TABLE citizen_cdc (id BIGINT, name STRING, age INT, city STRING, email STRING, phone STRING, created_at TIMESTAMP(3), updated_at TIMESTAMP(3), op_type STRING, op_ts TIMESTAMP(3));
SHOW TABLES;
DESCRIBE citizen_cdc;
