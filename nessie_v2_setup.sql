CREATE CATALOG nessie_catalog WITH ('type' = 'iceberg', 'catalog-type' = 'rest', 'uri' = 'http://nessie:19120/api/v2', 'warehouse' = 's3a://lakehouse/warehouse', 'io-impl' = 'org.apache.iceberg.aws.s3.S3FileIO', 's3.endpoint' = 'http://minioserver:9000', 's3.access-key-id' = 'minioadmin', 's3.secret-access-key' = 'minioadmin123', 's3.path-style-access' = 'true');
USE CATALOG nessie_catalog;
SHOW TABLES;
