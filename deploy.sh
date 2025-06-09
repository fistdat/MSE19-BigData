#!/bin/bash

# Data Lakehouse Deployment Script
# Script triển khai hệ thống Data Lakehouse với CDC

echo "🚀 Starting Data Lakehouse Deployment..."

# Step 1: Cleanup existing containers (if any)
echo "🧹 Cleaning up existing containers..."
docker compose down -v
docker system prune -f

# Step 2: Build and start all services
echo "🏗️ Building and starting all services..."
docker compose up -d --build

# Step 3: Wait for services to be ready
echo "⏳ Waiting for services to be ready..."
sleep 60

# Step 4: Check service health
echo "🔍 Checking service health..."
services=("postgres:5432" "minioserver:9000" "nessie:19120" "jobmanager:8081" "dremio:9047")

for service in "${services[@]}"; do
    IFS=':' read -r host port <<< "$service"
    echo "Checking $host:$port..."
    timeout 30 bash -c "until echo > /dev/tcp/localhost/$port; do sleep 1; done" 2>/dev/null
    if [ $? -eq 0 ]; then
        echo "✅ $host:$port is ready"
    else
        echo "❌ $host:$port is not ready"
    fi
done

# Step 5: Create MinIO bucket
echo "🪣 Creating MinIO bucket..."
docker exec minioserver mc alias set local http://localhost:9000 minioadmin minioadmin
docker exec minioserver mc mb local/lakehouse --ignore-existing

# Step 6: Wait a bit more for Flink to be fully ready
echo "⏳ Waiting for Flink to be fully ready..."
sleep 30

# Step 7: Run Flink SQL job
echo "📊 Submitting Flink SQL job for CDC pipeline..."
curl -X POST \
  http://localhost:8081/v1/sql/run \
  -H 'Content-Type: application/json' \
  -d @- << 'EOF'
{
  "sql": "CREATE TABLE postgres_demographics (city STRING, state STRING, median_age DOUBLE, male_population INT, female_population INT, total_population INT, number_of_veterans INT, foreign_born INT, average_household_size DOUBLE, state_code STRING, race STRING, count INT) WITH ('connector' = 'postgres-cdc', 'hostname' = 'postgres', 'port' = '5432', 'username' = 'cdc_user', 'password' = 'cdc_password', 'database-name' = 'demographics', 'schema-name' = 'public', 'table-name' = 'demographics', 'slot.name' = 'flink_slot', 'publication.name' = 'demographics_publication');"
}
EOF

# Wait a moment
sleep 5

curl -X POST \
  http://localhost:8081/v1/sql/run \
  -H 'Content-Type: application/json' \
  -d @- << 'EOF'
{
  "sql": "CREATE TABLE iceberg_demographics (city STRING, state STRING, median_age DOUBLE, male_population INT, female_population INT, total_population INT, number_of_veterans INT, foreign_born INT, average_household_size DOUBLE, state_code STRING, race STRING, count INT, PRIMARY KEY (city, state, race) NOT ENFORCED) WITH ('connector' = 'iceberg', 'catalog-name' = 'lakehouse_catalog', 'catalog-type' = 'nessie', 'catalog-impl' = 'org.apache.iceberg.nessie.NessieCatalog', 'nessie.uri' = 'http://nessie:19120/api/v1', 'nessie.ref' = 'main', 'warehouse' = 's3a://lakehouse/warehouse', 'format-version' = '2', 'write.format.default' = 'parquet');"
}
EOF

# Wait a moment
sleep 5

curl -X POST \
  http://localhost:8081/v1/sql/run \
  -H 'Content-Type: application/json' \
  -d @- << 'EOF'
{
  "sql": "INSERT INTO iceberg_demographics SELECT * FROM postgres_demographics;"
}
EOF

echo "🎉 Data Lakehouse deployment completed!"
echo ""
echo "📋 Access URLs:"
echo "   • Flink Web UI: http://localhost:8081"
echo "   • PostgreSQL (pgAdmin): http://localhost:5050"
echo "   • MinIO Console: http://localhost:9001"
echo "   • Dremio: http://localhost:9047"
echo "   • Apache Superset: http://localhost:8088"
echo "   • Jupyter Notebook: http://localhost:8888"
echo "   • Apache Airflow: http://localhost:8080"
echo "   • Nessie: http://localhost:19120"
echo ""
echo "🔐 Default Credentials:"
echo "   • PostgreSQL: admin/admin"
echo "   • pgAdmin: admin@admin.com/admin"
echo "   • MinIO: minioadmin/minioadmin"
echo "   • Superset: admin/admin"
echo "   • Jupyter: 123456aA@"
echo "   • Airflow: admin/admin"
echo ""
echo "🧪 To test CDC, run: ./test-cdc.sh" 