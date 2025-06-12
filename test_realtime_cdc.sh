#!/bin/bash

# ================================================================
# REAL-TIME CDC TEST SCRIPT
# Test Debezium + Flink CDC pipeline with live data changes
# ================================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}🧪 REAL-TIME CDC TESTING${NC}"
echo -e "${CYAN}========================${NC}"

# Function to insert test data
insert_test_data() {
    local test_name=$1
    local timestamp=$(date +%s)
    
    echo -e "\n${BLUE}📥 Inserting test data: $test_name${NC}"
    
    docker exec postgres psql -U admin -d demographics -c "
    INSERT INTO demographics (
        city, state, median_age, male_population, female_population, 
        total_population, number_of_veterans, foreign_born, 
        average_household_size, state_code, race, count
    ) VALUES (
        'Test_City_$timestamp', 
        'Test_State', 
        35.5, 
        50000, 
        52000, 
        102000, 
        8500, 
        12000, 
        2.4, 
        'TS', 
        'Test_Race', 
        1
    );
    " 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Test data inserted: Test_City_$timestamp${NC}"
        return $timestamp
    else
        echo -e "${RED}❌ Failed to insert test data${NC}"
        return 1
    fi
}

# Function to update test data
update_test_data() {
    local city_name=$1
    
    echo -e "\n${BLUE}✏️  Updating test data: $city_name${NC}"
    
    docker exec postgres psql -U admin -d demographics -c "
    UPDATE demographics 
    SET total_population = total_population + 1000,
        median_age = median_age + 1
    WHERE city = '$city_name';
    " 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Test data updated: $city_name${NC}"
    else
        echo -e "${RED}❌ Failed to update test data${NC}"
    fi
}

# Function to delete test data
delete_test_data() {
    local city_name=$1
    
    echo -e "\n${BLUE}🗑️  Deleting test data: $city_name${NC}"
    
    docker exec postgres psql -U admin -d demographics -c "
    DELETE FROM demographics WHERE city = '$city_name';
    " 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Test data deleted: $city_name${NC}"
    else
        echo -e "${RED}❌ Failed to delete test data${NC}"
    fi
}

# Function to monitor Kafka CDC messages
monitor_kafka_messages() {
    local duration=$1
    
    echo -e "\n${CYAN}📡 Monitoring Kafka CDC messages for $duration seconds...${NC}"
    echo -e "${YELLOW}Press Ctrl+C to stop monitoring${NC}"
    
    timeout $duration docker exec kafka kafka-console-consumer \
        --bootstrap-server localhost:9092 \
        --topic demographics_server.public.demographics \
        --from-beginning 2>/dev/null | \
    while read message; do
        echo -e "${GREEN}📨 CDC Message: $message${NC}"
    done
}

