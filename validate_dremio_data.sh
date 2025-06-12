#!/bin/bash

# ===== VALIDATE DREMIO DATA ACCESS =====
# Script to test data access through Dremio after configuring sources

echo "🔍 DREMIO DATA VALIDATION TEST"
echo "=============================="

# Check if Dremio is accessible
echo "📋 1. Checking Dremio accessibility..."
if curl -s http://localhost:9047 > /dev/null; then
    echo "   ✅ Dremio UI is accessible at http://localhost:9047"
else
    echo "   ❌ Dremio UI is not accessible"
    exit 1
fi

# Check MinIO test data
echo ""
echo "📦 2. Verifying test data in MinIO..."
echo "   MinIO warehouse contents:"
docker exec minioserver mc ls -r minio/warehouse/

# Check if test file exists
if docker exec minioserver mc ls minio/warehouse/test_data/test_data.json > /dev/null 2>&1; then
    echo "   ✅ Test data file exists"
    echo "   📄 Test data content:"
    docker exec minioserver mc cat minio/warehouse/test_data/test_data.json
else
    echo "   ❌ Test data file not found"
    echo "   Creating test data file..."
    echo '{"city":"Test City","state":"Test State","median_age":35.5,"male_population":1000,"female_population":1100,"total_population":2100,"number_of_veterans":50,"foreign_born":200,"average_household_size":2.5,"state_code":"TS","race":"Test","population_count":500}' > test_data.json
    docker cp test_data.json minioserver:/tmp/
    docker exec minioserver mc cp /tmp/test_data.json minio/warehouse/test_data/
    echo "   ✅ Test data file created"
fi

echo ""
echo "🎯 3. MANUAL DREMIO TESTING INSTRUCTIONS:"
echo "=========================================="
echo ""
echo "Step 1: Open Dremio UI"
echo "   URL: http://localhost:9047"
echo "   Username: admin"
echo "   Password: admin123"
echo ""
echo "Step 2: Add MinIO S3 Source"
echo "   - Click '+ Add Source'"
echo "   - Select 'Amazon S3'"
echo "   - Source Name: minio-s3"
echo "   - AWS Access Key: DKZjmhls7nwxBN4GJfXC"
echo "   - AWS Secret Key: kNuAZodphLEGKHv5EmbyiDt1v5eT0yVErjVFyg0t"
echo "   - Endpoint: http://minioserver:9000"
echo "   - Enable 'Path Style Access': ON"
echo "   - Secure Connection: OFF"
echo "   - Click 'Save'"
echo ""
echo "Step 3: Browse and Test Data"
echo "   - Navigate to minio-s3 > warehouse > test_data"
echo "   - Click on test_data.json"
echo "   - Click 'Preview' to see data"
echo "   - Expected data:"
echo "     * city: Test City"
echo "     * state: Test State"
echo "     * median_age: 35.5"
echo "     * total_population: 2100"
echo ""
echo "Step 4: Create Dataset and Run Queries"
echo "   - Click 'Save View As...' to create a dataset"
echo "   - Name it 'test_demographics'"
echo "   - Run SQL queries from dremio_validation_queries.sql"
echo ""
echo "Step 5: Test Queries to Run:"
echo "   -- Basic query"
echo "   SELECT * FROM \"minio-s3\".\"warehouse\".\"test_data\".\"test_data.json\";"
echo ""
echo "   -- Aggregation query"
echo "   SELECT COUNT(*) as records, AVG(median_age) as avg_age"
echo "   FROM \"minio-s3\".\"warehouse\".\"test_data\".\"test_data.json\";"
echo ""
echo "   -- Data transformation"
echo "   SELECT city, state, "
echo "          ROUND(male_population * 100.0 / total_population, 2) as male_pct"
echo "   FROM \"minio-s3\".\"warehouse\".\"test_data\".\"test_data.json\";"

echo ""
echo "🔧 4. TROUBLESHOOTING:"
echo "====================="
echo ""
echo "❌ If source connection fails:"
echo "   - Verify endpoint uses container name: minioserver:9000"
echo "   - Check 'Path Style Access' is enabled"
echo "   - Verify credentials match MinIO setup"
echo ""
echo "❌ If no data appears:"
echo "   - Check MinIO console: http://localhost:9001"
echo "   - Verify test file exists in warehouse/test_data/"
echo "   - Try refreshing the source in Dremio"
echo ""
echo "❌ If queries fail:"
echo "   - Check Dremio logs: docker logs dremio"
echo "   - Verify JSON format is valid"
echo "   - Try simpler queries first"

echo ""
echo "📊 5. EXPECTED SUCCESS INDICATORS:"
echo "================================="
echo "   ✅ Source connects without errors"
echo "   ✅ Can browse warehouse/test_data folder"
echo "   ✅ Can preview test_data.json content"
echo "   ✅ Queries return expected data"
echo "   ✅ Data types are correctly inferred"
echo "   ✅ Aggregations work properly"

echo ""
echo "🔗 6. USEFUL LINKS:"
echo "=================="
echo "   Dremio UI:      http://localhost:9047"
echo "   MinIO Console:  http://localhost:9001 (admin/password)"
echo "   Validation SQL: dremio_validation_queries.sql"

echo ""
echo "✅ Validation setup complete!"
echo "   Please follow the manual testing steps above." 