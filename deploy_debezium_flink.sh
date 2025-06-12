#!/bin/bash

# ================================================================
# DEPLOY DEBEZIUM + FLINK 1.18.3 CDC PIPELINE
# Complete production-grade CDC solution
# ================================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}🚀 DEPLOYING DEBEZIUM + FLINK 1.18.3 CDC PIPELINE${NC}"
echo -e "${CYAN}=================================================${NC}"

echo -e "${BLUE}Architecture: PostgreSQL → Debezium → Kafka → Flink 1.18.3 → Iceberg → MinIO${NC}"

# Function to wait for service to be ready
wait_for_service() {
    local service_name=$1
    local port=$2
    local max_attempts=30
    local attempt=1

    echo -e "${YELLOW}⏳ Waiting for $service_name to be ready on port $port...${NC}"
    
    while [ $attempt -le $max_attempts ]; do
        if curl -s http://localhost:$port > /dev/null 2>&1; then
            echo -e "${GREEN}✅ $service_name is ready!${NC}"
            return 0
        fi
        echo -e "${BLUE}   Attempt $attempt/$max_attempts - waiting...${NC}"
        sleep 10
        ((attempt++))
    done
    
    echo -e "${RED}❌ $service_name failed to start within $(($max_attempts * 10)) seconds${NC}"
    return 1
}

# Function to check container status
check_container_status() {
    local container_name=$1
    local status=$(docker inspect --format='{{.State.Status}}' $container_name 2>/dev/null)
    
    if [ "$status" = "running" ]; then
        echo -e "${GREEN}✅ $container_name: running${NC}"
        return 0
    else
        echo -e "${RED}❌ $container_name: $status${NC}"
        return 1
    fi
}

# Function to create directories
create_directories() {
    echo -e "\n${CYAN}📁 Creating Required Directories${NC}"
    mkdir -p debezium
    mkdir -p flink-sql
    echo -e "${GREEN}✅ Directories created${NC}"
}

echo -e "\n${CYAN}📋 Step 1: Pre-deployment Setup${NC}"
create_directories

# Stop existing containers if any
echo -e "\n${CYAN}🛑 Step 2: Stop Existing Containers${NC}"
docker-compose down 2>/dev/null || true
echo -e "${GREEN}✅ Existing containers stopped${NC}"

# Build Flink image with Kafka support
echo -e "\n${CYAN}🔨 Step 3: Build Flink 1.18.3 with Kafka Support${NC}"
echo -e "${YELLOW}Building Flink image with Kafka connectors...${NC}"

docker build -t flink-debezium:1.18.3 -f flink/Dockerfile.debezium flink/

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Flink 1.18.3 with Kafka support built successfully${NC}"
else
    echo -e "${RED}❌ Failed to build Flink image${NC}"
    exit 1
fi

# Update docker-compose to use Debezium architecture
echo -e "\n${CYAN}🔄 Step 4: Switch to Debezium Architecture${NC}"
cp docker-compose.yml docker-compose-backup.yml
cp docker-compose-debezium-flink.yml docker-compose.yml

# Update Flink service to use Debezium Dockerfile
sed -i 's/dockerfile: Dockerfile.1.18/dockerfile: Dockerfile.debezium/g' docker-compose.yml

echo -e "${GREEN}✅ Docker compose configuration updated${NC}"

# Start infrastructure services first
echo -e "\n${CYAN}🚀 Step 5: Start Infrastructure Services${NC}"
echo -e "${YELLOW}Starting PostgreSQL, Zookeeper, Kafka...${NC}"

docker-compose up -d postgres zookeeper kafka

echo -e "${BLUE}⏳ Waiting for infrastructure to be ready...${NC}"
sleep 20

# Check infrastructure status
echo -e "\n${BLUE}📊 Infrastructure Status:${NC}"
check_container_status "postgres"
check_container_status "zookeeper"
check_container_status "kafka"

# Start Debezium
echo -e "\n${CYAN}🔧 Step 6: Start Debezium Connect${NC}"
docker-compose up -d debezium

wait_for_service "debezium" "8083"

# Start Flink cluster
echo -e "\n${CYAN}🎯 Step 7: Start Flink 1.18.3 Cluster${NC}"
docker-compose up -d jobmanager taskmanager

wait_for_service "flink" "8081"

# Start remaining services
echo -e "\n${CYAN}🌟 Step 8: Start Remaining Services${NC}"
docker-compose up -d minioserver nessie kafka-ui

echo -e "${BLUE}⏳ Waiting for all services to be ready...${NC}"
sleep 15

# Setup MinIO bucket
echo -e "\n${CYAN}🪣 Step 9: Setup MinIO Bucket${NC}"
wait_for_service "minio" "9001"

docker exec minioserver mc alias set local http://localhost:9000 minioadmin minioadmin123
docker exec minioserver mc mb local/lakehouse 2>/dev/null || echo "Bucket already exists"
echo -e "${GREEN}✅ MinIO lakehouse bucket ready${NC}"

# Setup PostgreSQL for Debezium
echo -e "\n${CYAN}🗄️ Step 10: Setup PostgreSQL for Debezium${NC}"

# Create Debezium publication
docker exec postgres psql -U admin -d demographics -c "
DROP PUBLICATION IF EXISTS debezium_publication;
CREATE PUBLICATION debezium_publication FOR TABLE demographics;
" 2>/dev/null

