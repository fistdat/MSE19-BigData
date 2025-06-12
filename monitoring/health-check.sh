#!/bin/bash

# =============================================================================
# Nessie CDC Lakehouse - Health Check Script
# =============================================================================
# Comprehensive health monitoring for the CDC pipeline
# =============================================================================

set -euo pipefail

# Configuration
FLINK_REST_URL="http://localhost:8081"
KAFKA_BOOTSTRAP_SERVERS="localhost:9092"
KAFKA_TOPIC="demographics_server.public.demographics"
NESSIE_API_URL="http://localhost:19120/api/v2"
MINIO_ENDPOINT="http://localhost:9000"
POSTGRES_HOST="localhost"
POSTGRES_PORT="5432"
POSTGRES_DB="demographics"
POSTGRES_USER="admin"

# Health check results
HEALTH_STATUS="HEALTHY"
ISSUES=()

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

add_issue() {
    ISSUES+=("$1")
    HEALTH_STATUS="UNHEALTHY"
}

# Check Flink cluster health
check_flink_cluster() {
    log_info "Checking Flink cluster health..."
    
    if ! curl -s "$FLINK_REST_URL/overview" > /dev/null; then
        add_issue "Flink cluster is not accessible"
        return 1
    fi
    
    local overview=$(curl -s "$FLINK_REST_URL/overview")
    local running_jobs=$(echo "$overview" | grep -o '"jobs-running":[0-9]*' | cut -d':' -f2)
    local taskmanagers=$(echo "$overview" | grep -o '"taskmanagers":[0-9]*' | cut -d':' -f2)
    local available_slots=$(echo "$overview" | grep -o '"slots-available":[0-9]*' | cut -d':' -f2)
    
    if [[ "$running_jobs" -eq 0 ]]; then
        add_issue "No Flink jobs are running"
    else
        log_success "Flink cluster: $running_jobs job(s) running, $taskmanagers taskmanager(s), $available_slots available slots"
    fi
}

# Check specific CDC job
check_cdc_job() {
    log_info "Checking CDC job status..."
    
    local jobs=$(curl -s "$FLINK_REST_URL/jobs")
    local job_found=false
    
    # Parse jobs and find our CDC job
    if echo "$jobs" | grep -q "nessie-cdc-lakehouse"; then
        job_found=true
        local job_id=$(echo "$jobs" | grep -A5 -B5 "nessie-cdc-lakehouse" | grep -o '"id":"[^"]*"' | cut -d'"' -f4)
        
        if [[ -n "$job_id" ]]; then
            local job_details=$(curl -s "$FLINK_REST_URL/jobs/$job_id")
            local job_state=$(echo "$job_details" | grep -o '"state":"[^"]*"' | cut -d'"' -f4)
            
            case "$job_state" in
                "RUNNING")
                    log_success "CDC job is running (ID: $job_id)"
                    check_job_metrics "$job_id"
                    ;;
                "FAILED")
                    add_issue "CDC job has failed (ID: $job_id)"
                    ;;
                *)
                    add_issue "CDC job is in unexpected state: $job_state (ID: $job_id)"
                    ;;
            esac
        fi
    fi
    
    if [[ "$job_found" == false ]]; then
        add_issue "CDC job not found"
    fi
}

# Check job metrics
check_job_metrics() {
    local job_id=$1
    log_info "Checking job metrics..."
    
    local metrics=$(curl -s "$FLINK_REST_URL/jobs/$job_id/metrics?get=numRecordsIn,numRecordsOut,numRecordsInPerSecond,numRecordsOutPerSecond")
    
    if [[ -n "$metrics" ]]; then
        log_info "Job metrics retrieved successfully"
        # Could parse and validate specific metrics here
    else
        log_warning "Could not retrieve job metrics"
    fi
}

# Check Kafka connectivity and topic
check_kafka() {
    log_info "Checking Kafka connectivity..."
    
    # Check if Kafka is accessible
    if ! docker exec kafka kafka-topics --bootstrap-server localhost:9092 --list > /dev/null 2>&1; then
        add_issue "Kafka is not accessible"
        return 1
    fi
    
    # Check if our topic exists
    if docker exec kafka kafka-topics --bootstrap-server localhost:9092 --list | grep -q "$KAFKA_TOPIC"; then
        log_success "Kafka topic '$KAFKA_TOPIC' exists"
        
        # Check recent messages
        local message_count=$(docker exec kafka kafka-console-consumer \
            --bootstrap-server localhost:9092 \
            --topic "$KAFKA_TOPIC" \
            --timeout-ms 5000 \
            --from-beginning 2>/dev/null | wc -l || echo "0")
        
        log_info "Kafka topic has $message_count messages"
    else
        add_issue "Kafka topic '$KAFKA_TOPIC' does not exist"
    fi
}

