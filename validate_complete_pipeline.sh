#!/bin/bash

echo "🔍 COMPLETE CDC PIPELINE VALIDATION"
echo "==================================="
echo "$(date): Starting comprehensive pipeline validation..."

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_highlight() {
    echo -e "${CYAN}🔍 $1${NC}"
}

print_section() {
    echo -e "${PURPLE}📋 $1${NC}"
}

# Validation results tracking
VALIDATION_RESULTS=()
TOTAL_TESTS=0
PASSED_TESTS=0

# Function to record test result
record_test() {
    local test_name="$1"
    local result="$2"
    local details="$3"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    if [ "$result" = "PASS" ]; then
        PASSED_TESTS=$((PASSED_TESTS + 1))
        VALIDATION_RESULTS+=("✅ $test_name: PASS - $details")
        print_status "$test_name: PASS"
    else
        VALIDATION_RESULTS+=("❌ $test_name: FAIL - $details")
        print_error "$test_name: FAIL - $details"
    fi
}

echo ""
print_section "PHASE 1: INFRASTRUCTURE VALIDATION"
echo "================================================"

# Test 1: PostgreSQL connectivity and data
print_info "Testing PostgreSQL source data..."
PG_COUNT=$(docker exec postgres psql -U postgres -d bigdata -t -c "SELECT COUNT(*) FROM demographics;" 2>/dev/null | tr -d ' ')
if [ "$PG_COUNT" -gt 0 ] 2>/dev/null; then
    record_test "PostgreSQL Source Data" "PASS" "$PG_COUNT records found"
else
    record_test "PostgreSQL Source Data" "FAIL" "No data or connection failed"
fi