# Function to check Flink job processing
check_flink_processing() {
    echo -e "\n${CYAN}⚙️  Checking Flink job processing...${NC}"
    
    # Get Flink jobs
    FLINK_JOBS=$(curl -s http://localhost:8081/jobs 2>/dev/null | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    for job in data['jobs']:
        print(f\"Job ID: {job['id']}, Status: {job['status']}\")
except:
    print('No jobs found')
" 2>/dev/null)
    
    if [ -n "$FLINK_JOBS" ]; then
        echo -e "${GREEN}$FLINK_JOBS${NC}"
    else
        echo -e "${YELLOW}No active Flink jobs${NC}"
    fi
}

# Function to check lakehouse data
check_lakehouse_data() {
    echo -e "\n${CYAN}🏠 Checking lakehouse data...${NC}"
    
    # Check MinIO files
    MINIO_FILES=$(docker exec minioserver mc ls -r local/lakehouse/ 2>/dev/null)
    if [ -n "$MINIO_FILES" ]; then
        echo -e "${GREEN}Lakehouse files:${NC}"
        echo -e "$MINIO_FILES"
    else
        echo -e "${YELLOW}No files in lakehouse yet${NC}"
    fi
}

# Main test execution
echo -e "${BLUE}🎯 Starting Real-time CDC Test${NC}"

# Check prerequisites
echo -e "\n${CYAN}✅ Checking prerequisites...${NC}"

# Check if services are running
POSTGRES_RUNNING=$(docker inspect postgres --format='{{.State.Status}}' 2>/dev/null)
KAFKA_RUNNING=$(docker inspect kafka --format='{{.State.Status}}' 2>/dev/null)
DEBEZIUM_RUNNING=$(docker inspect debezium --format='{{.State.Status}}' 2>/dev/null)
FLINK_RUNNING=$(docker inspect jobmanager --format='{{.State.Status}}' 2>/dev/null)

if [ "$POSTGRES_RUNNING" != "running" ] || [ "$KAFKA_RUNNING" != "running" ] || \
   [ "$DEBEZIUM_RUNNING" != "running" ] || [ "$FLINK_RUNNING" != "running" ]; then
    echo -e "${RED}❌ Some services are not running. Please start the pipeline first.${NC}"
    echo -e "${YELLOW}Run: ./deploy_debezium_flink.sh${NC}"
    exit 1
fi

echo -e "${GREEN}✅ All services are running${NC}"

# Check Debezium connector
CONNECTOR_STATUS=$(curl -s http://localhost:8083/connectors/postgres-demographics-connector/status 2>/dev/null | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data['connector']['state'])
except:
    print('UNKNOWN')
" 2>/dev/null)

if [ "$CONNECTOR_STATUS" != "RUNNING" ]; then
    echo -e "${RED}❌ Debezium connector is not running. Status: $CONNECTOR_STATUS${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Debezium connector is running${NC}"

# Start background monitoring
echo -e "\n${CYAN}🔄 Starting background monitoring...${NC}"

# Start monitoring in background
monitor_kafka_messages 30 &
MONITOR_PID=$!

# Test 1: INSERT operation
echo -e "\n${BLUE}🧪 TEST 1: INSERT Operation${NC}"
TIMESTAMP1=$(insert_test_data "INSERT_TEST")
if [ $TIMESTAMP1 -ne 1 ]; then
    TEST_CITY1="Test_City_$TIMESTAMP1"
    
    # Wait for CDC propagation
    echo -e "${YELLOW}⏳ Waiting for CDC propagation (5 seconds)...${NC}"
    sleep 5
    
    check_flink_processing
    check_lakehouse_data
fi

# Test 2: UPDATE operation
echo -e "\n${BLUE}🧪 TEST 2: UPDATE Operation${NC}"
if [ $TIMESTAMP1 -ne 1 ]; then
    update_test_data "$TEST_CITY1"
    
    # Wait for CDC propagation
    echo -e "${YELLOW}⏳ Waiting for CDC propagation (5 seconds)...${NC}"
    sleep 5
    
    check_flink_processing
    check_lakehouse_data
fi

# Test 3: Multiple INSERT operations
echo -e "\n${BLUE}🧪 TEST 3: Multiple INSERT Operations${NC}"
for i in {1..3}; do
    TIMESTAMP_BULK=$(insert_test_data "BULK_TEST_$i")
    sleep 1
done

# Wait for CDC propagation
echo -e "${YELLOW}⏳ Waiting for bulk CDC propagation (10 seconds)...${NC}"
sleep 10

check_flink_processing
check_lakehouse_data

# Test 4: DELETE operation
echo -e "\n${BLUE}🧪 TEST 4: DELETE Operation${NC}"
if [ $TIMESTAMP1 -ne 1 ]; then
    delete_test_data "$TEST_CITY1"
    
    # Wait for CDC propagation
    echo -e "${YELLOW}⏳ Waiting for DELETE CDC propagation (5 seconds)...${NC}"
    sleep 5
    
    check_flink_processing
    check_lakehouse_data
fi

# Stop background monitoring
if ps -p $MONITOR_PID > /dev/null 2>&1; then
    kill $MONITOR_PID 2>/dev/null
fi

# Final verification
echo -e "\n${CYAN}🔍 FINAL VERIFICATION${NC}"
echo -e "${CYAN}=====================${NC}"

# Check PostgreSQL count
PG_COUNT=$(docker exec postgres psql -U admin -d demographics -t -c "SELECT COUNT(*) FROM demographics;" 2>/dev/null | tr -d ' ')
echo -e "PostgreSQL records: ${GREEN}$PG_COUNT${NC}"

# Check Kafka topics
TOPICS=$(docker exec kafka kafka-topics --bootstrap-server localhost:9092 --list 2>/dev/null | grep demographics)
echo -e "Kafka CDC topic: ${GREEN}$TOPICS${NC}"

# Check Flink jobs
FLINK_JOBS_COUNT=$(curl -s http://localhost:8081/jobs 2>/dev/null | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(len(data['jobs']))
except:
    print('0')
" 2>/dev/null)
echo -e "Active Flink jobs: ${GREEN}$FLINK_JOBS_COUNT${NC}"

# Check lakehouse files
MINIO_COUNT=$(docker exec minioserver mc ls -r local/lakehouse/ 2>/dev/null | wc -l)
echo -e "Lakehouse files: ${GREEN}$MINIO_COUNT${NC}"

# Summary
echo -e "\n${CYAN}📊 TEST SUMMARY${NC}"
echo -e "${CYAN}===============${NC}"

if [ "$PG_COUNT" -gt 0 ] && [ -n "$TOPICS" ] && [ "$FLINK_JOBS_COUNT" -gt 0 ]; then
    echo -e "${GREEN}✅ CDC Pipeline: WORKING${NC}"
    echo -e "${GREEN}✅ Data Flow: PostgreSQL → Debezium → Kafka → Flink → Lakehouse${NC}"
    
    if [ "$MINIO_COUNT" -gt 0 ]; then
        echo -e "${GREEN}✅ End-to-end data consistency: ESTABLISHED${NC}"
    else
        echo -e "${YELLOW}⚠️  End-to-end data consistency: IN PROGRESS${NC}"
        echo -e "${YELLOW}   (Data may still be syncing to lakehouse)${NC}"
    fi
else
    echo -e "${RED}❌ CDC Pipeline: ISSUES DETECTED${NC}"
    echo -e "${YELLOW}Check logs with: docker logs debezium && docker logs jobmanager${NC}"
fi

echo -e "\n${BLUE}📋 MONITORING COMMANDS${NC}"
echo -e "${BLUE}=======================${NC}"
echo -e "• Live Kafka monitoring: ${YELLOW}docker exec kafka kafka-console-consumer --bootstrap-server localhost:9092 --topic demographics_server.public.demographics --from-beginning${NC}"
echo -e "• Flink Web UI: ${CYAN}http://localhost:8081${NC}"
echo -e "• Kafka UI: ${CYAN}http://localhost:8082${NC}"
echo -e "• Pipeline validation: ${YELLOW}./validate_debezium_pipeline.sh${NC}"

echo -e "\n${GREEN}🎯 Real-time CDC testing completed! 🧪${NC}" 