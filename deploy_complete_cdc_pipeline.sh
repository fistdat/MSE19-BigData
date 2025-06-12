#!/bin/bash

echo "🚀 COMPLETE CDC PIPELINE DEPLOYMENT"
echo "===================================="
echo "$(date): Starting comprehensive CDC pipeline deployment..."

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

# Function to check if service is running
check_service() {
    local service_name=$1
    local check_command=$2
    
    print_info "Checking $service_name..."
    if eval $check_command > /dev/null 2>&1; then
        print_status "$service_name is running"
        return 0
    else
        print_error "$service_name is not accessible"
        return 1
    fi
}

# Function to wait for service
wait_for_service() {
    local service_name=$1
    local check_command=$2
    local max_attempts=30
    local attempt=1
    
    print_info "Waiting for $service_name to be ready..."
    while [ $attempt -le $max_attempts ]; do
        if eval $check_command > /dev/null 2>&1; then
            print_status "$service_name is ready!"
            return 0
        fi
        echo "   Attempt $attempt/$max_attempts - waiting..."
        sleep 5
        ((attempt++))
    done
    
    print_error "$service_name failed to become ready after $max_attempts attempts"
    return 1
}

echo ""
echo "📋 PHASE 1: PRE-FLIGHT CHECKS"
echo "============================="

# Check all required services
SERVICES_OK=true

check_service "PostgreSQL" "docker exec postgres pg_isready -U postgres" || SERVICES_OK=false
check_service "Kafka" "docker exec kafka kafka-topics --bootstrap-server localhost:9092 --list" || SERVICES_OK=false
check_service "MinIO" "docker exec minioserver mc ls minio" || SERVICES_OK=false
check_service "Nessie" "curl -s http://localhost:19120/api/v1/repositories" || SERVICES_OK=false
check_service "Flink JobManager" "curl -s http://localhost:8081/overview" || SERVICES_OK=false
check_service "Debezium Connect" "curl -s http://localhost:8083/connectors" || SERVICES_OK=false

if [ "$SERVICES_OK" = false ]; then
    print_error "Some services are not running. Please start all services first."
    echo ""
    echo "Quick start command:"
    echo "docker-compose up -d"
    exit 1
fi

print_status "All services are running!"

echo ""
echo "📊 PHASE 2: DATA SOURCE VALIDATION"
echo "=================================="

# Check PostgreSQL data
print_info "Checking PostgreSQL data..."
PG_COUNT=$(docker exec postgres psql -U postgres -d bigdata -t -c "SELECT COUNT(*) FROM demographics;" 2>/dev/null | tr -d ' ')
if [ "$PG_COUNT" -gt 0 ]; then
    print_status "PostgreSQL has $PG_COUNT records in demographics table"
else
    print_warning "PostgreSQL demographics table is empty or not accessible"
    print_info "Loading sample data..."
    docker exec postgres psql -U postgres -d bigdata -c "
        INSERT INTO demographics (city, state, median_age, male_population, female_population, total_population, number_of_veterans, foreign_born, average_household_size, state_code, race, population_count)
        VALUES 
        ('Sample City 1', 'Sample State 1', 35.5, 1000, 1100, 2100, 50, 200, 2.5, 'SS', 'Mixed', 500),
        ('Sample City 2', 'Sample State 2', 42.3, 1500, 1600, 3100, 75, 300, 2.8, 'SS', 'Mixed', 750)
        ON CONFLICT DO NOTHING;
    " || print_warning "Could not insert sample data"
fi