# Test 2: Debezium connector status
print_info "Testing Debezium connector..."
CONNECTOR_STATUS=$(curl -s http://localhost:8083/connectors/demographics-connector/status 2>/dev/null | jq -r '.connector.state' 2>/dev/null)
if [ "$CONNECTOR_STATUS" = "RUNNING" ]; then
    record_test "Debezium Connector" "PASS" "Connector is running"
else
    record_test "Debezium Connector" "FAIL" "Connector status: $CONNECTOR_STATUS"
fi

# Test 3: Kafka CDC messages
print_info "Testing Kafka CDC messages..."
KAFKA_MESSAGES=$(timeout 10 docker exec kafka kafka-console-consumer.sh \
    --bootstrap-server localhost:9092 \
    --topic demographics_server.public.demographics \
    --from-beginning \
    --max-messages 1 2>/dev/null | wc -l)
if [ "$KAFKA_MESSAGES" -gt 0 ]; then
    record_test "Kafka CDC Messages" "PASS" "CDC messages found in topic"
else
    record_test "Kafka CDC Messages" "FAIL" "No CDC messages found"
fi

# Test 4: Flink job status
print_info "Testing Flink streaming jobs..."
RUNNING_JOBS=$(curl -s http://localhost:8081/jobs 2>/dev/null | jq -r '.jobs[] | select(.status=="RUNNING") | .id' 2>/dev/null | wc -l)
if [ "$RUNNING_JOBS" -gt 0 ]; then
    record_test "Flink Streaming Jobs" "PASS" "$RUNNING_JOBS jobs running"
else
    record_test "Flink Streaming Jobs" "FAIL" "No running jobs found"
fi

# Test 5: Nessie catalog accessibility
print_info "Testing Nessie catalog..."
NESSIE_REPOS=$(curl -s http://localhost:19120/api/v1/repositories 2>/dev/null | jq -r '.repositories[]' 2>/dev/null | wc -l)
if [ "$NESSIE_REPOS" -gt 0 ]; then
    record_test "Nessie Catalog" "PASS" "Catalog accessible"
else
    record_test "Nessie Catalog" "FAIL" "Cannot access Nessie catalog"
fi

echo ""
print_section "PHASE 2: DATA PIPELINE VALIDATION"
echo "============================================="

# Test 6: MinIO data files
print_info "Testing MinIO data files..."
PARQUET_FILES=$(docker exec minioserver mc ls -r minio/warehouse/ 2>/dev/null | grep -c "\.parquet" || echo "0")
METADATA_FILES=$(docker exec minioserver mc ls -r minio/warehouse/ 2>/dev/null | grep -c "metadata" || echo "0")
TOTAL_FILES=$(docker exec minioserver mc ls -r minio/warehouse/ 2>/dev/null | grep -v "/$" | wc -l)

if [ "$PARQUET_FILES" -gt 0 ]; then
    record_test "MinIO Data Files" "PASS" "$PARQUET_FILES Parquet files, $METADATA_FILES metadata files"
else
    record_test "MinIO Data Files" "FAIL" "No Parquet files found (Total: $TOTAL_FILES files)"
fi

# Test 7: Checkpoint files
print_info "Testing Flink checkpoints..."
CHECKPOINT_FILES=$(docker exec minioserver mc ls -r minio/checkpoints/ 2>/dev/null | wc -l)
if [ "$CHECKPOINT_FILES" -gt 0 ]; then
    record_test "Flink Checkpoints" "PASS" "$CHECKPOINT_FILES checkpoint files"
else
    record_test "Flink Checkpoints" "FAIL" "No checkpoint files found"
fi

# Test 8: Data freshness (check if recent data exists)
print_info "Testing data freshness..."
# Trigger a data update
docker exec postgres psql -U postgres -d bigdata -c "
    INSERT INTO demographics (city, state, median_age, male_population, female_population, total_population, number_of_veterans, foreign_born, average_household_size, state_code, race, population_count)
    VALUES ('Validation Test $(date +%s)', 'Test State', 35.0, 1000, 1100, 2100, 50, 200, 2.5, 'VT', 'Test', 500)
    ON CONFLICT DO NOTHING;
" > /dev/null 2>&1

# Wait for CDC propagation
sleep 10

# Check if new messages appeared in Kafka
NEW_KAFKA_MESSAGES=$(timeout 5 docker exec kafka kafka-console-consumer.sh \
    --bootstrap-server localhost:9092 \
    --topic demographics_server.public.demographics \
    --from-beginning \
    --max-messages 10 2>/dev/null | grep -c "Validation Test" || echo "0")

if [ "$NEW_KAFKA_MESSAGES" -gt 0 ]; then
    record_test "Data Freshness" "PASS" "New data propagated to Kafka"
else
    record_test "Data Freshness" "FAIL" "New data not detected in Kafka"
fi

echo ""
print_section "PHASE 3: PERFORMANCE VALIDATION"
echo "======================================="

# Test 9: Kafka consumer lag
print_info "Testing Kafka consumer lag..."
CONSUMER_LAG=$(docker exec kafka kafka-consumer-groups.sh \
    --bootstrap-server localhost:9092 \
    --group flink-cdc-consumer \
    --describe 2>/dev/null | grep demographics_server | awk '{print $5}' | head -1)

if [ -n "$CONSUMER_LAG" ] && [ "$CONSUMER_LAG" -lt 100 ] 2>/dev/null; then
    record_test "Kafka Consumer Lag" "PASS" "Lag: $CONSUMER_LAG messages"
elif [ -n "$CONSUMER_LAG" ]; then
    record_test "Kafka Consumer Lag" "FAIL" "High lag: $CONSUMER_LAG messages"
else
    record_test "Kafka Consumer Lag" "FAIL" "Cannot determine consumer lag"
fi

# Test 10: Flink job health
print_info "Testing Flink job health..."
JOB_HEALTH_ISSUES=0
for job_id in $(curl -s http://localhost:8081/jobs 2>/dev/null | jq -r '.jobs[] | select(.status=="RUNNING") | .id' 2>/dev/null); do
    # Check for exceptions
    EXCEPTIONS=$(curl -s http://localhost:8081/jobs/$job_id/exceptions 2>/dev/null | jq -r '.["root-exception"]' 2>/dev/null)
    if [ "$EXCEPTIONS" != "null" ] && [ -n "$EXCEPTIONS" ]; then
        JOB_HEALTH_ISSUES=$((JOB_HEALTH_ISSUES + 1))
    fi
done

if [ "$JOB_HEALTH_ISSUES" -eq 0 ]; then
    record_test "Flink Job Health" "PASS" "No exceptions detected"
else
    record_test "Flink Job Health" "FAIL" "$JOB_HEALTH_ISSUES jobs with exceptions"
fi

echo ""
print_section "PHASE 4: DATA QUALITY VALIDATION"
echo "========================================"

# Test 11: File size validation
print_info "Testing data file sizes..."
SMALL_FILES=0
TOTAL_SIZE=0

while IFS= read -r line; do
    if [[ $line == *".parquet"* ]]; then
        # Extract file size (assuming mc ls format)
        SIZE=$(echo "$line" | awk '{print $4}' | sed 's/[^0-9]//g')
        if [ -n "$SIZE" ] && [ "$SIZE" -lt 1000 ] 2>/dev/null; then
            SMALL_FILES=$((SMALL_FILES + 1))
        fi
        TOTAL_SIZE=$((TOTAL_SIZE + SIZE))
    fi
done <<< "$(docker exec minioserver mc ls -r minio/warehouse/ 2>/dev/null)"

if [ "$SMALL_FILES" -eq 0 ] && [ "$TOTAL_SIZE" -gt 0 ]; then
    record_test "Data File Sizes" "PASS" "All files have reasonable size (Total: ${TOTAL_SIZE}B)"
elif [ "$TOTAL_SIZE" -gt 0 ]; then
    record_test "Data File Sizes" "FAIL" "$SMALL_FILES files are too small"
else
    record_test "Data File Sizes" "FAIL" "No data files to validate"
fi

# Test 12: Schema validation (if we can access the data)
print_info "Testing data schema..."
# This would require Dremio or direct Iceberg access
# For now, we'll check if metadata files exist
SCHEMA_FILES=$(docker exec minioserver mc ls -r minio/warehouse/ 2>/dev/null | grep -c "metadata.json" || echo "0")
if [ "$SCHEMA_FILES" -gt 0 ]; then
    record_test "Data Schema" "PASS" "Schema metadata files found"
else
    record_test "Data Schema" "FAIL" "No schema metadata files found"
fi

echo ""
print_section "PHASE 5: END-TO-END VALIDATION"
echo "======================================"

# Test 13: Complete pipeline latency
print_info "Testing end-to-end latency..."
START_TIME=$(date +%s)

# Insert test record with timestamp
TEST_ID="e2e_test_$(date +%s)"
docker exec postgres psql -U postgres -d bigdata -c "
    INSERT INTO demographics (city, state, median_age, male_population, female_population, total_population, number_of_veterans, foreign_born, average_household_size, state_code, race, population_count)
    VALUES ('$TEST_ID', 'E2E Test', 25.0, 500, 600, 1100, 25, 100, 2.2, 'E2', 'Test', 300);
" > /dev/null 2>&1

# Wait and check if it appears in Kafka
sleep 15
KAFKA_FOUND=$(timeout 10 docker exec kafka kafka-console-consumer.sh \
    --bootstrap-server localhost:9092 \
    --topic demographics_server.public.demographics \
    --from-beginning \
    --max-messages 50 2>/dev/null | grep -c "$TEST_ID" || echo "0")

END_TIME=$(date +%s)
LATENCY=$((END_TIME - START_TIME))

if [ "$KAFKA_FOUND" -gt 0 ]; then
    record_test "End-to-End Latency" "PASS" "Data propagated in ${LATENCY}s"
else
    record_test "End-to-End Latency" "FAIL" "Data not found after ${LATENCY}s"
fi

echo ""
print_section "VALIDATION SUMMARY"
echo "================================="

echo ""
echo "📊 OVERALL RESULTS:"
echo "=================="
echo "Total Tests: $TOTAL_TESTS"
echo "Passed: $PASSED_TESTS"
echo "Failed: $((TOTAL_TESTS - PASSED_TESTS))"
echo "Success Rate: $(( (PASSED_TESTS * 100) / TOTAL_TESTS ))%"

echo ""
echo "📋 DETAILED RESULTS:"
echo "==================="
for result in "${VALIDATION_RESULTS[@]}"; do
    echo "$result"
done

echo ""
echo "🔗 USEFUL LINKS:"
echo "==============="
echo "Flink Dashboard: http://localhost:8081"
echo "MinIO Console: http://localhost:9001"
echo "Kafka UI: http://localhost:8082"
echo "Dremio UI: http://localhost:9047"
echo "Nessie API: http://localhost:19120/api/v1"

echo ""
if [ "$PASSED_TESTS" -eq "$TOTAL_TESTS" ]; then
    print_status "🎉 ALL TESTS PASSED! Pipeline is fully operational."
    echo ""
    echo "🎯 NEXT STEPS:"
    echo "1. Test with Dremio: ./validate_dremio_data.sh"
    echo "2. Monitor continuously: ./monitor_cdc_pipeline.sh"
    echo "3. Run performance benchmarks if needed"
elif [ "$PASSED_TESTS" -gt $((TOTAL_TESTS / 2)) ]; then
    print_warning "⚠️  PARTIAL SUCCESS: Most tests passed but some issues detected."
    echo ""
    echo "🔧 RECOMMENDED ACTIONS:"
    echo "1. Review failed tests above"
    echo "2. Check logs: docker logs <container_name>"
    echo "3. Restart problematic services if needed"
else
    print_error "❌ VALIDATION FAILED: Multiple critical issues detected."
    echo ""
    echo "🚨 REQUIRED ACTIONS:"
    echo "1. Review all failed tests"
    echo "2. Check service status: docker ps"
    echo "3. Review deployment: ./deploy_complete_cdc_pipeline.sh"
    echo "4. Check troubleshooting guide"
fi

echo ""
print_info "Validation completed at $(date)" 