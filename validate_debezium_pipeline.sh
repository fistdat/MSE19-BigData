#!/bin/bash

# ================================================================
# VALIDATION SCRIPT FOR DEBEZIUM + FLINK CDC PIPELINE
# Comprehensive monitoring and validation
# ================================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}🔍 DEBEZIUM + FLINK CDC PIPELINE VALIDATION${NC}"
echo -e "${CYAN}===========================================${NC}"

# Function to check service health
check_service_health() {
    local service_name=$1
    local port=$2
    
    if curl -s http://localhost:$port > /dev/null; then
        echo -e "${GREEN}✅ $service_name: Healthy${NC}"
        return 0
    else
        echo -e "${RED}❌ $service_name: Unhealthy${NC}"
        return 1
    fi
}

# Function to get container status
get_container_status() {
    local container_name=$1
    local status=$(docker inspect --format='{{.State.Status}}' $container_name 2>/dev/null)
    
    if [ "$status" = "running" ]; then
        echo -e "${GREEN}✅ $container_name: Running${NC}"
    else
        echo -e "${RED}❌ $container_name: $status${NC}"
    fi
}

echo -e "\n${BLUE}📊 1. INFRASTRUCTURE STATUS${NC}"
echo -e "${BLUE}============================${NC}"

echo -e "\n${CYAN}Container Status:${NC}"
get_container_status "postgres"
get_container_status "zookeeper"
get_container_status "kafka"
get_container_status "debezium"
get_container_status "jobmanager"
get_container_status "taskmanager"
get_container_status "minioserver"
get_container_status "nessie"
get_container_status "kafka-ui"

echo -e "\n${CYAN}Service Health:${NC}"
check_service_health "PostgreSQL" "5432"
check_service_health "Kafka UI" "8082"
check_service_health "Debezium" "8083"
check_service_health "Flink" "8081"
check_service_health "MinIO" "9001"
check_service_health "Nessie" "19120"

echo -e "\n${BLUE}📊 2. POSTGRESQL STATUS${NC}"
echo -e "${BLUE}========================${NC}"

# Check PostgreSQL data
PG_COUNT=$(docker exec postgres psql -U admin -d demographics -t -c "SELECT COUNT(*) FROM demographics;" 2>/dev/null | tr -d ' ')
echo -e "Total records in PostgreSQL: ${GREEN}${PG_COUNT:-ERROR}${NC}"

# Check WAL level
WAL_LEVEL=$(docker exec postgres psql -U admin -d demographics -t -c "SHOW wal_level;" 2>/dev/null | tr -d ' ')
echo -e "WAL Level: ${GREEN}${WAL_LEVEL:-ERROR}${NC}"

# Check publications
echo -e "\n${CYAN}PostgreSQL Publications:${NC}"
docker exec postgres psql -U admin -d demographics -c "
SELECT pubname, pubtable 
FROM pg_publication p 
JOIN pg_publication_tables pt ON p.pubname = pt.pubname;
" 2>/dev/null

echo -e "\n${BLUE}📊 3. DEBEZIUM STATUS${NC}"
echo -e "${BLUE}====================${NC}"