# Check Debezium connector
print_info "Checking Debezium connector..."
CONNECTOR_STATUS=$(curl -s http://localhost:8083/connectors/demographics-connector/status 2>/dev/null | jq -r '.connector.state' 2>/dev/null)
if [ "$CONNECTOR_STATUS" = "RUNNING" ]; then
    print_status "Debezium connector is running"
else
    print_warning "Debezium connector not running. Setting up..."
    curl -X POST http://localhost:8083/connectors \
        -H "Content-Type: application/json" \
        -d '{
            "name": "demographics-connector",
            "config": {
                "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
                "database.hostname": "postgres",
                "database.port": "5432",
                "database.user": "postgres",
                "database.password": "postgres",
                "database.dbname": "bigdata",
                "database.server.name": "demographics_server",
                "table.include.list": "public.demographics",
                "plugin.name": "pgoutput",
                "slot.name": "debezium_slot",
                "publication.name": "debezium_publication"
            }
        }' > /dev/null 2>&1
    
    sleep 5
    CONNECTOR_STATUS=$(curl -s http://localhost:8083/connectors/demographics-connector/status 2>/dev/null | jq -r '.connector.state' 2>/dev/null)
    if [ "$CONNECTOR_STATUS" = "RUNNING" ]; then
        print_status "Debezium connector started successfully"
    else
        print_error "Failed to start Debezium connector"
    fi
fi

# Check Kafka topics
print_info "Checking Kafka CDC topic..."
KAFKA_MESSAGES=$(docker exec kafka kafka-console-consumer \
    --bootstrap-server localhost:9092 \
    --topic demographics_server.public.demographics \
    --from-beginning \
    --max-messages 1 \
    --timeout-ms 5000 2>/dev/null | wc -l)

if [ "$KAFKA_MESSAGES" -gt 0 ]; then
    print_status "Kafka CDC topic has messages"
else
    print_warning "No messages in Kafka CDC topic yet"
    print_info "Triggering data change to generate CDC events..."
    docker exec postgres psql -U postgres -d bigdata -c "
        UPDATE demographics SET median_age = median_age + 0.1 WHERE city LIKE 'Sample%';
    " > /dev/null 2>&1
    sleep 3
fi

echo ""
echo "🔧 PHASE 3: ENVIRONMENT SETUP"
echo "============================="

# Set AWS environment variables for Flink
print_info "Setting up AWS environment variables..."
export AWS_REGION=us-east-1
export AWS_ACCESS_KEY_ID=DKZjmhls7nwxBN4GJfXC
export AWS_SECRET_ACCESS_KEY=kNuAZodphLEGKHv5EmbyiDt1v5eT0yVErjVFyg0t

# Create MinIO buckets
print_info "Setting up MinIO buckets..."
docker exec minioserver mc mb minio/warehouse --ignore-existing > /dev/null 2>&1
docker exec minioserver mc mb minio/checkpoints --ignore-existing > /dev/null 2>&1
print_status "MinIO buckets created"

# Clean up any existing Flink jobs
print_info "Cleaning up existing Flink jobs..."
EXISTING_JOBS=$(curl -s http://localhost:8081/jobs | jq -r '.jobs[].id' 2>/dev/null)
for job_id in $EXISTING_JOBS; do
    if [ -n "$job_id" ] && [ "$job_id" != "null" ]; then
        print_info "Cancelling existing job: $job_id"
        curl -X PATCH http://localhost:8081/jobs/$job_id?mode=cancel > /dev/null 2>&1
    fi
done

sleep 5

echo ""
echo "🚀 PHASE 4: JOB DEPLOYMENT"
echo "========================="

print_info "Submitting Flink CDC streaming job..."

# Create the SQL job submission
cat > /tmp/cdc_job.sql << 'EOF'
-- Set execution environment
SET 'execution.checkpointing.interval' = '60sec';
SET 'execution.checkpointing.mode' = 'EXACTLY_ONCE';
SET 'execution.checkpointing.timeout' = '10min';
SET 'execution.checkpointing.max-concurrent-checkpoints' = '1';
SET 'state.backend' = 'filesystem';
SET 'state.checkpoints.dir' = 's3a://checkpoints/';
SET 'state.savepoints.dir' = 's3a://checkpoints/savepoints/';

-- AWS S3A Configuration
SET 'fs.s3a.endpoint' = 'http://minioserver:9000';
SET 'fs.s3a.access.key' = 'DKZjmhls7nwxBN4GJfXC';
SET 'fs.s3a.secret.key' = 'kNuAZodphLEGKHv5EmbyiDt1v5eT0yVErjVFyg0t';
SET 'fs.s3a.path.style.access' = 'true';
SET 'fs.s3a.impl' = 'org.apache.hadoop.fs.s3a.S3AFileSystem';

-- Create Nessie Catalog
CREATE CATALOG nessie_catalog WITH (
    'type' = 'iceberg',
    'catalog-impl' = 'org.apache.iceberg.nessie.NessieCatalog',
    'uri' = 'http://nessie:19120/api/v1',
    'ref' = 'main',
    'warehouse' = 's3a://warehouse/',
    'io-impl' = 'org.apache.iceberg.aws.s3.S3FileIO',
    's3.endpoint' = 'http://minioserver:9000',
    's3.access-key-id' = 'DKZjmhls7nwxBN4GJfXC',
    's3.secret-access-key' = 'kNuAZodphLEGKHv5EmbyiDt1v5eT0yVErjVFyg0t',
    's3.path-style-access' = 'true'
);

USE CATALOG nessie_catalog;

-- Create database
CREATE DATABASE IF NOT EXISTS lakehouse;
USE lakehouse;

-- Create Kafka source table
CREATE TABLE demographics_source (
    city STRING,
    state STRING,
    median_age DOUBLE,
    male_population BIGINT,
    female_population BIGINT,
    total_population BIGINT,
    number_of_veterans BIGINT,
    foreign_born BIGINT,
    average_household_size DOUBLE,
    state_code STRING,
    race STRING,
    population_count BIGINT,
    ts TIMESTAMP(3) METADATA FROM 'timestamp',
    WATERMARK FOR ts AS ts - INTERVAL '5' SECOND
) WITH (
    'connector' = 'kafka',
    'topic' = 'demographics_server.public.demographics',
    'properties.bootstrap.servers' = 'kafka:9092',
    'properties.group.id' = 'flink-cdc-consumer',
    'scan.startup.mode' = 'earliest-offset',
    'format' = 'debezium-json'
);

-- Create Iceberg sink table using CREATE TABLE AS SELECT
CREATE TABLE demographics_final AS
SELECT 
    city,
    state,
    median_age,
    male_population,
    female_population,
    total_population,
    number_of_veterans,
    foreign_born,
    average_household_size,
    state_code,
    race,
    population_count,
    ts as event_timestamp,
    PROCTIME() as processing_time
FROM demographics_source;
EOF

# Submit the job
print_info "Executing SQL job..."
docker exec -i flink-sql-client /opt/flink/bin/sql-client.sh embedded < /tmp/cdc_job.sql

# Wait a moment for job to start
sleep 10

# Check if job is running
RUNNING_JOBS=$(curl -s http://localhost:8081/jobs | jq -r '.jobs[] | select(.status=="RUNNING") | .id' 2>/dev/null)
if [ -n "$RUNNING_JOBS" ]; then
    print_status "Flink streaming job is running!"
    for job_id in $RUNNING_JOBS; do
        print_info "Job ID: $job_id"
    done
else
    print_error "No running jobs found. Checking for any jobs..."
    ALL_JOBS=$(curl -s http://localhost:8081/jobs | jq -r '.jobs[] | "\(.id) - \(.status)"' 2>/dev/null)
    if [ -n "$ALL_JOBS" ]; then
        echo "Found jobs:"
        echo "$ALL_JOBS"
    else
        print_error "No jobs found at all. Job submission may have failed."
    fi
fi

echo ""
echo "📊 PHASE 5: INITIAL MONITORING"
echo "=============================="

print_info "Starting initial monitoring phase..."
print_info "Waiting for first checkpoint cycle (60 seconds)..."

# Monitor for 3 minutes
for i in {1..6}; do
    echo ""
    print_info "Monitoring cycle $i/6 ($(date))"
    
    # Check job status
    RUNNING_JOBS=$(curl -s http://localhost:8081/jobs | jq -r '.jobs[] | select(.status=="RUNNING") | .id' 2>/dev/null | wc -l)
    print_info "Running jobs: $RUNNING_JOBS"
    
    # Check MinIO for data files
    DATA_FILES=$(docker exec minioserver mc ls -r minio/warehouse/ 2>/dev/null | grep -v "/$" | wc -l)
    print_info "Data files in MinIO: $DATA_FILES"
    
    if [ "$DATA_FILES" -gt 1 ]; then  # More than just our test file
        print_status "Data files detected! Pipeline is working!"
        break
    fi
    
    if [ $i -lt 6 ]; then
        print_info "Waiting 30 seconds before next check..."
        sleep 30
    fi
done

echo ""
echo "📋 DEPLOYMENT SUMMARY"
echo "===================="

# Final status check
FINAL_JOBS=$(curl -s http://localhost:8081/jobs | jq -r '.jobs[] | "\(.status): \(.id)"' 2>/dev/null)
FINAL_FILES=$(docker exec minioserver mc ls -r minio/warehouse/ 2>/dev/null)

echo "Flink Jobs:"
echo "$FINAL_JOBS"
echo ""
echo "MinIO Files:"
echo "$FINAL_FILES"

echo ""
echo "🎯 NEXT STEPS"
echo "============"
echo "1. Monitor pipeline: ./monitor_cdc_pipeline.sh"
echo "2. Validate data: ./validate_complete_pipeline.sh"
echo "3. Test with Dremio: ./validate_dremio_data.sh"
echo "4. Check Flink UI: http://localhost:8081"
echo "5. Check MinIO Console: http://localhost:9001"

echo ""
print_status "Deployment completed! $(date)"

# Clean up temp file
rm -f /tmp/cdc_job.sql 