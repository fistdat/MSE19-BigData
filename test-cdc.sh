#!/bin/bash

# CDC Testing Script
# Script test chức năng Change Data Capture

echo "🧪 Starting CDC Testing..."

# Function to execute SQL on PostgreSQL
execute_sql() {
    docker exec -i postgres psql -U admin -d demographics -c "$1"
}

# Function to check Flink job status
check_flink_jobs() {
    echo "📊 Current Flink jobs:"
    curl -s http://localhost:8081/jobs | jq -r '.jobs[] | "Job ID: \(.id) | Status: \(.status)"'
}

# Test 1: Insert new data
echo "🔄 Test 1: Inserting new data to test CDC..."
execute_sql "INSERT INTO public.demographics VALUES ('CDC Test City', 'CDC Test State', 40.0, 50000, 52000, 102000, 5000, 15000, 2.5, 'CT', 'Mixed', 10000);"

echo "✅ New data inserted. Waiting for CDC to capture changes..."
sleep 10

# Test 2: Update existing data
echo "🔄 Test 2: Updating existing data to test CDC..."
execute_sql "UPDATE public.demographics SET total_population = total_population + 1000 WHERE city = 'CDC Test City';"

echo "✅ Data updated. Waiting for CDC to capture changes..."
sleep 10

# Test 3: Delete data
echo "🔄 Test 3: Deleting data to test CDC..."
execute_sql "DELETE FROM public.demographics WHERE city = 'Test City 1';"

echo "✅ Data deleted. Waiting for CDC to capture changes..."
sleep 10

# Check current data in PostgreSQL
echo "📊 Current data in PostgreSQL:"
execute_sql "SELECT COUNT(*) as total_records FROM public.demographics;"
execute_sql "SELECT city, state, total_population FROM public.demographics WHERE city LIKE '%Test%' OR city LIKE '%CDC%';"

# Check Flink job status
echo ""
echo "📊 Flink Jobs Status:"
check_flink_jobs

# Check data in MinIO (via Dremio if available)
echo ""
echo "📊 Checking data in Data Lakehouse..."
echo "You can verify the data has been replicated to Iceberg tables by:"
echo "1. Opening Dremio at http://localhost:9047"
echo "2. Configure connection to Nessie catalog"
echo "3. Query the iceberg_demographics table"

echo ""
echo "🔍 To manually check Iceberg data:"
echo "   1. Access MinIO Console at http://localhost:9001"
echo "   2. Check 'lakehouse' bucket"
echo "   3. Look for warehouse/demographics data"

echo ""
echo "📈 To visualize data:"
echo "   1. Access Superset at http://localhost:8088"
echo "   2. Connect to Dremio as data source"
echo "   3. Create charts from iceberg_demographics table"

echo ""
echo "✅ CDC testing completed!"
echo "💡 Monitor the Flink Web UI at http://localhost:8081 to see real-time processing metrics" 