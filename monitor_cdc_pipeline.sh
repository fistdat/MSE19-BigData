#!/bin/bash

echo "📊 CDC PIPELINE CONTINUOUS MONITORING"
echo "====================================="
echo "$(date): Starting continuous monitoring..."

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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

# Function to get job details
get_job_details() {
    local job_id=$1
    local job_info=$(curl -s http://localhost:8081/jobs/$job_id 2>/dev/null)
    local job_name=$(echo "$job_info" | jq -r '.name' 2>/dev/null)
    local job_status=$(echo "$job_info" | jq -r '.state' 2>/dev/null)
    local start_time=$(echo "$job_info" | jq -r '.["start-time"]' 2>/dev/null)
    local duration=$(echo "$job_info" | jq -r '.duration' 2>/dev/null)
    
    echo "   Job: $job_name"
    echo "   Status: $job_status"
    echo "   Duration: $duration ms"
}

# Function to check checkpoint status
check_checkpoints() {
    local job_id=$1
    local checkpoint_info=$(curl -s http://localhost:8081/jobs/$job_id/checkpoints 2>/dev/null)
    local latest_checkpoint=$(echo "$checkpoint_info" | jq -r '.latest.completed.id' 2>/dev/null)
    local checkpoint_count=$(echo "$checkpoint_info" | jq -r '.counts.completed' 2>/dev/null)
    
    if [ "$latest_checkpoint" != "null" ] && [ -n "$latest_checkpoint" ]; then
        echo "   Latest Checkpoint: $latest_checkpoint"
        echo "   Completed Checkpoints: $checkpoint_count"
        return 0
    else
        echo "   No checkpoints completed yet"
        return 1
    fi
}

# Function to analyze MinIO content
analyze_minio_content() {
    local warehouse_content=$(docker exec minioserver mc ls -r minio/warehouse/ 2>/dev/null)
    local checkpoint_content=$(docker exec minioserver mc ls -r minio/checkpoints/ 2>/dev/null)
    
    echo "📦 MinIO Warehouse Content:"
    if [ -n "$warehouse_content" ]; then
        echo "$warehouse_content" | while read -r line; do
            if [[ $line == *".parquet"* ]]; then
                echo -e "   ${GREEN}📄 $line${NC}"
            elif [[ $line == *"metadata"* ]]; then
                echo -e "   ${YELLOW}📋 $line${NC}"
            else
                echo "   📁 $line"
            fi
        done
        
        # Count different file types
        local parquet_count=$(echo "$warehouse_content" | grep -c "\.parquet" || echo "0")
        local metadata_count=$(echo "$warehouse_content" | grep -c "metadata" || echo "0")
        local total_files=$(echo "$warehouse_content" | grep -v "/$" | wc -l)
        
        echo ""
        echo "   Summary: $total_files total files ($parquet_count Parquet, $metadata_count metadata)"
    else
        echo "   No files in warehouse"
    fi
    
    echo ""
    echo "🔄 MinIO Checkpoints:"
    if [ -n "$checkpoint_content" ]; then
        local checkpoint_files=$(echo "$checkpoint_content" | wc -l)
        echo "   $checkpoint_files checkpoint files"
    else
        echo "   No checkpoint files"
    fi
}

# Function to check Kafka lag
check_kafka_lag() {
    local consumer_group="flink-cdc-consumer"
    local topic="demographics_server.public.demographics"
    
    # Get consumer group info
    local lag_info=$(docker exec kafka kafka-consumer-groups.sh \
        --bootstrap-server localhost:9092 \
        --group $consumer_group \
        --describe 2>/dev/null | grep $topic)
    
    if [ -n "$lag_info" ]; then
        echo "📮 Kafka Consumer Lag:"
        echo "$lag_info" | while read -r line; do
            local lag=$(echo "$line" | awk '{print $5}')
            if [ "$lag" = "0" ]; then
                echo -e "   ${GREEN}✅ No lag - consumer is up to date${NC}"
            elif [ "$lag" -gt 0 ] 2>/dev/null; then
                echo -e "   ${YELLOW}⚠️  Lag: $lag messages${NC}"
            fi
        done
    else
        echo "📮 Kafka Consumer: No active consumer group found"
    fi
}

# Function to trigger test data
trigger_test_data() {
    print_info "Triggering test data update..."
    docker exec postgres psql -U postgres -d bigdata -c "
        UPDATE demographics 
        SET median_age = median_age + RANDOM() * 0.1,
            male_population = male_population + FLOOR(RANDOM() * 10)
        WHERE city LIKE '%Sample%' OR city LIKE '%Test%';
        
        INSERT INTO demographics (city, state, median_age, male_population, female_population, total_population, number_of_veterans, foreign_born, average_household_size, state_code, race, population_count)
        VALUES ('Monitor Test ' || EXTRACT(EPOCH FROM NOW()), 'Test State', 30 + RANDOM() * 20, 800 + FLOOR(RANDOM() * 200), 900 + FLOOR(RANDOM() * 200), 1700 + FLOOR(RANDOM() * 400), 40 + FLOOR(RANDOM() * 20), 150 + FLOOR(RANDOM() * 50), 2.0 + RANDOM(), 'MT', 'Test', 400 + FLOOR(RANDOM() * 100))
        ON CONFLICT DO NOTHING;
    " > /dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        print_status "Test data updated successfully"
    else
        print_warning "Failed to update test data"
    fi
}

# Main monitoring loop
MONITOR_COUNT=0
DATA_FILES_DETECTED=false
LAST_FILE_COUNT=0

echo ""
print_info "Starting monitoring loop (Ctrl+C to stop)..."
print_info "Monitoring interval: 30 seconds"
echo ""

while true; do
    MONITOR_COUNT=$((MONITOR_COUNT + 1))
    echo "════════════════════════════════════════════════════════════════"
    print_highlight "MONITORING CYCLE #$MONITOR_COUNT - $(date)"
    echo "════════════════════════════════════════════════════════════════"
    
    # Check Flink jobs
    echo "⚡ Flink Job Status:"
    JOBS=$(curl -s http://localhost:8081/jobs 2>/dev/null | jq -r '.jobs[]' 2>/dev/null)
    if [ -n "$JOBS" ]; then
        echo "$JOBS" | jq -r '"\(.id) - \(.status)"' | while read -r job_line; do
            job_id=$(echo "$job_line" | cut -d' ' -f1)
            job_status=$(echo "$job_line" | cut -d' ' -f3)
            
            if [ "$job_status" = "RUNNING" ]; then
                echo -e "   ${GREEN}🟢 Job $job_id: $job_status${NC}"
                get_job_details "$job_id"
                check_checkpoints "$job_id"
            else
                echo -e "   ${RED}🔴 Job $job_id: $job_status${NC}"
            fi
        done
    else
        print_error "No Flink jobs found"
    fi
    
    echo ""
    
    # Analyze MinIO content
    analyze_minio_content
    
    # Count current data files
    CURRENT_FILE_COUNT=$(docker exec minioserver mc ls -r minio/warehouse/ 2>/dev/null | grep -v "/$" | wc -l)
    
    # Check if new files appeared
    if [ "$CURRENT_FILE_COUNT" -gt "$LAST_FILE_COUNT" ]; then
        print_status "New files detected! ($LAST_FILE_COUNT → $CURRENT_FILE_COUNT)"
        if [ "$CURRENT_FILE_COUNT" -gt 1 ] && [ "$DATA_FILES_DETECTED" = false ]; then
            DATA_FILES_DETECTED=true
            print_status "🎉 DATA FILES SUCCESSFULLY CREATED! Pipeline is working!"
            echo ""
            echo "🎯 Ready for next steps:"
            echo "   1. Run validation: ./validate_complete_pipeline.sh"
            echo "   2. Test with Dremio: ./validate_dremio_data.sh"
            echo ""
        fi
    fi
    LAST_FILE_COUNT=$CURRENT_FILE_COUNT
    
    echo ""
    
    # Check Kafka consumer lag
    check_kafka_lag
    
    echo ""
    
    # Trigger test data every 5 cycles (2.5 minutes)
    if [ $((MONITOR_COUNT % 5)) -eq 0 ]; then
        trigger_test_data
        echo ""
    fi
    
    # Show summary
    echo "📊 SUMMARY:"
    RUNNING_JOBS=$(curl -s http://localhost:8081/jobs 2>/dev/null | jq -r '.jobs[] | select(.status=="RUNNING")' 2>/dev/null | wc -l)
    echo "   Running Jobs: $RUNNING_JOBS"
    echo "   Data Files: $CURRENT_FILE_COUNT"
    echo "   Pipeline Status: $([ "$DATA_FILES_DETECTED" = true ] && echo "✅ WORKING" || echo "⏳ WAITING")"
    
    echo ""
    print_info "Next check in 30 seconds... (Ctrl+C to stop)"
    
    # Wait with interrupt handling
    for i in {1..30}; do
        sleep 1
        # Check for Ctrl+C
        if ! kill -0 $$ 2>/dev/null; then
            break
        fi
    done
    
    echo ""
done

echo ""
print_info "Monitoring stopped." 