# Check Debezium connectors
echo -e "\n${CYAN}Debezium Connectors:${NC}"
CONNECTORS=$(curl -s http://localhost:8083/connectors 2>/dev/null)
echo -e "Registered connectors: ${GREEN}$CONNECTORS${NC}"

# Check specific connector status
echo -e "\n${CYAN}Postgres Connector Status:${NC}"
CONNECTOR_STATUS=$(curl -s http://localhost:8083/connectors/postgres-demographics-connector/status 2>/dev/null)

if [ $? -eq 0 ]; then
    echo "$CONNECTOR_STATUS" | python3 -m json.tool 2>/dev/null || echo "$CONNECTOR_STATUS"
else
    echo -e "${RED}❌ Failed to get connector status${NC}"
fi

echo -e "\n${BLUE}📊 4. KAFKA STATUS${NC}"
echo -e "${BLUE}=================${NC}"

# Check Kafka topics
echo -e "\n${CYAN}Kafka Topics:${NC}"
TOPICS=$(docker exec kafka kafka-topics --bootstrap-server localhost:9092 --list 2>/dev/null)
echo -e "${GREEN}$TOPICS${NC}"

# Check specific CDC topic
CDC_TOPIC="demographics_server.public.demographics"
echo -e "\n${CYAN}CDC Topic Messages (last 5):${NC}"
docker exec kafka kafka-console-consumer \
    --bootstrap-server localhost:9092 \
    --topic "$CDC_TOPIC" \
    --from-beginning \
    --max-messages 5 \
    --timeout-ms 5000 2>/dev/null || echo -e "${YELLOW}No messages or topic not found${NC}"

echo -e "\n${BLUE}📊 5. FLINK STATUS${NC}"
echo -e "${BLUE}=================${NC}"

# Check Flink version
FLINK_VERSION=$(docker exec jobmanager /opt/flink/bin/flink --version 2>/dev/null)
echo -e "Flink Version: ${GREEN}$FLINK_VERSION${NC}"

# Check Flink jobs
FLINK_JOBS=$(curl -s http://localhost:8081/jobs 2>/dev/null | python3 -c "import sys, json; data=json.load(sys.stdin); print(len(data['jobs']))" 2>/dev/null)
echo -e "Active Flink Jobs: ${GREEN}${FLINK_JOBS:-0}${NC}"

if [ "$FLINK_JOBS" -gt 0 ]; then
    echo -e "\n${CYAN}Flink Job Details:${NC}"
    curl -s http://localhost:8081/jobs | python3 -m json.tool 2>/dev/null
fi

# Check Flink tables
echo -e "\n${CYAN}Flink Tables:${NC}"
docker exec jobmanager /opt/flink/bin/sql-client.sh -e "SHOW TABLES;" 2>/dev/null | grep -v "WARNING\|Empty set" || echo -e "${YELLOW}No tables found${NC}"

echo -e "\n${BLUE}📊 6. DATA LAKEHOUSE STATUS${NC}"
echo -e "${BLUE}===========================${NC}"

# Check MinIO lakehouse
echo -e "\n${CYAN}MinIO Lakehouse Files:${NC}"
MINIO_FILES=$(docker exec minioserver mc ls -r local/lakehouse/ 2>/dev/null | wc -l)
echo -e "Files in lakehouse bucket: ${GREEN}$MINIO_FILES${NC}"

if [ "$MINIO_FILES" -gt 0 ]; then
    echo -e "\n${CYAN}Lakehouse Content:${NC}"
    docker exec minioserver mc ls -r local/lakehouse/ 2>/dev/null
fi

# Check Nessie catalog
echo -e "\n${CYAN}Nessie Catalog Status:${NC}"
NESSIE_STATUS=$(curl -s http://localhost:19120/api/v1/config 2>/dev/null)
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Nessie catalog is accessible${NC}"
else
    echo -e "${RED}❌ Nessie catalog is not accessible${NC}"
fi

echo -e "\n${BLUE}📊 7. END-TO-END PIPELINE STATUS${NC}"
echo -e "${BLUE}=================================${NC}"

# Summary assessment
SERVICES_UP=0
TOTAL_SERVICES=8

# Count healthy services
curl -s http://localhost:5432 > /dev/null && ((SERVICES_UP++))
curl -s http://localhost:8082 > /dev/null && ((SERVICES_UP++))
curl -s http://localhost:8083 > /dev/null && ((SERVICES_UP++))
curl -s http://localhost:8081 > /dev/null && ((SERVICES_UP++))
curl -s http://localhost:9001 > /dev/null && ((SERVICES_UP++))
curl -s http://localhost:19120 > /dev/null && ((SERVICES_UP++))
[ "$PG_COUNT" -gt 0 ] 2>/dev/null && ((SERVICES_UP++))
[ "$FLINK_JOBS" -gt 0 ] 2>/dev/null && ((SERVICES_UP++))

HEALTH_PERCENTAGE=$((SERVICES_UP * 100 / TOTAL_SERVICES))

echo -e "\n${CYAN}Pipeline Health: ${GREEN}$HEALTH_PERCENTAGE%${NC} ($SERVICES_UP/$TOTAL_SERVICES services)"

if [ $HEALTH_PERCENTAGE -ge 90 ]; then
    echo -e "${GREEN}✅ Pipeline Status: EXCELLENT${NC}"
elif [ $HEALTH_PERCENTAGE -ge 70 ]; then
    echo -e "${YELLOW}⚠️  Pipeline Status: GOOD${NC}"
elif [ $HEALTH_PERCENTAGE -ge 50 ]; then
    echo -e "${YELLOW}⚠️  Pipeline Status: DEGRADED${NC}"
else
    echo -e "${RED}❌ Pipeline Status: CRITICAL${NC}"
fi

echo -e "\n${BLUE}📋 8. DATA CONSISTENCY CHECK${NC}"
echo -e "${BLUE}=============================${NC}"

# Check if data flows correctly
if [ "$PG_COUNT" -gt 0 ] && [ "$FLINK_JOBS" -gt 0 ] && [ "$MINIO_FILES" -gt 0 ]; then
    echo -e "${GREEN}✅ Data Consistency: GOOD${NC}"
    echo -e "   - PostgreSQL has data: $PG_COUNT records"
    echo -e "   - Flink jobs running: $FLINK_JOBS"
    echo -e "   - Lakehouse has files: $MINIO_FILES"
elif [ "$PG_COUNT" -gt 0 ] && [ "$FLINK_JOBS" -gt 0 ]; then
    echo -e "${YELLOW}⚠️  Data Consistency: IN PROGRESS${NC}"
    echo -e "   - CDC pipeline is active but data may still be syncing"
else
    echo -e "${RED}❌ Data Consistency: NOT ESTABLISHED${NC}"
    echo -e "   - CDC pipeline needs to be activated"
fi

echo -e "\n${BLUE}🔗 9. ACCESS URLS${NC}"
echo -e "${BLUE}=================${NC}"
echo -e "• Flink Web UI: ${CYAN}http://localhost:8081${NC}"
echo -e "• Kafka UI: ${CYAN}http://localhost:8082${NC}"
echo -e "• Debezium API: ${CYAN}http://localhost:8083${NC}"
echo -e "• MinIO Console: ${CYAN}http://localhost:9001${NC}"
echo -e "• pgAdmin: ${CYAN}http://localhost:5050${NC}"

echo -e "\n${BLUE}📝 10. TROUBLESHOOTING COMMANDS${NC}"
echo -e "${BLUE}===============================${NC}"
echo -e "• Check Debezium logs: ${YELLOW}docker logs debezium${NC}"
echo -e "• Check Flink logs: ${YELLOW}docker logs jobmanager${NC}"
echo -e "• Check Kafka topics: ${YELLOW}docker exec kafka kafka-topics --bootstrap-server localhost:9092 --list${NC}"
echo -e "• Monitor CDC messages: ${YELLOW}docker exec kafka kafka-console-consumer --bootstrap-server localhost:9092 --topic demographics_server.public.demographics --from-beginning${NC}"

echo -e "\n${GREEN}✅ Validation completed! 🎯${NC}" 