echo -e "${GREEN}✅ PostgreSQL Debezium publication created${NC}"

# Register Debezium connector
echo -e "\n${CYAN}📡 Step 11: Register Debezium Connector${NC}"

sleep 10 # Wait for Debezium to be fully ready

curl -X POST \
  http://localhost:8083/connectors \
  -H 'Content-Type: application/json' \
  -d @debezium/postgres-connector.json

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Debezium connector registered successfully${NC}"
else
    echo -e "${RED}❌ Failed to register Debezium connector${NC}"
    echo -e "${YELLOW}Checking Debezium logs...${NC}"
    docker logs debezium --tail 20
fi

# Wait for connector to be ready
echo -e "${BLUE}⏳ Waiting for Debezium connector to initialize...${NC}"
sleep 15

# Check connector status
echo -e "\n${BLUE}📊 Debezium Connector Status:${NC}"
curl -s http://localhost:8083/connectors/postgres-demographics-connector/status | python3 -m json.tool

# Setup Flink tables
echo -e "\n${CYAN}🎯 Step 12: Setup Flink Tables and Streaming Job${NC}"

echo -e "${YELLOW}Creating Kafka source table...${NC}"
docker exec jobmanager /opt/flink/bin/sql-client.sh << 'EOF'
CREATE TABLE kafka_demographics_source (
    city STRING,
    state STRING,
    median_age DOUBLE,
    male_population INT,
    female_population INT,
    total_population INT,
    number_of_veterans INT,
    foreign_born INT,
    average_household_size DOUBLE,
    state_code STRING,
    race STRING,
    count INT,
    __op STRING,
    __source_ts_ms BIGINT,
    __source_db STRING
) WITH (
    'connector' = 'kafka',
    'topic' = 'demographics_server.public.demographics',
    'properties.bootstrap.servers' = 'kafka:9092',
    'properties.group.id' = 'flink-demographics-consumer',
    'scan.startup.mode' = 'earliest-offset',
    'format' = 'json',
    'json.fail-on-missing-field' = 'false',
    'json.ignore-parse-errors' = 'true'
);
QUIT;
EOF

echo -e "${YELLOW}Creating Iceberg sink table...${NC}"
docker exec jobmanager /opt/flink/bin/sql-client.sh << 'EOF'
CREATE TABLE iceberg_demographics_sink (
    city STRING,
    state STRING,
    median_age DOUBLE,
    male_population INT,
    female_population INT,
    total_population INT,
    number_of_veterans INT,
    foreign_born INT,
    average_household_size DOUBLE,
    state_code STRING,
    race STRING,
    count INT,
    cdc_operation STRING,
    cdc_timestamp TIMESTAMP(3),
    processing_time TIMESTAMP(3)
) WITH (
    'connector' = 'iceberg',
    'catalog-name' = 'nessie',
    'catalog-type' = 'nessie',
    'uri' = 'http://nessie:19120/api/v1',
    'warehouse' = 's3a://lakehouse/',
    's3.endpoint' = 'http://minioserver:9000',
    's3.access-key-id' = 'minioadmin',
    's3.secret-access-key' = 'minioadmin123',
    's3.path-style-access' = 'true',
    'catalog-database' = 'demographics_db',
    'catalog-table' = 'demographics_cdc_table'
);
QUIT;
EOF

echo -e "${GREEN}✅ Flink tables created successfully${NC}"

# Start remaining services for complete stack
echo -e "\n${CYAN}🎉 Step 13: Start Complete Stack${NC}"
docker-compose up -d

echo -e "${BLUE}⏳ Final initialization...${NC}"
sleep 10

# Deployment summary
echo -e "\n${CYAN}🎉 DEPLOYMENT COMPLETED!${NC}"
echo -e "${CYAN}======================${NC}"

echo -e "\n${GREEN}✅ Services Status:${NC}"
echo -e "📊 Total containers: $(docker ps | grep -c "Up")"

echo -e "\n${BLUE}🔗 Access URLs:${NC}"
echo -e "• Flink Web UI: ${CYAN}http://localhost:8081${NC}"
echo -e "• Kafka UI: ${CYAN}http://localhost:8082${NC}"
echo -e "• Debezium REST API: ${CYAN}http://localhost:8083${NC}"
echo -e "• MinIO Console: ${CYAN}http://localhost:9001${NC} (minioadmin/minioadmin123)"
echo -e "• pgAdmin: ${CYAN}http://localhost:5050${NC} (admin@example.com/admin123)"
echo -e "• Dremio: ${CYAN}http://localhost:9047${NC}"
echo -e "• Superset: ${CYAN}http://localhost:8088${NC}"

echo -e "\n${BLUE}📋 Next Steps:${NC}"
echo -e "1. Check Kafka topics: ${YELLOW}http://localhost:8082${NC}"
echo -e "2. Submit Flink streaming job via Web UI: ${YELLOW}http://localhost:8081${NC}"
echo -e "3. Monitor CDC with: ${YELLOW}./validate_debezium_pipeline.sh${NC}"
echo -e "4. Test real-time CDC by inserting data into PostgreSQL"

echo -e "\n${GREEN}🚀 Debezium + Flink 1.18.3 CDC Pipeline Ready! 🎯${NC}" 