#!/bin/bash

echo "🚀 Submitting Flink CDC Job..."

# Submit SQL to create source table
echo "📊 Creating PostgreSQL CDC source table..."
curl -X POST http://localhost:8081/v1/sql/run \
  -H 'Content-Type: application/json' \
  -d '{
    "sql": "CREATE TABLE postgres_demographics (city STRING, state STRING, median_age DOUBLE, male_population INT, female_population INT, total_population INT, number_of_veterans INT, foreign_born INT, average_household_size DOUBLE, state_code STRING, race STRING, count INT) WITH (\"connector\" = \"postgres-cdc\", \"hostname\" = \"postgres\", \"port\" = \"5432\", \"username\" = \"cdc_user\", \"password\" = \"cdc_password\", \"database-name\" = \"demographics\", \"schema-name\" = \"public\", \"table-name\" = \"demographics\", \"slot.name\" = \"flink_slot\", \"publication.name\" = \"demographics_publication\");"
  }'

echo ""
sleep 5

# Submit SQL to create sink table
echo "📊 Creating Iceberg sink table..."
curl -X POST http://localhost:8081/v1/sql/run \
  -H 'Content-Type: application/json' \
  -d '{
    "sql": "CREATE TABLE iceberg_demographics (city STRING, state STRING, median_age DOUBLE, male_population INT, female_population INT, total_population INT, number_of_veterans INT, foreign_born INT, average_household_size DOUBLE, state_code STRING, race STRING, count INT, PRIMARY KEY (city, state, race) NOT ENFORCED) WITH (\"connector\" = \"iceberg\", \"catalog-name\" = \"lakehouse_catalog\", \"catalog-type\" = \"nessie\", \"catalog-impl\" = \"org.apache.iceberg.nessie.NessieCatalog\", \"nessie.uri\" = \"http://nessie:19120/api/v1\", \"nessie.ref\" = \"main\", \"warehouse\" = \"s3a://lakehouse/warehouse\", \"format-version\" = \"2\", \"write.format.default\" = \"parquet\");"
  }'

echo ""
sleep 5

# Submit SQL to start CDC pipeline
echo "📊 Starting CDC pipeline..."
curl -X POST http://localhost:8081/v1/sql/run \
  -H 'Content-Type: application/json' \
  -d '{
    "sql": "INSERT INTO iceberg_demographics SELECT * FROM postgres_demographics;"
  }'

echo ""
echo "✅ Flink CDC job submitted successfully!"
echo "🔍 Check job status at: http://localhost:8081" 