# Check PostgreSQL source
check_postgresql() {
    log_info "Checking PostgreSQL source..."
    
    if docker exec postgres pg_isready -h localhost -p 5432 -U admin > /dev/null 2>&1; then
        log_success "PostgreSQL is accessible"
        
        # Check demographics table
        local record_count=$(docker exec postgres psql -U admin -d demographics -t -c "SELECT COUNT(*) FROM demographics;" 2>/dev/null | tr -d ' ' || echo "0")
        log_info "Demographics table has $record_count records"
    else
        add_issue "PostgreSQL is not accessible"
    fi
}

# Check Nessie catalog
check_nessie() {
    log_info "Checking Nessie catalog..."
    
    if curl -s "$NESSIE_API_URL/config" > /dev/null; then
        log_success "Nessie API is accessible"
        
        # Check if our databases exist
        local trees=$(curl -s "$NESSIE_API_URL/trees" || echo "{}")
        if echo "$trees" | grep -q "main"; then
            log_success "Nessie main branch exists"
        else
            log_warning "Nessie main branch not found"
        fi
    else
        add_issue "Nessie API is not accessible"
    fi
}

# Check MinIO storage
check_minio() {
    log_info "Checking MinIO storage..."
    
    if docker exec minioserver mc ls minio/warehouse/ > /dev/null 2>&1; then
        log_success "MinIO warehouse is accessible"
        
        # Check for recent data files
        local file_count=$(docker exec minioserver mc ls minio/warehouse/ --recursive | wc -l || echo "0")
        log_info "MinIO warehouse has $file_count files"
    else
        add_issue "MinIO warehouse is not accessible"
    fi
}

# Check end-to-end data flow
check_data_flow() {
    log_info "Checking end-to-end data flow..."
    
    # Insert test record
    local test_city="HealthCheck_$(date +%s)"
    
    if docker exec postgres psql -U admin -d demographics -c \
        "INSERT INTO demographics (city, state, median_age, male_population, female_population, total_population, number_of_veterans, foreign_born, average_household_size, state_code, race, count) VALUES ('$test_city', 'TestState', 30.0, 150, 150, 300, 15, 10, 2.5, 'TS', 'Test', 300);" > /dev/null 2>&1; then
        
        log_success "Test record inserted into PostgreSQL"
        
        # Wait a bit for CDC to process
        sleep 10
        
        # Check if it appears in Kafka
        if docker exec kafka kafka-console-consumer \
            --bootstrap-server localhost:9092 \
            --topic "$KAFKA_TOPIC" \
            --timeout-ms 5000 \
            --from-beginning 2>/dev/null | grep -q "$test_city"; then
            log_success "Test record found in Kafka"
        else
            log_warning "Test record not found in Kafka (may take time to propagate)"
        fi
    else
        add_issue "Failed to insert test record into PostgreSQL"
    fi
}

# Generate health report
generate_report() {
    echo ""
    echo "=============================================="
    echo "         HEALTH CHECK REPORT"
    echo "=============================================="
    echo "Timestamp: $(date)"
    echo "Status: $HEALTH_STATUS"
    echo ""
    
    if [[ "$HEALTH_STATUS" == "HEALTHY" ]]; then
        log_success "All systems are healthy!"
    else
        log_error "Issues detected:"
        for issue in "${ISSUES[@]}"; do
            echo "  - $issue"
        done
    fi
    
    echo ""
    echo "=============================================="
}

# Main health check function
main() {
    log_info "Starting comprehensive health check..."
    
    # Run all health checks
    check_flink_cluster
    check_cdc_job
    check_kafka
    check_postgresql
    check_nessie
    check_minio
    check_data_flow
    
    # Generate report
    generate_report
    
    # Exit with appropriate code
    if [[ "$HEALTH_STATUS" == "HEALTHY" ]]; then
        exit 0
    else
        exit 1
    fi
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi